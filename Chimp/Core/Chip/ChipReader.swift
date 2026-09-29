import Foundation

/// Lecture d'une carte : type de puce, courbe et clé publique. Rien n'est signé.
/// Implémenté par `NFCChipReader` (Core NFC) et `MockChipReader` (tests, simulateur).
protocol ChipReader {
    func readKey() async throws -> ChipKeyInfo
}

/// Détection du type de puce puis lecture de la clé, sur une carte déjà connectée.
/// Même ordre que nfc-bridge (`server/chips/index.js`) : **Infineon d'abord, puis DUOX**, parce que
/// le GetVersion de la DUOX peut « empoisonner » une Infineon (`6E00`) jusqu'à ce qu'on la retire du champ.
enum ChipDetector {
    static func readKey(_ transport: some APDUTransport) async throws -> ChipKeyInfo {
        if try await Infineon2Go.detect(transport) != nil {
            return try await Infineon2Go.readKey(transport)
        }
        if try await Duox.detect(transport) {
            return try await Duox.readKey(transport)
        }
        throw ChipError.unknownChip
    }
}
