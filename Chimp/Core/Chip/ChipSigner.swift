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
    /// Onboarding d'une Infineon (étape 4) : dans le **même tap**, définit le PIN (SET PIN, qui renvoie le PUK une seule
    /// fois), puis signe les digests avec ce PIN. Voir `ChipSigning.setPINAndSign`.
    func setPINAndSign(digests: [Data], expectedKey: ChipPublicKey, newPIN: String) async throws -> PINSetupSignatures
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
        guard !digests.isEmpty else { throw ChipError.malformedResponse("nothing to sign") }
        for digest in digests where digest.count != 32 {
            throw ChipError.malformedResponse("digest must be 32 bytes, got \(digest.count)")
        }
        let card = try await ChipDetector.readKey(transport)
        // Deux taps (lecture, puis signature) : on vérifie que c'est la même carte avant de lui faire signer quoi que ce soit.
        guard card.publicKey == expectedKey else { throw ChipError.wrongCard }
        var signatures: [ChipSignedDigest] = []
        for digest in digests {
            switch card.kind {
            case .infineon2Go:
                signatures.append(try await Infineon2Go.sign(transport, digest: digest, pin: pin))
            case .duox:
                signatures.append(try await Duox.sign(transport, digest: digest))
            }
        }
        return signatures
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

    func setPINAndSign(digests: [Data], expectedKey: ChipPublicKey, newPIN: String) async throws -> PINSetupSignatures {
        try await NFCTagSession.run(
            alertMessage: String(localized: "Hold your card near the top of your iPhone."),
            successMessage: String(localized: "Card read.")
        ) { transport in
            try await ChipSigning.setPINAndSign(transport, digests: digests, expectedKey: expectedKey, newPIN: newPIN)
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

    /// PUK factice, visiblement faux.
    static let fakePUK = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77])

    func setPINAndSign(digests: [Data], expectedKey: ChipPublicKey, newPIN: String) async throws -> PINSetupSignatures {
        PINSetupSignatures(puk: Self.fakePUK, signatures: try await sign(digests: digests, expectedKey: expectedKey, pin: newPIN))
    }
}
