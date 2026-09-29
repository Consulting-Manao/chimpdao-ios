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

/// Fait signer un digest par la carte présente, après avoir vérifié que c'est bien la carte attendue.
/// Implémenté par `NFCChipSigner` (Core NFC) et `MockChipSigner` (tests, simulateur).
protocol ChipSigner {
    func sign(digest: Data, expectedKey: ChipPublicKey, pin: String?) async throws -> ChipSignedDigest
}

/// Signature sur une carte déjà connectée : même détection que la lecture, relecture de la clé, puis signature.
enum ChipSigning {
    static func sign(
        _ transport: some APDUTransport,
        digest: Data,
        expectedKey: ChipPublicKey,
        pin: String?
    ) async throws -> ChipSignedDigest {
        guard digest.count == 32 else { throw ChipError.malformedResponse("digest must be 32 bytes, got \(digest.count)") }
        let card = try await ChipDetector.readKey(transport)
        // Deux taps (lecture, puis signature) : on vérifie que c'est la même carte avant de lui faire signer quoi que ce soit.
        guard card.publicKey == expectedKey else { throw ChipError.wrongCard }
        switch card.kind {
        case .infineon2Go:
            return try await Infineon2Go.sign(transport, digest: digest, pin: pin)
        case .duox:
            return try await Duox.sign(transport, digest: digest)
        }
    }
}

/// Signature par Core NFC : une feuille NFC, une carte.
struct NFCChipSigner: ChipSigner {
    func sign(digest: Data, expectedKey: ChipPublicKey, pin: String?) async throws -> ChipSignedDigest {
        try await NFCTagSession.run(
            alertMessage: String(localized: "Hold your card near the top of your iPhone."),
            successMessage: String(localized: "Card read.")
        ) { transport in
            try await ChipSigning.sign(transport, digest: digest, expectedKey: expectedKey, pin: pin)
        }
    }
}

/// Faux signataire : renvoie une signature fixe (invalide sur le réseau), pour faire tourner l'interface.
struct MockChipSigner: ChipSigner {
    var outcome: Result<ChipSignedDigest, ChipError> = .success(.secp256k1(signature: Data(repeating: 0x11, count: 32) + Data(repeating: 0x22, count: 32)))
    var delay: Duration = .milliseconds(700)

    func sign(digest: Data, expectedKey: ChipPublicKey, pin: String?) async throws -> ChipSignedDigest {
        try await Task.sleep(for: delay)
        return try outcome.get()
    }
}
