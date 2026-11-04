import Foundation
import Testing
@testable import ChimpDAO

/// Changer le PIN d'une Infineon. ⚠️ CHANGE PIN n'est pas dans `reference/` : APDU et statuts du manuel Infineon
/// « Blockchain Security 2Go Starter Kit », Edition 2019-03-10, §3.3 et §4.3.3.3 (journal du 2026-09-30).
struct ChangePINTests {
    private let key = MockChipReader.secp256k1Key
    private static let puk = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF])

    // MARK: APDU (manuel Infineon)

    @Test("CHANGE PIN 1234 → 5678 : 00 42 00 00 0A 04 31 32 33 34 04 35 36 37 38 08 (exemple du journal)")
    func apdu() throws {
        #expect(try Infineon2Go.changePINAPDU(current: "1234", new: "5678").hexString == "004200000a0431323334043536373808")
        #expect(throws: ChipError.invalidPINLength) { try Infineon2Go.changePINAPDU(current: "123", new: "5678") }
        #expect(throws: ChipError.invalidPINLength) { try Infineon2Go.changePINAPDU(current: "1234", new: String(repeating: "1", count: 63)) }
    }

    @Test("Réponse : 8 octets de PUK ; 63 Cx = PIN actuel faux, 69 83 = bloqué, 69 85 = pas de PIN, autre = erreur")
    func response() throws {
        #expect(try Infineon2Go.parseChangePIN(APDUResponse(data: Self.puk, sw1: 0x90, sw2: 0x00)) == Self.puk)
        #expect(throws: ChipError.wrongPIN(retriesLeft: 2)) { try Infineon2Go.parseChangePIN(APDUResponse(data: Data(), sw1: 0x63, sw2: 0xC2)) }
        #expect(throws: ChipError.pinLocked) { try Infineon2Go.parseChangePIN(APDUResponse(data: Data(), sw1: 0x69, sw2: 0x83)) }
        #expect(throws: ChipError.pinNotSet) { try Infineon2Go.parseChangePIN(APDUResponse(data: Data(), sw1: 0x69, sw2: 0x85)) }
        #expect(throws: ChipError.status(command: "CHANGE PIN", statusWord: 0x6A80)) {
            try Infineon2Go.parseChangePIN(APDUResponse(data: Data(), sw1: 0x6A, sw2: 0x80))
        }
        #expect(throws: ChipError.self) { try Infineon2Go.parseChangePIN(APDUResponse(data: Data([1, 2, 3]), sw1: 0x90, sw2: 0x00)) }
    }

    // MARK: Séquence sur la carte

    @Test("Séquence : détection (SELECT), SELECT, GET KEY INFO (bonne carte, PIN actif), SELECT, CHANGE PIN ; renvoie le nouveau PUK")
    func sequence() async throws {
        let card = ChangePINCard(key: key, pinActive: true, pin: "1234")
        let puk = try await ChipSigning.changePIN(card, expectedKey: key, currentPIN: "1234", newPIN: "5678")
        #expect(puk == Self.puk)
        #expect(card.sent.map { $0.prefix(2).hexString } == ["00a4", "00a4", "0016", "00a4", "0042"])
        #expect(card.sent.last?.hexString == "004200000a0431323334043536373808")
    }

    @Test("Autre carte ou carte sans PIN : aucun PIN ne lui est envoyé")
    func refusedWithoutSendingPIN() async {
        let otherKey = try! ChipPublicKey(Data([0x04]) + Data(repeating: 7, count: 64))
        let other = ChangePINCard(key: otherKey, pinActive: true, pin: "1234")
        await #expect(throws: ChipError.wrongCard) {
            try await ChipSigning.changePIN(other, expectedKey: key, currentPIN: "1234", newPIN: "5678")
        }
        #expect(!other.sent.contains { $0.prefix(2) == Data([0x00, 0x42]) })

        let noPIN = ChangePINCard(key: key, pinActive: false, pin: nil)
        await #expect(throws: ChipError.pinNotSet) {
            try await ChipSigning.changePIN(noPIN, expectedKey: key, currentPIN: "1234", newPIN: "5678")
        }
        #expect(!noPIN.sent.contains { $0.prefix(2) == Data([0x00, 0x42]) })
    }

    @Test("PIN actuel faux : la carte répond 63 Cx, rien n'a changé")
    func wrongCurrentPIN() async {
        let card = ChangePINCard(key: key, pinActive: true, pin: "1234")
        await #expect(throws: ChipError.wrongPIN(retriesLeft: 2)) {
            try await ChipSigning.changePIN(card, expectedKey: key, currentPIN: "0000", newPIN: "5678")
        }
    }

    @Test("Carte retirée pendant CHANGE PIN : issue inconnue (jamais « rien n'a changé ») ; avant : erreur normale")
    func lostResponse() async {
        let during = ChangePINCard(key: key, pinActive: true, pin: "1234", dropOnChange: true)
        await #expect(throws: ChangePINOutcomeUnknown(underlying: .transport("Tag connection lost"))) {
            try await ChipSigning.changePIN(during, expectedKey: key, currentPIN: "1234", newPIN: "5678")
        }
        let before = ChangePINCard(key: key, pinActive: true, pin: "1234", dropOnKeyInfo: true)
        await #expect(throws: ChipError.transport("Tag connection lost")) {
            try await ChipSigning.changePIN(before, expectedKey: key, currentPIN: "1234", newPIN: "5678")
        }
    }

    // MARK: Parcours

    private var card: PINCard { PINCard(key: key, name: "Banana", color: .banana, number: "0007") }

    private func typed(_ model: ChangePINModel, current: String = "1234", new: String = "5678", confirm: String? = nil) {
        model.continueFromReview()
        model.pinCompleted(current)
        model.pinCompleted(new)
        model.pinCompleted(confirm ?? new)
    }

    @Test("Revue, PIN actuel, nouveau PIN deux fois, tap tout seul, nouveau code, fin ; les PIN vont à la carte, rien n'est gardé")
    func happyPath() async {
        let signer = PINSigner(result: .success(Self.puk))
        let model = ChangePINModel(card: card, signer: signer)
        #expect(model.screen == .review)
        #expect(!model.back(), "Retour depuis la revue : on quitte")
        typed(model)
        #expect(model.isShowingTapSheet, "Nouveau PIN confirmé : la feuille du tap s'ouvre, sans écran de plus")
        for _ in 0..<200 where model.screen != .unlockCode {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(signer.changes.count == 1, "Le scan a démarré tout seul, une seule fois")
        #expect(signer.changes.first?.current == "1234")
        #expect(signer.changes.first?.new == "5678")
        #expect(model.screen == .unlockCode)
        #expect(model.unlockCode == Self.puk)
        #expect(!model.isShowingTapSheet)
        model.acknowledgeUnlockCode()
        #expect(model.unlockCode == nil)
        #expect(model.screen == .done(codeLost: false))
    }

    @Test("Les deux saisies du nouveau PIN diffèrent : on recommence le nouveau PIN")
    func mismatch() {
        let model = ChangePINModel(card: card, signer: PINSigner(result: .success(Self.puk)))
        typed(model, confirm: "9999")
        #expect(model.screen == .new)
        #expect(model.pinState == .mismatch)
    }

    @Test("PIN actuel faux : retour au PIN actuel avec les essais restants ; bloqué : cadenas")
    func wrongAndLocked() async {
        let wrong = ChangePINModel(card: card, signer: PINSigner(result: .failure(ChipError.wrongPIN(retriesLeft: 2))))
        typed(wrong)
        await wrong.scan()
        #expect(wrong.screen == .current)
        #expect(wrong.pinState == .wrong(triesLeft: 2))

        let locked = ChangePINModel(card: card, signer: PINSigner(result: .failure(ChipError.pinLocked)))
        typed(locked)
        await locked.scan()
        #expect(locked.pinState == .blocked)
    }

    @Test("Autre carte tapée : message dans la feuille, qui reste ouverte, sans nouveau scan tout seul")
    func otherCard() async {
        let signer = PINSigner(result: .failure(ChipError.wrongCard))
        let model = ChangePINModel(card: card, signer: signer)
        typed(model)
        await model.scan()
        #expect(model.problem?.kind == .otherCard)
        #expect(model.screen == .confirmNew)
        #expect(model.isShowingTapSheet)
        try? await Task.sleep(for: .milliseconds(500))
        #expect(signer.changes.count == 1, "« Scan my card » a été tapé avant la pause : pas de second scan")
    }

    @Test("Réponse perdue : « Did it work? » ; le nouveau PIN marche → fait, code perdu ; il ne marche pas → l'ancien est le bon")
    func unknownOutcome() async {
        let newWorks = PINSigner(result: .failure(ChangePINOutcomeUnknown(underlying: .transport("lost"))), verify: nil)
        let model = ChangePINModel(card: card, signer: newWorks)
        typed(model)
        await model.scan()
        #expect(model.screen == .unknownOutcome)
        await model.checkNewPIN()
        #expect(newWorks.verified == ["5678"], "La vérification se fait avec le nouveau PIN")
        #expect(model.screen == .done(codeLost: true))

        let oldWorks = PINSigner(result: .failure(ChangePINOutcomeUnknown(underlying: .transport("lost"))), verify: .wrongPIN(retriesLeft: 2))
        let other = ChangePINModel(card: card, signer: oldWorks)
        typed(other)
        await other.scan()
        await other.checkNewPIN()
        #expect(other.screen == .current)
        #expect(other.recoveryResult == .oldPINStillActive(triesLeft: 2))
    }

    @Test("Réglages : « Change PIN » seulement pour les Infineon")
    @MainActor func settingsCards() {
        let session = AppSession(store: InMemoryLocalWalletStore(LocalWallet(
            account: SavedAccount(address: "CAAAA", cards: [
                SavedCard(publicKey: key.hex, chip: "infineon2Go", tokenID: 7, pocket: nil, name: "Banana", color: "banana"),
                SavedCard(publicKey: MockChipReader.p256Key.hex, chip: "duox", tokenID: 9, pocket: nil, name: "Leaf", color: "leaf"),
            ])
        )), config: .testnet)
        let model = SettingsModel(session: session, walletCards: [])
        #expect(model.pinCards.map(\.name) == ["Banana"])
    }
}

/// Infineon simulée pour CHANGE PIN : SELECT (octet « PIN actif »), GET KEY INFO, CHANGE PIN (63 C2 si le PIN actuel est
/// faux). Peut « perdre » la carte à GET KEY INFO ou pendant CHANGE PIN. Garde toutes les commandes reçues.
private final class ChangePINCard: APDUTransport, @unchecked Sendable {
    private(set) var sent: [Data] = []
    let key: ChipPublicKey
    let pinActive: Bool
    let pin: String?
    let dropOnChange: Bool
    let dropOnKeyInfo: Bool

    init(key: ChipPublicKey, pinActive: Bool, pin: String?, dropOnChange: Bool = false, dropOnKeyInfo: Bool = false) {
        self.key = key
        self.pinActive = pinActive
        self.pin = pin
        self.dropOnChange = dropOnChange
        self.dropOnKeyInfo = dropOnKeyInfo
    }

    func send(_ apdu: Data) async throws -> APDUResponse {
        sent.append(apdu)
        let ok = { (data: Data) in APDUResponse(data: data, sw1: 0x90, sw2: 0x00) }
        if apdu == Infineon2Go.selectAPDU { return ok(Data([pinActive ? 0x01 : 0x00])) }
        if apdu.prefix(2) == Data([0x00, 0x16]) {
            if dropOnKeyInfo { throw ChipError.transport("Tag connection lost") }
            return ok(Data(count: 8) + key.bytes)
        }
        if apdu.prefix(2) == Data([0x00, 0x42]) {
            if dropOnChange { throw ChipError.transport("Tag connection lost") }
            let length = Int(apdu[5])
            let current = String(decoding: apdu.subdata(in: 6..<(6 + length)), as: UTF8.self)
            guard current == pin else { return APDUResponse(data: Data(), sw1: 0x63, sw2: 0xC2) }
            return ok(Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]))
        }
        return APDUResponse(data: Data(), sw1: 0x6D, sw2: 0x00)
    }
}

/// Faux signataire pour le parcours : résultat de CHANGE PIN et de VERIFY PIN réglables ; garde les PIN reçus.
private final class PINSigner: ChipSigner, @unchecked Sendable {
    let result: Result<Data, Error>
    let verify: ChipError?
    private(set) var changes: [(current: String, new: String)] = []
    private(set) var verified: [String] = []

    init(result: Result<Data, Error>, verify: ChipError? = nil) {
        self.result = result
        self.verify = verify
    }

    func sign(digests: [Data], expectedKey: ChipPublicKey, pin: String?) async throws -> [ChipSignedDigest] { throw ChipError.pinUnsupported }
    func sign(digests: [Data], acceptedKeys: [ChipPublicKey], pin: String?) async throws -> CardSignatures { throw ChipError.pinUnsupported }
    func readOrSign(digests: [Data], acceptedKeys: [ChipPublicKey]) async throws -> ReadOrSign { throw ChipError.pinUnsupported }
    func setPINAndSign(digests: [Data], expectedKey: ChipPublicKey, newPIN: String) async throws -> PINSetupSignatures { throw ChipError.pinUnsupported }

    func verifyPIN(expectedKey: ChipPublicKey, pin: String) async throws {
        verified.append(pin)
        if let verify { throw verify }
    }

    func changePIN(expectedKey: ChipPublicKey, currentPIN: String, newPIN: String) async throws -> Data {
        changes.append((currentPIN, newPIN))
        return try result.get()
    }
}
