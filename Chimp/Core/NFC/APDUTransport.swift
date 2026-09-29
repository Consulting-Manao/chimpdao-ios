import Foundation

/// Réponse d'une puce à une commande APDU : les données, puis les 2 octets de statut (SW1 SW2).
struct APDUResponse: Equatable, Sendable {
    let data: Data
    let sw1: UInt8
    let sw2: UInt8

    /// Statut sur 16 bits (`0x9000` = OK en ISO 7816, `0x9100` = OK en commande native DESFire).
    var statusWord: UInt16 { UInt16(sw1) << 8 | UInt16(sw2) }
}

/// Envoie des APDU à la carte présente. Implémenté par la session Core NFC (`NFCChipReader`)
/// et par de faux transports dans les tests. Toute erreur radio est levée, jamais transformée en statut.
protocol APDUTransport: Sendable {
    func send(_ apdu: Data) async throws -> APDUResponse
}
