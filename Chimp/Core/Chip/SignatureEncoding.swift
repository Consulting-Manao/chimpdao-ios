import Foundation

/// Mise en forme des signatures renvoyées par les puces (règles 2, 5 et 11).
/// Portage de `reference/nfc-bridge/server/der.js` (`toRS`, `parseDer`) et de `normalizeSignature`
/// (`reference/terminal/src/chain/chip-auth.ts`) : même découpage DER, même règle low-S.
enum SignatureEncoding {
    /// Ordre `n` des deux courbes, grand-boutiste (`ORDERS` dans der.js).
    static func order(of curve: ChipCurve) -> [UInt8] {
        switch curve {
        case .secp256k1: secp256k1Order
        case .p256: p256Order
        }
    }

    static let secp256k1Order = [UInt8](Data(hex: "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141")!)
    static let p256Order = [UInt8](Data(hex: "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551")!)

    /// `n >> 1` pour chaque courbe (`half = order >> 1n`).
    static func halfOrder(of curve: ChipCurve) -> [UInt8] {
        switch curve {
        case .secp256k1: [UInt8](Data(hex: "7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0")!)
        case .p256: [UInt8](Data(hex: "7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a8")!)
        }
    }

    /// Signature DER → `r ‖ s` (64 octets), sans normalisation (`parseDer` puis remplissage à 32 octets de `toRS`).
    /// Comme le bridge, retire un `00` de tête sur `r` et `s`. Refuse (au lieu de planter) une DER tronquée.
    static func rawSignature(fromDER der: Data) throws(ChipError) -> Data {
        let bytes = [UInt8](der)
        guard bytes.count >= 8, bytes[0] == 0x30, bytes[2] == 0x02 else {
            throw .malformedResponse("signature is not a DER SEQUENCE of two INTEGERs (\(der.hexString))")
        }
        var index = 3
        let rLength = Int(bytes[index]); index += 1
        guard index + rLength + 2 <= bytes.count else { throw .malformedResponse("DER signature truncated (r)") }
        var r = Array(bytes[index..<(index + rLength)]); index += rLength
        guard bytes[index] == 0x02 else { throw .malformedResponse("DER signature: s is not an INTEGER") }
        index += 1
        let sLength = Int(bytes[index]); index += 1
        guard index + sLength <= bytes.count else { throw .malformedResponse("DER signature truncated (s)") }
        var s = Array(bytes[index..<(index + sLength)])
        if r.first == 0x00 { r.removeFirst() }
        if s.first == 0x00 { s.removeFirst() }
        guard (1...32).contains(r.count), (1...32).contains(s.count) else {
            throw .malformedResponse("DER signature: r or s longer than 32 bytes")
        }
        return Data(repeating: 0, count: 32 - r.count) + r + Data(repeating: 0, count: 32 - s.count) + s
    }

    /// Normalisation « low-S » (règle 5) : si `s > n/2`, `s` devient `n − s`. `r` ne change pas.
    /// Obligatoire pour Soroban (`secp256k1_recover`) ; le bridge l'applique aussi à P-256.
    static func lowS(_ rs: Data, curve: ChipCurve) throws(ChipError) -> Data {
        guard rs.count == 64 else { throw .malformedResponse("signature must be 64 bytes, got \(rs.count)") }
        let r = rs.prefix(32)
        let s = [UInt8](rs.suffix(32))
        guard compare(s, halfOrder(of: curve)) > 0 else { return Data(rs) }
        return Data(r) + Data(subtract(order(of: curve), s))
    }

    /// Compare deux entiers de 32 octets grand-boutistes : −1, 0 ou 1.
    static func compare(_ a: [UInt8], _ b: [UInt8]) -> Int {
        for (x, y) in zip(a, b) where x != y { return x < y ? -1 : 1 }
        return 0
    }

    /// `a − b` sur 32 octets grand-boutistes (avec `a ≥ b`).
    static func subtract(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: 32)
        var borrow = 0
        for i in stride(from: 31, through: 0, by: -1) {
            var difference = Int(a[i]) - Int(b[i]) - borrow
            borrow = difference < 0 ? 1 : 0
            if difference < 0 { difference += 256 }
            result[i] = UInt8(difference)
        }
        return result
    }
}
