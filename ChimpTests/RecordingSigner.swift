import Foundation
import Testing
@testable import ChimpDAO

/// Faux signataire : garde chaque appel (digests, carte attendue, PIN) et renvoie une signature fixe ou une erreur.
final class RecordingSigner: ChipSigner, @unchecked Sendable {
    struct Call {
        let digests: [Data]
        let expectedKey: ChipPublicKey
        let pin: String?
    }

    private(set) var calls: [Call] = []
    let error: ChipError?

    init(error: ChipError? = nil) { self.error = error }

    /// Appels à SET PIN (onboarding réel) : le PIN transmis.
    private(set) var newPINs: [String] = []
    /// Erreur à renvoyer à la place de `setPINAndSign` (ex. : PIN défini puis signature ratée).
    var setPINError: Error?
    /// PUK renvoyé par le faux SET PIN (`nil` : la carte avait déjà un PIN).
    var puk: Data? = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04])

    func sign(digests: [Data], expectedKey: ChipPublicKey, pin: String?) async throws -> [ChipSignedDigest] {
        calls.append(Call(digests: digests, expectedKey: expectedKey, pin: pin))
        if let error { throw error }
        return digests.map { _ in .secp256k1(signature: Data(repeating: 0x11, count: 64)) }
    }

    func sign(digests: [Data], acceptedKeys: [ChipPublicKey], pin: String?) async throws -> CardSignatures {
        guard let key = acceptedKeys.first else { throw ChipError.malformedResponse("no accepted card") }
        let signatures = try await sign(digests: digests, expectedKey: key, pin: pin)
        return CardSignatures(card: ChipKeyInfo(kind: .infineon2Go, publicKey: key, pinActive: pin != nil), signatures: signatures)
    }

    func readOrSign(digests: [Data], acceptedKeys: [ChipPublicKey]) async throws -> ReadOrSign {
        .signed(try await sign(digests: digests, acceptedKeys: acceptedKeys, pin: nil))
    }

    func setPINAndSign(digests: [Data], expectedKey: ChipPublicKey, newPIN: String) async throws -> PINSetupSignatures {
        newPINs.append(newPIN)
        if let setPINError { throw setPINError }
        return PINSetupSignatures(puk: puk, signatures: try await sign(digests: digests, expectedKey: expectedKey, pin: newPIN))
    }

    /// PIN vérifiés (reconnexion) ; même erreur que `sign` si elle est donnée.
    private(set) var verifiedPINs: [String] = []

    func verifyPIN(expectedKey: ChipPublicKey, pin: String) async throws {
        verifiedPINs.append(pin)
        if let error { throw error }
    }
}

extension AccountSetupModel {
    /// Saisie d'un nouveau PIN puis de sa confirmation.
    func pinEnter(_ first: String, _ confirm: String) async {
        pinCompleted(first)
        pinCompleted(confirm)
    }
}
