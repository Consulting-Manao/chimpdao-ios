import Foundation

/// Commandes de l'Infineon Blockchain Security 2Go (secp256k1).
/// Portage de `reference/nfc-bridge/server/chips/infineon2go.js` : mêmes APDU, mêmes décalages.
/// Volontairement absent : GENERATE KEY (`00 02`). Une carte sans clé est refusée (règle 6).
enum Infineon2Go {
    /// AID de l'appli « blocksec2go » (`BLOCKCHAIN_AID` dans `server/constants.js`).
    /// Il figure dans la liste `select-identifiers` de l'Info.plist (configuration NFC gelée).
    static let aid = Data([0xD2, 0x76, 0x00, 0x00, 0x04, 0x15, 0x02, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01])

    /// Seule clé utilisée par ChimpDAO (le bridge et le terminal lisent toujours la clé n°1).
    static let defaultKeyID: UInt8 = 1

    /// Statuts qui veulent dire « pas de clé à cet index ». Même liste que `keyMissing` du client
    /// du bridge (`packages/client/src/client.ts`) : `6A88` (clé absente), `6A82`, `6985`.
    static let keyMissingStatusWords: Set<UInt16> = [0x6A88, 0x6A82, 0x6985]

    // MARK: APDU

    /// SELECT APP : `00 A4 04 00 0D <AID> 00`.
    static var selectAPDU: Data {
        Data([0x00, 0xA4, 0x04, 0x00, UInt8(aid.count)]) + aid + [0x00]
    }

    /// GET KEY INFO : `00 16 <keyId> 00 00`.
    static func getKeyInfoAPDU(keyID: UInt8 = defaultKeyID) -> Data {
        Data([0x00, 0x16, keyID, 0x00, 0x00])
    }

    // MARK: Réponses

    /// Réponse au SELECT → PIN actif ? (octet 0 = `01`, manuel §4.3.1, `selectApp` du bridge).
    static func parseSelect(_ response: APDUResponse) throws(ChipError) -> Bool {
        guard response.statusWord == 0x9000 else {
            throw .status(command: "SELECT", statusWord: response.statusWord)
        }
        return response.data.first == 0x01
    }

    /// Réponse à GET KEY INFO : 4 o compteur global · 4 o compteur de la clé · 65 o clé publique.
    /// La clé est `data[8..<73]` (`getPubkey` du bridge).
    static func parseKeyInfo(_ response: APDUResponse) throws(ChipError) -> ChipPublicKey {
        if keyMissingStatusWords.contains(response.statusWord) {
            throw .noKey(statusWord: response.statusWord)
        }
        guard response.statusWord == 0x9000 else {
            throw .status(command: "GET KEY INFO", statusWord: response.statusWord)
        }
        guard response.data.count >= 73 else {
            throw .malformedResponse("GET KEY INFO returned \(response.data.count) bytes, expected at least 73")
        }
        let start = response.data.startIndex
        return try ChipPublicKey(response.data.subdata(in: (start + 8)..<(start + 73)))
    }

    // MARK: Opérations

    /// Détection (`detect` du bridge) : la carte répond-elle `90 00` au SELECT de l'appli ?
    /// Renvoie l'état du PIN si oui, `nil` sinon. Une erreur radio est levée, pas convertie en « non ».
    static func detect(_ transport: some APDUTransport) async throws -> Bool? {
        let response = try await transport.send(selectAPDU)
        guard response.statusWord == 0x9000 else { return nil }
        return response.data.first == 0x01
    }

    /// Lit la clé n°1. Comme le bridge, refait le SELECT juste avant (`withApp`).
    static func readKey(_ transport: some APDUTransport) async throws -> ChipKeyInfo {
        let pinActive = try parseSelect(try await transport.send(selectAPDU))
        let key = try parseKeyInfo(try await transport.send(getKeyInfoAPDU()))
        return ChipKeyInfo(kind: .infineon2Go, publicKey: key, pinActive: pinActive)
    }
}
