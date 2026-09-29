import Foundation

/// Faux lecteur de carte, pour le simulateur (pas de NFC) et les tests. Chaque scénario reproduit
/// un résultat possible de `NFCChipReader`, y compris les erreurs, avec un petit délai de « tap ».
struct MockChipReader: ChipReader {
    enum Scenario: String, CaseIterable, Identifiable {
        case infineon
        case infineonWithPIN
        case duox
        case noKey
        case unknownChip
        case cardRemoved
        case cancelled

        var id: Self { self }

        /// Nom technique affiché dans les écrans de développement.
        var label: String {
            switch self {
            case .infineon: "Infineon, no PIN"
            case .infineonWithPIN: "Infineon, PIN set"
            case .duox: "DUOX"
            case .noKey: "Card without a key"
            case .unknownChip: "Unknown chip"
            case .cardRemoved: "Card removed too early"
            case .cancelled: "Scan cancelled"
            }
        }
    }

    var scenario: Scenario = .infineon
    var delay: Duration = .milliseconds(700)

    func readKey() async throws -> ChipKeyInfo {
        try await Task.sleep(for: delay)
        switch scenario {
        case .infineon:
            return ChipKeyInfo(kind: .infineon2Go, publicKey: Self.secp256k1Key, pinActive: false)
        case .infineonWithPIN:
            return ChipKeyInfo(kind: .infineon2Go, publicKey: Self.secp256k1Key, pinActive: true)
        case .duox:
            return ChipKeyInfo(kind: .duox, publicKey: Self.p256Key, pinActive: false)
        case .noKey:
            throw ChipError.noKey(statusWord: 0x6A88)
        case .unknownChip:
            throw ChipError.unknownChip
        case .cardRemoved:
            throw ChipError.transport("Tag connection lost")
        case .cancelled:
            throw ChipError.cancelled
        }
    }

    /// Point générateur de secp256k1 : une clé publique valide, dont tout le monde connaît la clé privée (1).
    /// Visiblement factice, et jamais enregistrable.
    static let secp256k1Key = try! ChipPublicKey(Data(hex:
        "0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
        + "483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8")!)

    /// Point générateur de P-256, même principe.
    static let p256Key = try! ChipPublicKey(Data(hex:
        "046b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296"
        + "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5")!)
}
