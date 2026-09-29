import Foundation
import stellarsdk

/// Encodage ScVal des types partagés des contrats (ARCHITECTURE §2.2).
/// Portage de `reference/terminal/src/chain/chip-auth.ts` : `scCurve`, `scUpgradePolicy`, `scMap`,
/// `scChipAuthK1`, `scChipAuthR1`, `scCardSigner`. Octets comparés au terminal dans les tests.
enum ChipAuthEncoding {
    /// `Curve` : `Vec[Symbol("Secp256k1")]` ou `Vec[Symbol("Secp256r1")]`.
    static func curve(_ curve: ChipCurve) -> SCValXDR {
        .vec([.symbol(curve == .p256 ? "Secp256r1" : "Secp256k1")])
    }

    /// `UpgradePolicy` : `Vec[Symbol("Managed")]` ou `Vec[Symbol("Manual")]`.
    static func upgradePolicy(managed: Bool) -> SCValXDR {
        .vec([.symbol(managed ? "Managed" : "Manual")])
    }

    /// Map Soroban : les clés doivent être triées (ordre des chaînes, comme `scMap` du terminal).
    static func map(_ entries: [(key: String, value: SCValXDR)]) -> SCValXDR {
        let sorted = entries.sorted { $0.key < $1.key }
        return .map(sorted.map { SCMapEntryXDR(key: .symbol($0.key), val: $0.value) })
    }

    /// `ChipAuth::Secp256k1(Secp256k1Auth { signature, recovery_id })`.
    static func chipAuthSecp256k1(signature: Data, recoveryID: UInt32) throws(ChipError) -> SCValXDR {
        guard signature.count == 64 else { throw .malformedResponse("signature must be 64 bytes, got \(signature.count)") }
        return .vec([
            .symbol("Secp256k1"),
            map([("recovery_id", .u32(recoveryID)), ("signature", .bytes(signature))]),
        ])
    }

    /// `ChipAuth::Secp256r1(Secp256r1Auth { signature, rnd_b })`.
    static func chipAuthSecp256r1(signature: Data, rndB: Data) throws(ChipError) -> SCValXDR {
        guard rndB.count == 16 else { throw .malformedResponse("rnd_b must be 16 bytes, got \(rndB.count)") }
        guard signature.count == 64 else { throw .malformedResponse("signature must be 64 bytes, got \(signature.count)") }
        return .vec([
            .symbol("Secp256r1"),
            map([("rnd_b", .bytes(rndB)), ("signature", .bytes(signature))]),
        ])
    }

    /// `CardSigner { curve, key }` : une carte dans un Chimp account.
    static func cardSigner(publicKey: ChipPublicKey, curve: ChipCurve) -> SCValXDR {
        map([("curve", self.curve(curve)), ("key", .bytes(publicKey.bytes))])
    }
}
