import Foundation

/// CHANGE PIN de l'Infineon 2Go. ⚠️ **Absent de `reference/`** : commande lue dans le manuel Infineon « Blockchain
/// Security 2Go Starter Kit », Edition 2019-03-10, §3.3 et §4.3.3.3 (journal du 2026-09-30). À faire valider par Pamphile.
///
/// `00 42 00 00 <Lc> <Lcur> <PIN actuel> <Lnew> <nouveau PIN> 08`, Lc = Lcur + Lnew + 2. La carte vérifie le PIN actuel,
/// enregistre le nouveau et renvoie un **nouveau PUK de 8 octets**, une seule fois (l'ancien ne sert plus).
/// Erreurs : `63 Cx` PIN actuel faux (x essais restants), `69 83` PIN bloqué, `69 85` pas de PIN défini, `6A 80` format.
extension Infineon2Go {
    /// CHANGE PIN : chaque PIN fait 4 à 62 octets (même contrôle que VERIFY PIN et SET PIN).
    static func changePINAPDU(current: String, new: String) throws(ChipError) -> Data {
        let currentBytes = Data(current.utf8)
        let newBytes = Data(new.utf8)
        guard (4...62).contains(currentBytes.count), (4...62).contains(newBytes.count) else { throw .invalidPINLength }
        let body = Data([UInt8(currentBytes.count)]) + currentBytes + Data([UInt8(newBytes.count)]) + newBytes
        return Data([0x00, 0x42, 0x00, 0x00, UInt8(body.count)]) + body + [pukLength]
    }

    /// Réponse à CHANGE PIN : les 8 premiers octets sont le nouveau PUK.
    static func parseChangePIN(_ response: APDUResponse) throws(ChipError) -> Data {
        guard response.statusWord == 0x9000 else {
            if response.sw1 == 0x63 { throw .wrongPIN(retriesLeft: Int(response.sw2 & 0x0F)) }
            if response.statusWord == 0x6983 { throw .pinLocked }
            if response.statusWord == 0x6985 { throw .pinNotSet }
            throw .status(command: "CHANGE PIN", statusWord: response.statusWord)
        }
        guard response.data.count >= Int(pukLength) else {
            throw .malformedResponse("CHANGE PIN returned \(response.data.count) bytes, expected a \(pukLength)-byte PUK")
        }
        return Data(response.data.prefix(Int(pukLength)))
    }
}

/// CHANGE PIN envoyé, mais la réponse n'est jamais arrivée (carte retirée, feuille NFC coupée) : on ne sait pas si le
/// nouveau PIN est actif, et si oui, son nouveau code de déblocage est perdu. Ne jamais conclure « rien n'a changé ».
struct ChangePINOutcomeUnknown: Error, Equatable {
    let underlying: ChipError
}

extension ChipSigning {
    /// Changer le PIN, dans une seule session NFC : lecture de la clé (SELECT → GET KEY INFO : bonne carte ? PIN actif ?)
    /// → SELECT → CHANGE PIN. Une autre carte, une DUOX ou une carte sans PIN ne reçoivent **aucun** PIN.
    /// Renvoie le nouveau PUK. Si la réponse à CHANGE PIN se perd : `ChangePINOutcomeUnknown`.
    static func changePIN(_ transport: some APDUTransport, expectedKey: ChipPublicKey, currentPIN: String, newPIN: String) async throws -> Data {
        let apdu = try Infineon2Go.changePINAPDU(current: currentPIN, new: newPIN)
        let card = try await ChipDetector.readKey(transport)
        guard card.publicKey == expectedKey else { throw ChipError.wrongCard }
        guard card.kind == .infineon2Go else { throw ChipError.pinUnsupported }
        guard card.pinActive else { throw ChipError.pinNotSet }
        _ = try Infineon2Go.parseSelect(try await transport.send(Infineon2Go.selectAPDU))
        let response: APDUResponse
        do {
            response = try await transport.send(apdu)
        } catch let error as ChipError {
            throw ChangePINOutcomeUnknown(underlying: error)
        } catch {
            throw ChangePINOutcomeUnknown(underlying: .transport(error.localizedDescription))
        }
        return try Infineon2Go.parseChangePIN(response)
    }
}
