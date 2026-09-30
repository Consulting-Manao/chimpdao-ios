import Foundation

/// Ce que la puce renvoie pour un digest de 32 octets, déjà mis en forme pour Soroban.
enum ChipSignedDigest: Equatable, Sendable {
    /// Infineon : `r ‖ s` en low-S. Le `recovery_id` n'est pas fourni par la puce : il se cherche ensuite.
    case secp256k1(signature: Data)
    /// DUOX : `r ‖ s` en low-S et `RndB`, l'aléa de 16 octets choisi par la puce (Internal Authenticate).
    case p256(signature: Data, rndB: Data)

    var signature: Data {
        switch self {
        case .secp256k1(let signature), .p256(let signature, _): signature
        }
    }
}

/// Fait signer un ou plusieurs digests par la carte présente, **en un seul tap**, après avoir vérifié que
/// c'est bien la carte attendue. Implémenté par `NFCChipSigner` (Core NFC) et `MockChipSigner` (tests, simulateur).
///
/// Plusieurs digests : adaptation à l'iPhone (DESIGN_NOTES §12). Le terminal garde la carte posée sur le lecteur
/// entre deux signatures ; sur iPhone, chaque signature demanderait un nouveau tap. L'onboarding fait donc signer
/// la preuve de possession et `set_owner` dans la même session NFC. Les signatures sont renvoyées dans l'ordre des digests.
protocol ChipSigner {
    func sign(digests: [Data], expectedKey: ChipPublicKey, pin: String?) async throws -> [ChipSignedDigest]
    /// Paiement : la carte posée doit être **une** de `acceptedKeys` (la carte du wallet, ou n'importe quelle carte du
    /// Main account). Sa clé est lue et comparée **avant** tout PIN : une autre carte ne perd jamais un essai
    /// (`ChipError.cardNotAccepted`). Renvoie la carte qui a signé (sa clé va dans `AccountAuth`) et les signatures.
    func sign(digests: [Data], acceptedKeys: [ChipPublicKey], pin: String?) async throws -> CardSignatures
    /// Premier tap de l'ordre « tap puis PIN » : lit la carte (une de `acceptedKeys`, sinon `cardNotAccepted`) ; si elle
    /// n'a **pas** de PIN actif, elle signe dans la même session (un seul tap) ; sinon rien n'est signé ni envoyé à la
    /// carte au-delà de la lecture, et l'app demandera le PIN puis un second tap.
    func readOrSign(digests: [Data], acceptedKeys: [ChipPublicKey]) async throws -> ReadOrSign
    /// Onboarding d'une Infineon (étape 4) : dans le **même tap**, définit le PIN (SET PIN, qui renvoie le PUK une seule
    /// fois), puis signe les digests avec ce PIN. Voir `ChipSigning.setPINAndSign`.
    func setPINAndSign(digests: [Data], expectedKey: ChipPublicKey, newPIN: String) async throws -> PINSetupSignatures
    /// Reconnexion d'une Infineon déjà liée à un compte (décision de Barth du 2026-09-29) : la carte vérifie le PIN, rien
    /// n'est signé. Voir `ChipSigning.verifyPIN`.
    func verifyPIN(expectedKey: ChipPublicKey, pin: String) async throws
    /// Changer le PIN d'une Infineon (lecture de la clé, puis CHANGE PIN) ; renvoie le nouveau PUK.
    func changePIN(expectedKey: ChipPublicKey, currentPIN: String, newPIN: String) async throws -> Data
}

extension ChipSigner {
    /// Faux signataires des tests qui ne changent pas de PIN : refus, sans rien envoyer.
    func changePIN(expectedKey: ChipPublicKey, currentPIN: String, newPIN: String) async throws -> Data {
        throw ChipError.pinUnsupported
    }
}

/// SET PIN a réussi (le PIN est défini sur la carte, pour toujours) mais une signature a échoué juste après
/// (carte retirée, délai…). Le PUK n'est renvoyé qu'une fois : il voyage avec l'erreur pour ne jamais être perdu.
struct PINSetButSigningFailed: Error, Equatable {
    let puk: Data
    let underlying: ChipError
}

extension PINSetButSigningFailed: LocalizedError {
    var errorDescription: String? {
        "The PIN is set on the card, but signing failed: \(underlying.errorDescription ?? "\(underlying)")"
    }
}

/// Résultat d'une signature par « une carte parmi plusieurs ».
struct CardSignatures: Equatable, Sendable {
    /// La carte qui a signé, telle qu'elle vient d'être lue.
    let card: ChipKeyInfo
    let signatures: [ChipSignedDigest]
}

/// Résultat de `readOrSign`.
enum ReadOrSign: Equatable, Sendable {
    /// La carte a un PIN : lue seulement (clé, type), rien n'est signé.
    case needsPIN(ChipKeyInfo)
    /// La carte n'a pas de PIN : elle a signé dans le même tap.
    case signed(CardSignatures)
}

/// Résultat de `setPINAndSign`.
struct PINSetupSignatures: Equatable, Sendable {
    /// Code de déblocage (8 octets), à montrer **une seule fois**, jamais enregistré ni journalisé.
    /// `nil` : la carte avait déjà un PIN au moment du tap (un essai précédent l'a défini, sa réponse s'est perdue),
    /// le PIN a seulement été vérifié et il n'y a pas de code à montrer.
    let puk: Data?
    let signatures: [ChipSignedDigest]
}

extension ChipSigner {
    /// Un seul digest.
    func sign(digest: Data, expectedKey: ChipPublicKey, pin: String?) async throws -> ChipSignedDigest {
        let signed = try await sign(digests: [digest], expectedKey: expectedKey, pin: pin)
        guard signed.count == 1, let first = signed.first else {
            throw ChipError.malformedResponse("expected 1 signature, got \(signed.count)")
        }
        return first
    }
}

/// Signature sur une carte déjà connectée : même détection que la lecture, relecture de la clé, puis signature.
enum ChipSigning {
    static func sign(
        _ transport: some APDUTransport,
        digest: Data,
        expectedKey: ChipPublicKey,
        pin: String?
    ) async throws -> ChipSignedDigest {
        try await sign(transport, digests: [digest], expectedKey: expectedKey, pin: pin)[0]
    }

    /// Plusieurs digests sur la même carte, dans la même session. Chaque signature refait la séquence complète
    /// du bridge (Infineon : SELECT → VERIFY PIN → SIGN ; DUOX : Select PICC → Internal Authenticate),
    /// comme `signDigest` qui refait SELECT avant chaque opération. La première erreur arrête tout.
    static func sign(
        _ transport: some APDUTransport,
        digests: [Data],
        expectedKey: ChipPublicKey,
        pin: String?
    ) async throws -> [ChipSignedDigest] {
        do {
            return try await sign(transport, digests: digests, acceptedKeys: [expectedKey], pin: pin).signatures
        } catch ChipError.cardNotAccepted {
            // Deux taps (lecture, puis signature) : ce n'est pas la carte lue au premier.
            throw ChipError.wrongCard
        }
    }

    /// Signature par une carte parmi `acceptedKeys` : lecture de la clé → comparaison → seulement alors VERIFY PIN
    /// et SIGN. Une carte refusée ne reçoit **aucune** commande après la lecture de sa clé (ni PIN, ni signature).
    ///
    /// VERIFY PIN n'est envoyé que si la carte a un PIN actif (octet 0 du SELECT). Écart minimal avec le bridge, qui
    /// l'envoie dès qu'un PIN est fourni : depuis le Main account, le PIN est saisi avant de savoir quelle carte sera
    /// tapée, et une carte sans PIN (ou une DUOX) n'a rien à vérifier.
    static func sign(
        _ transport: some APDUTransport,
        digests: [Data],
        acceptedKeys: [ChipPublicKey],
        pin: String?
    ) async throws -> CardSignatures {
        guard !digests.isEmpty else { throw ChipError.malformedResponse("nothing to sign") }
        for digest in digests where digest.count != 32 {
            throw ChipError.malformedResponse("digest must be 32 bytes, got \(digest.count)")
        }
        let card = try await ChipDetector.readKey(transport)
        guard acceptedKeys.contains(card.publicKey) else { throw ChipError.cardNotAccepted(tapped: card.publicKey) }
        var signatures: [ChipSignedDigest] = []
        for digest in digests {
            switch card.kind {
            case .infineon2Go:
                signatures.append(try await Infineon2Go.sign(transport, digest: digest, pin: card.pinActive ? pin : nil))
            case .duox:
                signatures.append(try await Duox.sign(transport, digest: digest))
            }
        }
        return CardSignatures(card: card, signatures: signatures)
    }

    /// `readOrSign` sur une carte connectée : lecture de la clé → comparaison → carte avec PIN actif : on s'arrête là
    /// (aucune commande de plus) ; sinon SIGN sans PIN (DUOX : Internal Authenticate), comme `sign(..., pin: nil)`.
    static func readOrSign(
        _ transport: some APDUTransport,
        digests: [Data],
        acceptedKeys: [ChipPublicKey]
    ) async throws -> ReadOrSign {
        guard !digests.isEmpty else { throw ChipError.malformedResponse("nothing to sign") }
        for digest in digests where digest.count != 32 {
            throw ChipError.malformedResponse("digest must be 32 bytes, got \(digest.count)")
        }
        let card = try await ChipDetector.readKey(transport)
        guard acceptedKeys.contains(card.publicKey) else { throw ChipError.cardNotAccepted(tapped: card.publicKey) }
        if card.pinActive { return .needsPIN(card) }
        var signatures: [ChipSignedDigest] = []
        for digest in digests {
            switch card.kind {
            case .infineon2Go:
                signatures.append(try await Infineon2Go.sign(transport, digest: digest, pin: nil))
            case .duox:
                signatures.append(try await Duox.sign(transport, digest: digest))
            }
        }
        return .signed(CardSignatures(card: card, signatures: signatures))
    }

    /// SET PIN puis signatures, sur la carte attendue, dans la même session :
    /// lecture de la clé (même carte ?) → SELECT → SET PIN (PUK) → pour chaque digest SELECT → VERIFY PIN → SIGN.
    /// Si la carte a **déjà** un PIN (SET PIN d'un essai précédent dont la réponse s'est perdue), SET PIN n'est pas
    /// envoyé : le PIN donné est vérifié comme pour une signature normale, et `puk` vaut `nil`.
    static func setPINAndSign(
        _ transport: some APDUTransport,
        digests: [Data],
        expectedKey: ChipPublicKey,
        newPIN: String
    ) async throws -> PINSetupSignatures {
        guard !digests.isEmpty else { throw ChipError.malformedResponse("nothing to sign") }
        for digest in digests where digest.count != 32 {
            throw ChipError.malformedResponse("digest must be 32 bytes, got \(digest.count)")
        }
        _ = try Infineon2Go.setPINAPDU(pin: newPIN)
        let card = try await ChipDetector.readKey(transport)
        guard card.publicKey == expectedKey else { throw ChipError.wrongCard }
        guard card.kind == .infineon2Go else { throw ChipError.pinUnsupported }
        var puk: Data?
        if !card.pinActive {
            puk = try await Infineon2Go.setPIN(transport, pin: newPIN)
        }
        var signatures: [ChipSignedDigest] = []
        do {
            for digest in digests {
                signatures.append(try await Infineon2Go.sign(transport, digest: digest, pin: newPIN))
            }
        } catch let error as ChipError {
            // Le PIN est déjà écrit sur la carte : on ne perd jamais le PUK, même si la suite échoue.
            if let puk { throw PINSetButSigningFailed(puk: puk, underlying: error) }
            throw error
        }
        return PINSetupSignatures(puk: puk, signatures: signatures)
    }

    /// Reconnexion : lecture de la clé (même carte qu'en A2 ?) → SELECT → VERIFY PIN. Rien n'est signé.
    /// Adaptation à l'iPhone (DESIGN_NOTES §13) : le terminal se reconnecte par simple lecture ; Barth demande le PIN
    /// d'une Infineon (2026-09-29). Une carte sans PIN actif ou une DUOX est refusée **sans** VERIFY PIN : l'app ne
    /// demande le PIN que si la lecture d'A2 a dit « PIN actif », et une Infineon ne perd jamais son PIN.
    /// Un PIN faux coûte un essai à la carte (`63 Cx`), comme pour une signature.
    static func verifyPIN(_ transport: some APDUTransport, expectedKey: ChipPublicKey, pin: String) async throws {
        _ = try Infineon2Go.verifyPINAPDU(pin: pin)
        let card = try await ChipDetector.readKey(transport)
        guard card.publicKey == expectedKey else { throw ChipError.wrongCard }
        guard card.kind == .infineon2Go, card.pinActive else { throw ChipError.pinUnsupported }
        try await Infineon2Go.verifyPIN(transport, pin: pin)
    }
}

/// Signature par Core NFC : une feuille NFC, une carte.
struct NFCChipSigner: ChipSigner {
    func sign(digests: [Data], expectedKey: ChipPublicKey, pin: String?) async throws -> [ChipSignedDigest] {
        try await NFCTagSession.run(
            alertMessage: String(localized: "Hold your card near the top of your iPhone."),
            successMessage: String(localized: "Card read.")
        ) { transport in
            try await ChipSigning.sign(transport, digests: digests, expectedKey: expectedKey, pin: pin)
        }
    }

    func sign(digests: [Data], acceptedKeys: [ChipPublicKey], pin: String?) async throws -> CardSignatures {
        try await NFCTagSession.run(
            alertMessage: String(localized: "Hold your card near the top of your iPhone."),
            successMessage: String(localized: "Card read.")
        ) { transport in
            try await ChipSigning.sign(transport, digests: digests, acceptedKeys: acceptedKeys, pin: pin)
        }
    }

    func readOrSign(digests: [Data], acceptedKeys: [ChipPublicKey]) async throws -> ReadOrSign {
        try await NFCTagSession.run(
            alertMessage: String(localized: "Hold your card near the top of your iPhone."),
            successMessage: String(localized: "Card read.")
        ) { transport in
            try await ChipSigning.readOrSign(transport, digests: digests, acceptedKeys: acceptedKeys)
        }
    }

    func setPINAndSign(digests: [Data], expectedKey: ChipPublicKey, newPIN: String) async throws -> PINSetupSignatures {
        try await NFCTagSession.run(
            alertMessage: String(localized: "Hold your card near the top of your iPhone."),
            successMessage: String(localized: "Card read.")
        ) { transport in
            try await ChipSigning.setPINAndSign(transport, digests: digests, expectedKey: expectedKey, newPIN: newPIN)
        }
    }

    func verifyPIN(expectedKey: ChipPublicKey, pin: String) async throws {
        try await NFCTagSession.run(
            alertMessage: String(localized: "Hold your card near the top of your iPhone."),
            successMessage: String(localized: "Card read.")
        ) { transport in
            try await ChipSigning.verifyPIN(transport, expectedKey: expectedKey, pin: pin)
        }
    }

    func changePIN(expectedKey: ChipPublicKey, currentPIN: String, newPIN: String) async throws -> Data {
        try await NFCTagSession.run(
            alertMessage: String(localized: "Keep your card still until it's done."),
            successMessage: String(localized: "PIN changed.")
        ) { transport in
            try await ChipSigning.changePIN(transport, expectedKey: expectedKey, currentPIN: currentPIN, newPIN: newPIN)
        }
    }
}

/// Faux signataire : renvoie une signature fixe (invalide sur le réseau) pour chaque digest, pour faire tourner l'interface.
struct MockChipSigner: ChipSigner {
    var outcome: Result<ChipSignedDigest, ChipError> = .success(.secp256k1(signature: Data(repeating: 0x11, count: 32) + Data(repeating: 0x22, count: 32)))
    var delay: Duration = .milliseconds(700)

    func sign(digests: [Data], expectedKey: ChipPublicKey, pin: String?) async throws -> [ChipSignedDigest] {
        try await Task.sleep(for: delay)
        let signed = try outcome.get()
        return digests.map { _ in signed }
    }

    /// La première carte acceptée signe ; son type suit la courbe de la signature factice.
    func sign(digests: [Data], acceptedKeys: [ChipPublicKey], pin: String?) async throws -> CardSignatures {
        guard let key = acceptedKeys.first else { throw ChipError.malformedResponse("no accepted card") }
        let signatures = try await sign(digests: digests, expectedKey: key, pin: pin)
        let kind: ChipKind = if case .p256 = signatures.first { .duox } else { .infineon2Go }
        return CardSignatures(card: ChipKeyInfo(kind: kind, publicKey: key, pinActive: kind == .infineon2Go), signatures: signatures)
    }

    /// Carte factice avec PIN (Infineon) : lue seulement ; sans PIN (signature P-256) : signe.
    func readOrSign(digests: [Data], acceptedKeys: [ChipPublicKey]) async throws -> ReadOrSign {
        let signed = try await sign(digests: digests, acceptedKeys: acceptedKeys, pin: nil)
        return signed.card.pinActive ? .needsPIN(signed.card) : .signed(signed)
    }

    /// PUK factice, visiblement faux.
    static let fakePUK = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77])

    func setPINAndSign(digests: [Data], expectedKey: ChipPublicKey, newPIN: String) async throws -> PINSetupSignatures {
        PINSetupSignatures(puk: Self.fakePUK, signatures: try await sign(digests: digests, expectedKey: expectedKey, pin: newPIN))
    }

    /// Le faux PIN est accepté si `outcome` réussit (même délai qu'un tap).
    func verifyPIN(expectedKey: ChipPublicKey, pin: String) async throws {
        try await Task.sleep(for: delay)
        _ = try outcome.get()
    }

    /// Faux changement : PUK factice si `outcome` réussit (même délai qu'un tap).
    func changePIN(expectedKey: ChipPublicKey, currentPIN: String, newPIN: String) async throws -> Data {
        try await Task.sleep(for: delay)
        _ = try outcome.get()
        return Self.fakePUK
    }
}
