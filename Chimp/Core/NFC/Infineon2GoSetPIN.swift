import Foundation

/// SET PIN de l'Infineon 2Go : portage de `setPin()` de `reference/nfc-bridge/server/chips/infineon2go.js`.
/// `00 40 00 00 <Lc> <PIN en UTF-8> 08` → la carte renvoie le **PUK (8 octets), une seule fois**.
/// Utilisé seulement par l'onboarding (décision du 2026-09-29 : PIN obligatoire, choisi par l'utilisateur).
/// Garde plus stricte que le bridge : jamais envoyé à une carte dont le SELECT dit « PIN déjà actif ».
extension Infineon2Go {
    /// Longueur du PUK demandée à la carte (dernier octet de l'APDU, `08` dans le bridge).
    static let pukLength: UInt8 = 8

    /// SET PIN : `00 40 00 00 <Lc> <PIN> 08` (même contrôle de longueur que VERIFY PIN : 4 à 62 octets).
    static func setPINAPDU(pin: String) throws(ChipError) -> Data {
        let pinBytes = Data(pin.utf8)
        guard (4...62).contains(pinBytes.count) else { throw .invalidPINLength }
        return Data([0x00, 0x40, 0x00, 0x00, UInt8(pinBytes.count)]) + pinBytes + [pukLength]
    }

    /// Réponse à SET PIN : les 8 premiers octets sont le PUK (`res.subarray(0, 8)`). Erreurs comme `pinError`.
    static func parseSetPIN(_ response: APDUResponse) throws(ChipError) -> Data {
        guard response.statusWord == 0x9000 else {
            if response.sw1 == 0x63 { throw .wrongPIN(retriesLeft: Int(response.sw2 & 0x0F)) }
            if response.statusWord == 0x6983 { throw .pinLocked }
            throw .status(command: "SET PIN", statusWord: response.statusWord)
        }
        guard response.data.count >= Int(pukLength) else {
            throw .malformedResponse("SET PIN returned \(response.data.count) bytes, expected a \(pukLength)-byte PUK")
        }
        return Data(response.data.prefix(Int(pukLength)))
    }

    /// SELECT puis SET PIN, comme `withApp` du bridge. Refuse (sans rien envoyer d'autre) si le PIN est déjà actif.
    static func setPIN(_ transport: some APDUTransport, pin: String) async throws -> Data {
        let apdu = try setPINAPDU(pin: pin)
        let pinActive = try parseSelect(try await transport.send(selectAPDU))
        guard !pinActive else { throw ChipError.pinAlreadySet }
        return try parseSetPIN(try await transport.send(apdu))
    }
}
