import Foundation
import Security

/// Commandes de la NXP MIFARE DUOX (P-256), lecture seule de la clé.
/// Portage de `reference/nfc-bridge/server/chips/duox.js` : commandes natives DESFire enveloppées
/// en ISO 7816 (CLA `90`), certificat X.509 d'origine dans le fichier 1 du PICC, clé publique dans son SPKI.
/// Clé préchargée en usine : pas de PIN et pas de génération de clé sur cette puce.
enum Duox {
    /// Fichier du certificat d'origine (`PICC_CERT_FILE`).
    static let certificateFile: UInt8 = 1
    /// Taille maximale d'un morceau lu (`READ_CHUNK`).
    static let readChunk = 48

    /// Statut « OK » des commandes natives DESFire.
    static let nativeOK: UInt16 = 0x9100
    /// Statut « trame suivante » des commandes natives DESFire.
    static let additionalFrame: UInt16 = 0x91AF

    // MARK: APDU

    /// Commande native enveloppée : `90 <cmd> 00 00 00` sans données, `90 <cmd> 00 00 <Lc> <données> 00` sinon (`nativeApdu`).
    static func nativeAPDU(_ command: UInt8, payload: Data = Data()) -> Data {
        guard !payload.isEmpty else { return Data([0x90, command, 0x00, 0x00, 0x00]) }
        return Data([0x90, command, 0x00, 0x00, UInt8(payload.count)]) + payload + [0x00]
    }

    /// Demande de la trame suivante : `90 AF 00 00 00`.
    static let additionalFrameAPDU = Data([0x90, 0xAF, 0x00, 0x00, 0x00])

    /// GetVersion : `90 60 00 00 00`.
    static var getVersionAPDU: Data { nativeAPDU(0x60) }

    /// Select Application niveau carte (PICC, AID `00 00 00`) : `90 5A 00 00 03 00 00 00 00`.
    static var selectPICCAPDU: Data { nativeAPDU(0x5A, payload: Data([0x00, 0x00, 0x00])) }

    /// ReadData : `90 AD 00 00 07 <fichier> <offset 3 o LE> <longueur 3 o LE> 00`.
    static func readDataAPDU(file: UInt8, offset: Int, length: Int) -> Data {
        nativeAPDU(0xAD, payload: Data([file]) + littleEndian3(offset) + littleEndian3(length))
    }

    static func littleEndian3(_ value: Int) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF)])
    }

    // MARK: GetVersion

    struct Version: Equatable {
        let hardwareVendor: UInt8
        let hardwareType: UInt8
        let hardwareMajor: UInt8

        /// Empreinte DUOX (`isDuoxVersion`) : fabricant NXP, type DESFire, version matérielle `A0`.
        var isDuox: Bool {
            hardwareVendor == 0x04 && (hardwareType & 0x0F) == 0x01 && hardwareMajor == 0xA0
        }
    }

    /// Lit le résultat de GetVersion (AN10833, `parseVersion`).
    static func parseVersion(_ data: Data) throws(ChipError) -> Version {
        guard data.count >= 14 else {
            throw .malformedResponse("GetVersion returned \(data.count) bytes, expected at least 14")
        }
        let bytes = [UInt8](data)
        return Version(hardwareVendor: bytes[0], hardwareType: bytes[1], hardwareMajor: bytes[3])
    }

    // MARK: Certificat

    /// Longueur totale d'un certificat DER d'après ses premiers octets (en-tête `30 82 hh ll`, `30 81 ll` ou `30 ll`).
    static func derTotalLength(head: Data) throws(ChipError) -> Int {
        let bytes = [UInt8](head)
        guard bytes.count >= 2, bytes[0] == 0x30 else {
            throw .malformedResponse("PICC certificate is not a DER SEQUENCE (\(head.hexString))")
        }
        switch bytes[1] {
        case 0x82:
            guard bytes.count >= 4 else { throw .malformedResponse("PICC certificate header too short") }
            return 4 + (Int(bytes[2]) << 8 | Int(bytes[3]))
        case 0x81:
            guard bytes.count >= 3 else { throw .malformedResponse("PICC certificate header too short") }
            return 3 + Int(bytes[2])
        case let short where short < 0x80:
            return 2 + Int(short)
        default:
            throw .malformedResponse("PICC certificate: unsupported DER length \(String(format: "%02x", bytes[1]))")
        }
    }

    /// Clé publique P-256 du certificat (`pubFromCert`). Le bridge compare l'en-tête SPKI à celui de P-256 ;
    /// ici, le framework Security d'Apple lit le certificat et on exige une clé EC de 256 bits,
    /// renvoyée au format SEC1 non compressé (`04 ‖ X ‖ Y`, 65 octets).
    static func publicKey(fromCertificate der: Data) throws(ChipError) -> ChipPublicKey {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw .malformedResponse("PICC certificate is not a valid X.509 certificate")
        }
        guard let key = SecCertificateCopyKey(certificate),
              let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
              attributes[kSecAttrKeyType] as? String == kSecAttrKeyTypeECSECPrimeRandom as String,
              (attributes[kSecAttrKeySizeInBits] as? Int) == 256,
              let external = SecKeyCopyExternalRepresentation(key, nil) as Data?
        else {
            throw .malformedResponse("PICC certificate: expected a P-256 public key")
        }
        return try ChipPublicKey(external)
    }

    // MARK: Opérations

    /// Commande native avec suivi des trames `91 AF` (`native`). Renvoie toutes les données et le dernier statut.
    static func native(_ transport: some APDUTransport, _ apdu: Data) async throws -> (data: Data, statusWord: UInt16) {
        var response = try await transport.send(apdu)
        var data = response.data
        while response.statusWord == additionalFrame {
            response = try await transport.send(additionalFrameAPDU)
            data.append(response.data)
        }
        return (data, response.statusWord)
    }

    /// Détection (`detect`) : GetVersion puis empreinte DUOX.
    /// Un statut refusé ou une réponse illisible veut dire « pas une DUOX » ; une erreur radio est levée.
    static func detect(_ transport: some APDUTransport) async throws -> Bool {
        let (data, statusWord) = try await native(transport, getVersionAPDU)
        guard statusWord == nativeOK, let version = try? parseVersion(data) else { return false }
        return version.isDuox
    }

    /// Lit le certificat d'origine (`readPiccCert`) : Select PICC, en-tête de 8 octets, puis morceaux de 48 octets.
    static func readCertificate(_ transport: some APDUTransport) async throws -> Data {
        try await expectOK(native(transport, selectPICCAPDU), command: "SelectApplication")
        let head = try await readData(transport, offset: 0, length: min(readChunk, 8))
        let total = try derTotalLength(head: head)

        var certificate = head
        while certificate.count < total {
            let length = min(readChunk, total - certificate.count)
            let chunk = try await readData(transport, offset: certificate.count, length: length)
            certificate.append(chunk)
            if chunk.count < length { break }
        }
        guard certificate.count >= total else {
            throw ChipError.malformedResponse("PICC certificate: short read \(certificate.count)/\(total)")
        }
        return certificate.prefix(total)
    }

    /// Lit la clé publique (`getPubkey`, clé n°1 = slot PICC 1, la seule prise en charge).
    static func readKey(_ transport: some APDUTransport) async throws -> ChipKeyInfo {
        let certificate = try await readCertificate(transport)
        return ChipKeyInfo(kind: .duox, publicKey: try publicKey(fromCertificate: certificate), pinActive: false)
    }

    private static func readData(_ transport: some APDUTransport, offset: Int, length: Int) async throws -> Data {
        let apdu = readDataAPDU(file: certificateFile, offset: offset, length: length)
        return try await expectOK(native(transport, apdu), command: "ReadData")
    }

    @discardableResult
    private static func expectOK(_ result: (data: Data, statusWord: UInt16), command: String) throws(ChipError) -> Data {
        guard result.statusWord == nativeOK else {
            throw .status(command: command, statusWord: result.statusWord)
        }
        return result.data
    }
}
