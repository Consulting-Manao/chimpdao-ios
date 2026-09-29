import Foundation
import Testing
@testable import ChimpDAO

// Code du mode admin : ces tests tournent avec l'action Test du schéma (configuration Debug, drapeau `CHIMP_ADMIN`).

/// Génération de la clé n°1 d'une Infineon vierge (mode admin, exception à la règle 6 : slot 1 vide seulement).
/// Octets comparés à `reference/nfc-bridge/server/chips/infineon2go.js` (`generateKey`, `getPubkey`).
struct KeyGenerationTests {
    private let newKey = MockChipReader.secp256k1Key

    @Test("GENERATE KEY : 00 02 00 00 00 (generateKey du bridge)")
    func generateKeyAPDU() {
        #expect(Infineon2Go.generateKeyAPDU.hexString == "0002000000")
    }

    @Test("Réponse à GENERATE KEY : octet 0 = index de la clé ; statut refusé ou réponse vide = erreur")
    func parseGenerateKey() throws {
        #expect(try Infineon2Go.parseGenerateKey(APDUResponse(data: Data([0x01]), sw1: 0x90, sw2: 0x00)) == 1)
        #expect(throws: ChipError.status(command: "GENERATE KEY", statusWord: 0x6A84)) {
            try Infineon2Go.parseGenerateKey(APDUResponse(data: Data(), sw1: 0x6A, sw2: 0x84))
        }
        #expect(throws: ChipError.self) {
            try Infineon2Go.parseGenerateKey(APDUResponse(data: Data(), sw1: 0x90, sw2: 0x00))
        }
    }

    @Test("Slot 1 vide (6A88) : séquence exacte envoyée, clé relue sur l'index renvoyé")
    func generatesOnEmptySlot() async throws {
        let card = BlankInfineon(newKey: newKey)
        let info = try await ChipKeyGeneration.generateKey(card)
        #expect(info == ChipKeyInfo(kind: .infineon2Go, publicKey: newKey, pinActive: false))
        #expect(card.sent.map(\.hexString) == [
            "00a404000dd276000004150200010000000100", // SELECT : détection
            "00a404000dd276000004150200010000000100", // SELECT
            "0016010000",                             // GET KEY INFO clé 1 → 6A88 attendu
            "00a404000dd276000004150200010000000100", // SELECT (withApp du bridge)
            "0002000000",                             // GENERATE KEY
            "00a404000dd276000004150200010000000100", // SELECT
            "0016010000",                             // GET KEY INFO sur l'index renvoyé (1)
        ])
        #expect(card.generateCount == 1)
    }

    @Test("Carte qui a déjà une clé : refus, aucun GENERATE KEY envoyé")
    func refusesWhenKeyPresent() async {
        let card = BlankInfineon(newKey: newKey, existingKey: newKey)
        await #expect(throws: ChipError.keyAlreadyPresent) { try await ChipKeyGeneration.generateKey(card) }
        #expect(card.generateCount == 0)
    }

    @Test("Autres statuts « pas de clé » du bridge (6A82, 6985) : refus, aucun GENERATE KEY envoyé")
    func refusesOtherMissingKeyStatuses() async {
        for sw: UInt16 in [0x6A82, 0x6985] {
            let card = BlankInfineon(newKey: newKey, emptySlotStatus: sw)
            await #expect(throws: ChipError.status(command: "GET KEY INFO", statusWord: sw)) {
                try await ChipKeyGeneration.generateKey(card)
            }
            #expect(card.generateCount == 0)
        }
    }

    @Test("DUOX ou carte inconnue : refus, aucun GENERATE KEY envoyé")
    func refusesOtherChips() async {
        let duox = NotInfineon(isDuox: true)
        await #expect(throws: ChipError.keyGenerationUnsupported(ChipKind.duox.displayName)) {
            try await ChipKeyGeneration.generateKey(duox)
        }
        let unknown = NotInfineon(isDuox: false)
        await #expect(throws: ChipError.unknownChip) { try await ChipKeyGeneration.generateKey(unknown) }
        #expect(!(duox.sent + unknown.sent).contains(Infineon2Go.generateKeyAPDU))
    }

    @Test("La puce crée la clé à un autre index que 1 : erreur explicite, pas de relecture silencieuse")
    func unexpectedSlot() async {
        let card = BlankInfineon(newKey: newKey, generatedSlot: 2)
        await #expect(throws: ChipError.unexpectedKeySlot(2)) { try await ChipKeyGeneration.generateKey(card) }
        #expect(card.sent.last == Infineon2Go.generateKeyAPDU)
    }

    @Test("GENERATE KEY refusé par la puce : erreur avec le statut")
    func generationRefused() async {
        let card = BlankInfineon(newKey: newKey, generateStatus: 0x6A84)
        await #expect(throws: ChipError.status(command: "GENERATE KEY", statusWord: 0x6A84)) {
            try await ChipKeyGeneration.generateKey(card)
        }
    }

    @Test("Erreur radio pendant la génération : propagée (règle 7)")
    func transportError() async {
        let card = BlankInfineon(newKey: newKey, failOnGenerate: true)
        await #expect(throws: ChipError.transport("lost")) { try await ChipKeyGeneration.generateKey(card) }
    }

    // MARK: ViewModel

    @Test("La génération n'est proposée qu'après une lecture « slot 1 vide » (6A88)")
    func modelOffersGenerationOnlyForEmptySlot() async {
        let model = AdminCardReadModel(nfcAvailable: false, mockDelay: .zero)
        #expect(!model.canGenerateKey)
        await model.generateKey()
        #expect(model.state == .idle)

        model.readerChoice = .mock(.infineon)
        await model.read()
        #expect(!model.canGenerateKey)

        model.readerChoice = .mock(.noKey)
        await model.read()
        #expect(model.canGenerateKey)
        await model.generateKey()
        #expect(model.state == .generated(ChipKeyInfo(kind: .infineon2Go, publicKey: newKey, pinActive: false)))
        #expect(!model.canGenerateKey)
    }

    @Test("Carte changée entre la lecture et la génération : la garde de la session refuse")
    func modelCardSwapped() async {
        let model = AdminCardReadModel(nfcAvailable: false, mockDelay: .zero)
        model.readerChoice = .mock(.noKey)
        await model.read()
        model.readerChoice = .mock(.infineon)
        await model.generateKey()
        #expect(model.state == .failed(ChipError.keyAlreadyPresent.errorDescription!))
    }
}

// MARK: - Fausses cartes

private func status(_ sw: UInt16, _ data: Data = Data()) -> APDUResponse {
    APDUResponse(data: data, sw1: UInt8(sw >> 8), sw2: UInt8(sw & 0xFF))
}

/// Infineon 2Go simulée avec ses slots de clé : GET KEY INFO, GENERATE KEY.
private final class BlankInfineon: APDUTransport {
    private(set) var sent: [Data] = []
    private(set) var generateCount = 0
    private var keys: [UInt8: ChipPublicKey] = [:]
    private let newKey: ChipPublicKey
    private let emptySlotStatus: UInt16
    private let generatedSlot: UInt8
    private let generateStatus: UInt16
    private let failOnGenerate: Bool

    init(
        newKey: ChipPublicKey,
        existingKey: ChipPublicKey? = nil,
        emptySlotStatus: UInt16 = 0x6A88,
        generatedSlot: UInt8 = 1,
        generateStatus: UInt16 = 0x9000,
        failOnGenerate: Bool = false
    ) {
        self.newKey = newKey
        if let existingKey { keys[1] = existingKey }
        self.emptySlotStatus = emptySlotStatus
        self.generatedSlot = generatedSlot
        self.generateStatus = generateStatus
        self.failOnGenerate = failOnGenerate
    }

    func send(_ apdu: Data) async throws -> APDUResponse {
        sent.append(apdu)
        let bytes = [UInt8](apdu)
        if apdu == Infineon2Go.selectAPDU { return status(0x9000, Data([0x00, 0x01])) }
        if bytes.count == 5, bytes[0] == 0x00, bytes[1] == 0x16 {
            guard let key = keys[bytes[2]] else { return status(emptySlotStatus) }
            return status(0x9000, Data([0, 0, 0, 1, 0, 0, 0, 0]) + key.bytes)
        }
        if apdu == Infineon2Go.generateKeyAPDU {
            if failOnGenerate { throw ChipError.transport("lost") }
            guard generateStatus == 0x9000 else { return status(generateStatus) }
            generateCount += 1
            keys[generatedSlot] = newKey
            return status(0x9000, Data([generatedSlot]))
        }
        return status(0x6D00)
    }
}

/// Carte qui refuse l'AID Infineon : une DUOX (répond à GetVersion) ou une carte inconnue.
private final class NotInfineon: APDUTransport {
    private(set) var sent: [Data] = []
    let isDuox: Bool

    init(isDuox: Bool) { self.isDuox = isDuox }

    func send(_ apdu: Data) async throws -> APDUResponse {
        sent.append(apdu)
        if isDuox, apdu == Duox.getVersionAPDU {
            return status(0x9100, Data([0x04, 0x01, 0x01, 0xA0]) + Data(count: 24))
        }
        return status(0x6A82)
    }
}
