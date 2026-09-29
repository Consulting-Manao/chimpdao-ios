import Foundation
import Testing
@testable import ChimpDAO

/// Lecture des cartes (étape A) : octets des APDU et décodage des réponses, comparés à
/// `reference/nfc-bridge/server/chips/infineon2go.js` et `duox.js`.
/// Les cartes sont simulées par de faux transports : aucun NFC ici.
struct ChipReadingTests {

    // MARK: Infineon 2Go : APDU

    @Test("SELECT Infineon : 00 A4 04 00 0D <AID blocksec2go> 00 (selectApp du bridge)")
    func infineonSelectAPDU() {
        #expect(Infineon2Go.selectAPDU.hexString == "00a404000dd276000004150200010000000100")
    }

    @Test("GET KEY INFO clé n°1 : 00 16 01 00 00")
    func infineonGetKeyInfoAPDU() {
        #expect(Infineon2Go.getKeyInfoAPDU().hexString == "0016010000")
    }

    @Test("L'AID Infineon est celui de l'Info.plist (configuration NFC gelée)")
    func infineonAIDMatchesInfoPlist() throws {
        let aids = try #require(
            Bundle.main.object(forInfoDictionaryKey: "com.apple.developer.nfc.readersession.iso7816.select-identifiers") as? [String]
        )
        #expect(aids.contains(Infineon2Go.aid.hexString.uppercased()))
    }

    // MARK: Infineon 2Go : réponses

    @Test("SELECT : octet 0 = 01 → PIN actif, sinon non")
    func infineonSelectPin() throws {
        #expect(try Infineon2Go.parseSelect(APDUResponse(data: Data([0x01]), sw1: 0x90, sw2: 0x00)))
        #expect(try !Infineon2Go.parseSelect(APDUResponse(data: Data([0x00]), sw1: 0x90, sw2: 0x00)))
        #expect(try !Infineon2Go.parseSelect(APDUResponse(data: Data(), sw1: 0x90, sw2: 0x00)))
    }

    @Test("SELECT refusé : erreur avec le statut")
    func infineonSelectRefused() {
        #expect(throws: ChipError.status(command: "SELECT", statusWord: 0x6A82)) {
            try Infineon2Go.parseSelect(APDUResponse(data: Data(), sw1: 0x6A, sw2: 0x82))
        }
    }

    @Test("GET KEY INFO : la clé est data[8..<73]")
    func infineonKeyInfoOffsets() throws {
        let response = APDUResponse(data: FakeInfineon.keyInfoData(key: MockChipReader.secp256k1Key), sw1: 0x90, sw2: 0x00)
        #expect(try Infineon2Go.parseKeyInfo(response) == MockChipReader.secp256k1Key)
    }

    @Test("Carte sans clé : 6A88, 6A82 et 6985 donnent « pas de clé » (keyMissing du client du bridge)")
    func infineonNoKey() {
        for sw: UInt16 in [0x6A88, 0x6A82, 0x6985] {
            let response = APDUResponse(data: Data(), sw1: UInt8(sw >> 8), sw2: UInt8(sw & 0xFF))
            #expect(throws: ChipError.noKey(statusWord: sw)) { try Infineon2Go.parseKeyInfo(response) }
        }
    }

    @Test("GET KEY INFO : autre statut = erreur de statut, réponse trop courte = réponse illisible")
    func infineonKeyInfoErrors() {
        #expect(throws: ChipError.status(command: "GET KEY INFO", statusWord: 0x6F00)) {
            try Infineon2Go.parseKeyInfo(APDUResponse(data: Data(), sw1: 0x6F, sw2: 0x00))
        }
        #expect(throws: ChipError.self) {
            try Infineon2Go.parseKeyInfo(APDUResponse(data: Data(count: 72), sw1: 0x90, sw2: 0x00))
        }
    }

    @Test("Clé publique : 65 octets commençant par 04, sinon refusée")
    func publicKeyValidation() throws {
        #expect(throws: ChipError.invalidPublicKey(length: 64)) { try ChipPublicKey(Data(count: 64)) }
        var compressed = Data(count: 65)
        compressed[0] = 0x02
        #expect(throws: ChipError.invalidPublicKey(length: 65)) { try ChipPublicKey(compressed) }
        #expect(MockChipReader.secp256k1Key.hex.count == 130)
    }

    // MARK: DUOX : APDU

    @Test("Commandes natives DUOX (nativeApdu du bridge)")
    func duoxAPDUs() {
        #expect(Duox.getVersionAPDU.hexString == "9060000000")
        #expect(Duox.additionalFrameAPDU.hexString == "90af000000")
        #expect(Duox.selectPICCAPDU.hexString == "905a00000300000000")
        // Fichier 1, offset 0x010203, longueur 48 : offset et longueur sur 3 octets little-endian.
        #expect(Duox.readDataAPDU(file: 1, offset: 0x010203, length: 48).hexString == "90ad0000070103020130000000")
    }

    @Test("Empreinte DUOX : NXP (04), type DESFire (x1), version matérielle A0")
    func duoxVersion() throws {
        #expect(try Duox.parseVersion(FakeDuox.versionData).isDuox)
        var desfireEV3 = FakeDuox.versionData
        desfireEV3[3] = 0x33
        #expect(try !Duox.parseVersion(desfireEV3).isDuox)
        #expect(throws: ChipError.self) { try Duox.parseVersion(Data(count: 13)) }
    }

    @Test("Longueur d'un certificat DER d'après son en-tête (readPiccCert du bridge)")
    func derLength() throws {
        #expect(try Duox.derTotalLength(head: Data([0x30, 0x82, 0x01, 0x8F, 0, 0, 0, 0])) == 403)
        #expect(try Duox.derTotalLength(head: Data([0x30, 0x81, 0xC8, 0, 0, 0, 0, 0])) == 203)
        #expect(try Duox.derTotalLength(head: Data([0x30, 0x45, 0, 0, 0, 0, 0, 0])) == 71)
        #expect(throws: ChipError.self) { try Duox.derTotalLength(head: Data([0x31, 0x82, 0x01, 0x8F])) }
        #expect(throws: ChipError.self) { try Duox.derTotalLength(head: Data([0x30, 0x83, 0x01, 0x00, 0x00])) }
    }

    @Test("Clé P-256 extraite du certificat (clé attendue calculée par openssl)")
    func duoxCertificateKey() throws {
        let key = try Duox.publicKey(fromCertificate: FakeDuox.certificate)
        #expect(key.hex == FakeDuox.certificateKeyHex)
    }

    @Test("Certificat secp256k1 ou illisible : refusé (la DUOX est en P-256)")
    func duoxCertificateRejected() {
        #expect(throws: ChipError.self) { try Duox.publicKey(fromCertificate: FakeDuox.secp256k1Certificate) }
        #expect(throws: ChipError.self) { try Duox.publicKey(fromCertificate: Data([0x30, 0x03, 0x02, 0x01, 0x00])) }
    }

    // MARK: Lecture complète, cartes simulées

    @Test("Infineon : SELECT puis GET KEY INFO, clé et PIN lus")
    func readInfineon() async throws {
        let card = FakeInfineon(key: MockChipReader.secp256k1Key, pinActive: true)
        let info = try await ChipDetector.readKey(card)
        #expect(info == ChipKeyInfo(kind: .infineon2Go, publicKey: MockChipReader.secp256k1Key, pinActive: true))
        #expect(info.curve == .secp256k1)
        // Détection (SELECT), puis SELECT refait avant GET KEY INFO, comme le bridge.
        #expect(card.sent.map(\.hexString) == [
            Infineon2Go.selectAPDU.hexString, Infineon2Go.selectAPDU.hexString, "0016010000",
        ])
    }

    @Test("Infineon sans clé : erreur « pas de clé », aucune commande GENERATE KEY envoyée (règle 6)")
    func readInfineonWithoutKey() async {
        let card = FakeInfineon(key: nil, pinActive: false)
        await #expect(throws: ChipError.noKey(statusWord: 0x6A88)) { try await ChipDetector.readKey(card) }
        #expect(!card.sent.contains { $0.count > 1 && $0[1] == 0x02 })
    }

    @Test("DUOX : SELECT Infineon refusé, puis GetVersion (trames 91AF), Select PICC et certificat par morceaux de 48 octets")
    func readDuox() async throws {
        let card = FakeDuox()
        let info = try await ChipDetector.readKey(card)
        #expect(info.kind == .duox)
        #expect(info.curve == .p256)
        #expect(!info.pinActive)
        #expect(info.publicKey.hex == FakeDuox.certificateKeyHex)
        // Infineon essayée d'abord (ordre du bridge), jamais GetVersion avant.
        #expect(card.sent.first == Infineon2Go.selectAPDU)
        #expect(card.readLengths.allSatisfy { $0 <= Duox.readChunk })
        #expect(card.readLengths.reduce(0, +) == FakeDuox.certificate.count)
    }

    @Test("Ni Infineon ni DUOX : carte inconnue")
    func readUnknownChip() async {
        await #expect(throws: ChipError.unknownChip) { try await ChipDetector.readKey(FakeUnknownCard()) }
    }

    @Test("Erreur radio pendant la lecture : propagée, jamais convertie en « carte inconnue » (règle 7)")
    func transportErrorPropagates() async {
        let card = FakeInfineon(key: MockChipReader.secp256k1Key, pinActive: false, failAfter: 2)
        await #expect(throws: ChipError.transport("lost")) { try await ChipDetector.readKey(card) }
    }

    // MARK: Faux lecteur

    @Test("MockChipReader : chaque scénario donne le résultat attendu")
    func mockScenarios() async {
        for scenario in MockChipReader.Scenario.allCases {
            let reader = MockChipReader(scenario: scenario, delay: .zero)
            switch scenario {
            case .infineon, .infineonWithPIN:
                let info = try? await reader.readKey()
                #expect(info?.kind == .infineon2Go)
                #expect(info?.pinActive == (scenario == .infineonWithPIN))
            case .duox:
                #expect((try? await reader.readKey())?.kind == .duox)
            case .noKey:
                await #expect(throws: ChipError.noKey(statusWord: 0x6A88)) { try await reader.readKey() }
            case .unknownChip:
                await #expect(throws: ChipError.unknownChip) { try await reader.readKey() }
            case .cardRemoved:
                await #expect(throws: ChipError.self) { try await reader.readKey() }
            case .cancelled:
                await #expect(throws: ChipError.cancelled) { try await reader.readKey() }
            }
        }
    }

    @Test("Hexadécimal : aller-retour, et refus des chaînes invalides")
    func hex() {
        #expect(Data(hex: "00ff10Ab")?.hexString == "00ff10ab")
        #expect(Data(hex: "0") == nil)
        #expect(Data(hex: "zz") == nil)
        #expect(Data(hex: "+f") == nil)
    }
}

// MARK: - Fausses cartes

/// Enregistre les APDU envoyés.
private class RecordingCard {
    private(set) var sent: [Data] = []
    func record(_ apdu: Data) { sent.append(apdu) }
}


private func status(_ sw: UInt16, _ data: Data = Data()) -> APDUResponse {
    APDUResponse(data: data, sw1: UInt8(sw >> 8), sw2: UInt8(sw & 0xFF))
}

/// Infineon 2Go simulée : répond au SELECT et à GET KEY INFO comme la vraie puce.
private final class FakeInfineon: RecordingCard, APDUTransport {
    let key: ChipPublicKey?
    let pinActive: Bool
    /// Lève une erreur radio à partir de cette commande (0 = jamais).
    let failAfter: Int

    init(key: ChipPublicKey?, pinActive: Bool, failAfter: Int = 0) {
        self.key = key
        self.pinActive = pinActive
        self.failAfter = failAfter
    }

    static func keyInfoData(key: ChipPublicKey) -> Data {
        // 4 o compteur global, 4 o compteur de la clé, clé, puis 2 octets de plus pour vérifier qu'ils sont ignorés.
        Data([0, 0, 0, 7, 0, 0, 0, 3]) + key.bytes + [0xAA, 0xBB]
    }

    func send(_ apdu: Data) async throws -> APDUResponse {
        record(apdu)
        if failAfter > 0, sent.count >= failAfter { throw ChipError.transport("lost") }
        if apdu == Infineon2Go.selectAPDU { return status(0x9000, Data([pinActive ? 0x01 : 0x00, 0x01])) }
        if apdu.prefix(2) == Data([0x00, 0x16]) {
            guard let key else { return status(0x6A88) }
            return status(0x9000, Self.keyInfoData(key: key))
        }
        return status(0x6D00)
    }
}

/// DUOX simulée : refuse l'AID Infineon, répond à GetVersion en deux trames et sert son certificat par ReadData.
private final class FakeDuox: RecordingCard, APDUTransport {
    private(set) var readLengths: [Int] = []
    private var versionFramesSent = 0

    /// GetVersion : fabricant 04 (NXP), type 01 (DESFire), sous-type, version matérielle A0, puis le reste (28 octets).
    static let versionData = Data(hex: "0401" + "01" + "a0" + "00" + "1a05" + "0401010000001a05" + "04a1b2c3d4e5f6" + "00000000000000")!

    func send(_ apdu: Data) async throws -> APDUResponse {
        record(apdu)
        if apdu == Duox.getVersionAPDU {
            versionFramesSent = 1
            return status(0x91AF, Self.versionData.prefix(7))
        }
        if apdu == Duox.additionalFrameAPDU, versionFramesSent == 1 {
            versionFramesSent = 2
            return status(0x9100, Self.versionData.dropFirst(7))
        }
        if apdu == Duox.selectPICCAPDU { return status(0x9100) }
        if apdu.prefix(2) == Data([0x90, 0xAD]) {
            let bytes = [UInt8](apdu)
            let offset = Int(bytes[6]) | Int(bytes[7]) << 8 | Int(bytes[8]) << 16
            let length = Int(bytes[9]) | Int(bytes[10]) << 8 | Int(bytes[11]) << 16
            readLengths.append(length)
            let end = min(offset + length, Self.certificate.count)
            return status(0x9100, Self.certificate.subdata(in: offset..<end))
        }
        // Tout le reste, dont le SELECT de l'AID Infineon : fichier ou appli introuvable.
        return status(0x6A82)
    }

    /// Certificat P-256 auto-signé généré par openssl pour ce test (pas un vrai certificat DUOX) :
    /// `openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -outform DER`.
    static let certificate = Data(hex:
        "3082018f30820135a0030201020214195b6e2ce5015d76f8656ff788377fae308f2aa9300a06082a8648ce3d040302301d311b301906035504030c124368696d7044414f20746573742044554f58301e170d3236303932393036343530385a170d3336303932363036343530385a301d311b301906035504030c124368696d7044414f20746573742044554f583059301306072a8648ce3d020106082a8648ce3d03010703420004f0d5ec5dd1bbc4d694cea0de2ebdecf4be088cd7d498ac0694eb629a11668f5f02a6e2aa1a0d112e56272674bce89073657a6c0b42a63a90fa58c943acc77c20a3533051301d0603551d0e041604149115419e9fdd4fa451023f6326d66105540cda39301f0603551d230418301680149115419e9fdd4fa451023f6326d66105540cda39300f0603551d130101ff040530030101ff300a06082a8648ce3d0403020348003045022030dd73c57e18de779b3d810b9bbb7d5dc19f66b76a9c9dc8738be44d2e2f80a5022100ef54811a95617b67a35af5a873abd4f350240c5df9fd36a48bfb533fd29fd4a9"
    )!

    /// Clé publique de ce certificat, extraite par `openssl x509 -pubkey | openssl ec -pubin`.
    static let certificateKeyHex =
        "04f0d5ec5dd1bbc4d694cea0de2ebdecf4be088cd7d498ac0694eb629a11668f5f02a6e2aa1a0d112e56272674bce89073657a6c0b42a63a90fa58c943acc77c20"

    /// Même chose sur la courbe secp256k1 : doit être refusé.
    static let secp256k1Certificate = Data(hex:
        "308201883082012ea00302010202146e81c349afd49c1bd504e40732049d03a408438d300a06082a8648ce3d040302301b3119301706035504030c104368696d7044414f2074657374206b31301e170d3236303932393036343530385a170d3336303932363036343530385a301b3119301706035504030c104368696d7044414f2074657374206b313056301006072a8648ce3d020106052b8104000a03420004a9c15c7874d202a24857a739418911cca3d3a36213ecb62bbbcf199557b961875eacbfc68df8ad5b04c7ed5e2e7b956eebc2a6e79788b8df0600c88f96248088a3533051301d0603551d0e0416041456ceef1ffde9484fc5ac30b29c84008abd7e25c5301f0603551d2304183016801456ceef1ffde9484fc5ac30b29c84008abd7e25c5300f0603551d130101ff040530030101ff300a06082a8648ce3d0403020348003045022046abf885484da95e4e3fde25d207df445a0d68104f20714f8417e07a2943d143022100a050e9071f27c395eb658ff843d800d5fd543bee9e00cc693ee7e0e8e1843247"
    )!
}

/// Carte ISO 14443 qui n'est ni l'une ni l'autre : refuse tout.
private final class FakeUnknownCard: APDUTransport {
    func send(_ apdu: Data) async throws -> APDUResponse { status(0x6D00) }
}
