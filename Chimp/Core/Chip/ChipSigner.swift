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
}
