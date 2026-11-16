import Foundation
import Testing
@testable import ChimpDAO

/// Reconnexion d'une carte déjà liée à un compte (décisions de Barth du 2026-09-29) : PIN d'une Infineon vérifié par
/// la carte (VERIFY PIN, second tap), simple tap pour une DUOX, puis « Welcome back! » si des noms manquent.
struct ReconnectTests {
    private let key = MockChipReader.secp256k1Key

    // MARK: APDU (ChipSigning.verifyPIN)

    @Test("VERIFY PIN seul : lecture de la clé, puis SELECT → VERIFY PIN ; aucun SIGN")
    func verifyPINSequence() async throws {
        let card = PINInfineon(key: key, pinActive: true, pin: "1234")
        try await ChipSigning.verifyPIN(card, expectedKey: key, pin: "1234")
        #expect(card.sent.map(\.hexString) == [
            Infineon2Go.selectAPDU.hexString, Infineon2Go.selectAPDU.hexString, "0016010000",
            Infineon2Go.selectAPDU.hexString, "004400000431323334",
        ])
        #expect(!card.sent.contains { $0.count > 1 && $0[1] == 0x18 })
    }

    @Test("PIN faux (63 C2) ou bloqué (69 83) : l'erreur de la carte remonte")
    func verifyPINErrors() async {
        await #expect(throws: ChipError.wrongPIN(retriesLeft: 2)) {
            try await ChipSigning.verifyPIN(PINInfineon(key: self.key, pinActive: true, pin: "1234"), expectedKey: self.key, pin: "9999")
        }
        await #expect(throws: ChipError.pinLocked) {
            try await ChipSigning.verifyPIN(PINInfineon(key: self.key, pinActive: true, pin: "1234", locked: true), expectedKey: self.key, pin: "1234")
        }
    }

    @Test("Autre carte, carte sans PIN, PIN trop court : refus, et le PIN n'est jamais envoyé")
    func verifyPINRefusals() async {
        let other = PINInfineon(key: MockChipReader.p256Key, pinActive: true, pin: "1234")
        await #expect(throws: ChipError.wrongCard) { try await ChipSigning.verifyPIN(other, expectedKey: self.key, pin: "1234") }
        #expect(!other.sent.contains { $0.count > 1 && $0[1] == 0x44 })

        let noPIN = PINInfineon(key: key, pinActive: false, pin: nil)
        await #expect(throws: ChipError.pinUnsupported) { try await ChipSigning.verifyPIN(noPIN, expectedKey: self.key, pin: "1234") }
        #expect(!noPIN.sent.contains { $0.count > 1 && $0[1] == 0x44 })

        let short = PINInfineon(key: key, pinActive: true, pin: "1234")
        await #expect(throws: ChipError.invalidPINLength) { try await ChipSigning.verifyPIN(short, expectedKey: self.key, pin: "123") }
        #expect(short.sent.isEmpty)
    }

    // MARK: Parcours

    @Test("Infineon avec PIN : le 4ᵉ chiffre lance le tap tout seul (VERIFY PIN), sans « Scan my card »")
    func pinStartsTheTap() async throws {
        let session = AppSession(store: InMemoryLocalWalletStore(), config: .testnet)
        let signer = RecordingSigner()
        let model = await scannedMember(reader: .infineonWithPIN, session: session, signer: signer)
        let reconnect = try #require(model.reconnection)
        reconnect.pinCompleted("1234")
        for _ in 0..<200 where model.path.last != .welcomeBack {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(signer.verifiedPINs == ["1234"])
        #expect(model.path == [.reading, .welcomeBack])
    }

    @Test("Infineon avec PIN : PIN, second tap (VERIFY PIN), puis « Welcome back! » ; le compte n'est ouvert qu'à la fin")
    func infineonWithPIN() async throws {
        let store = InMemoryLocalWalletStore()
        let session = AppSession(store: store, config: .testnet)
        let signer = RecordingSigner()
        let model = await scannedMember(reader: .infineonWithPIN, session: session, signer: signer)
        #expect(model.path == [.reading, .reconnectPIN])
        #expect(!session.hasAccount)

        let reconnect = try #require(model.reconnection)
        #expect(reconnect.needsPIN)
        reconnect.pinCompleted("1234")
        #expect(reconnect.isShowingTapSheet)
        await model.scanForReconnection()
        #expect(signer.verifiedPINs == ["1234"])
        #expect(model.path == [.reading, .welcomeBack])
        #expect(!reconnect.isShowingTapSheet)
        #expect(!session.hasAccount)

        #expect(reconnect.asksFirstName && reconnect.asksCard)
        #expect(!reconnect.canSave)
        reconnect.firstName = " Barth "
        reconnect.cardName = "Jungle"
        reconnect.cardColor = .leaf
        reconnect.usesCardDesign = true
        model.finishWelcomeBack()
        #expect(session.showsOnboarding == false)
        #expect(store.wallet.firstName == "Barth")
        #expect(store.wallet.account?.address == MockOnboardingService.memberAccount)
        let saved = try #require(store.wallet.account?.cards.first)
        #expect(saved.name == "Jungle" && saved.color == "leaf" && saved.tokenID == 421 && saved.chip == "infineon2Go")
        #expect(saved.usesDesign == true, "Le dessin choisi à la reconnexion est gardé avec la couleur")
        #expect(store.wallet.hint(for: key) == MockOnboardingService.memberAccount)
    }

    @Test("PIN faux : essais restants affichés, feuille fermée, rien d'ouvert ; carte bloquée : cadenas")
    func wrongAndLockedPIN() async throws {
        for (error, state) in [(ChipError.wrongPIN(retriesLeft: 2), ChimpPinState.wrong(triesLeft: 2)), (.pinLocked, .blocked)] {
            let session = AppSession(store: InMemoryLocalWalletStore(), config: .testnet)
            let model = await scannedMember(reader: .infineonWithPIN, session: session, signer: RecordingSigner(error: error))
            let reconnect = try #require(model.reconnection)
            reconnect.pinCompleted("1234")
            await model.scanForReconnection()
            #expect(reconnect.pinState == state)
            #expect(!reconnect.isShowingTapSheet)
            #expect(reconnect.pinEntry.isEmpty)
            #expect(model.path == [.reading, .reconnectPIN])
            #expect(!session.hasAccount)
        }
    }

    @Test("Autre carte au second tap : message dans la feuille, le PIN reste en mémoire pour retaper")
    func otherCardAtSecondTap() async throws {
        let signer = RecordingSigner(error: .wrongCard)
        let model = await scannedMember(reader: .infineonWithPIN, signer: signer)
        let reconnect = try #require(model.reconnection)
        reconnect.pinCompleted("1234")
        await model.scanForReconnection()
        #expect(reconnect.tapProblem?.kind == .wrongCard)
        #expect(reconnect.isShowingTapSheet)
        await model.scanForReconnection()
        #expect(signer.verifiedPINs == ["1234", "1234"])
    }

    @Test("DUOX ou Infineon sans PIN : pas de PIN demandé, directement « Welcome back! »")
    func noPINCards() async throws {
        for reader in [MockChipReader.Scenario.duox, .infineon] {
            let signer = RecordingSigner()
            let model = await scannedMember(reader: reader, signer: signer)
            #expect(model.path == [.reading, .welcomeBack])
            #expect(signer.verifiedPINs.isEmpty)
            #expect(model.reconnection?.needsPIN == false)
        }
    }

    @Test("Prénom déjà connu du téléphone : « Welcome back! » ne demande que la carte")
    func asksOnlyWhatIsMissing() async throws {
        // Compte fermé dont le téléphone connaît le prénom, mais pas cette carte (ajoutée ailleurs).
        let closed = SavedAccount(address: MockOnboardingService.memberAccount, cards: [], firstName: "Léo")
        let store = InMemoryLocalWalletStore(LocalWallet(tourSeen: true, disconnectedAccounts: [closed]))
        let session = AppSession(store: store, config: .testnet)
        let model = await scannedMember(reader: .duox, session: session)
        let reconnect = try #require(model.reconnection)
        #expect(!reconnect.asksFirstName && reconnect.asksCard)
        reconnect.cardName = "Leaf"
        model.finishWelcomeBack()
        #expect(store.wallet.firstName == "Léo")
        #expect(store.wallet.account?.cards.first?.name == "Leaf")
    }

    @Test("Téléphone déconnecté de ce compte : ni « Welcome back! » ni noms redemandés, tout est repris")
    func reconnectAfterDisconnect() async throws {
        let named = SavedCard(publicKey: MockChipReader.p256Key.hex, chip: "duox", tokenID: 421, pocket: "CPOCKET", name: "Jungle", color: "leaf")
        let store = InMemoryLocalWalletStore(LocalWallet(
            firstName: "Barth", tourSeen: true,
            account: SavedAccount(address: MockOnboardingService.memberAccount, cards: [named])
        ))
        let session = AppSession(store: store, config: .testnet)
        try session.disconnect()
        let model = await scannedMember(reader: .duox, session: session)
        #expect(model.reconnection?.needsWelcomeBack == false)
        #expect(!session.showsOnboarding, "Le compte s'ouvre directement")
        let card = try #require(store.wallet.account?.cards.first)
        #expect(store.wallet.account?.cards.count == 1)
        #expect(card.name == "Jungle" && card.color == "leaf", "Nom et couleur repris ; puce, NFT et wallet relus sur la chaîne")
        #expect(store.wallet.firstName == "Barth")
    }

    @Test("Écriture impossible : l'erreur s'affiche, le compte n'est pas ouvert")
    func saveFailure() async throws {
        let session = AppSession(store: RefusingStore(), config: .testnet)
        let model = await scannedMember(reader: .duox, session: session)
        let reconnect = try #require(model.reconnection)
        reconnect.firstName = "Léo"
        reconnect.cardName = "Leaf"
        model.finishWelcomeBack()
        #expect(reconnect.saveError != nil)
        #expect(!session.hasAccount)
    }

    @Test("Retour depuis la reconnexion : A2, rien d'enregistré")
    func cancel() async {
        let session = AppSession(store: InMemoryLocalWalletStore(), config: .testnet)
        let model = await scannedMember(reader: .infineonWithPIN, session: session)
        model.cancelReconnection()
        #expect(model.path == [.reading])
        #expect(model.reconnection == nil)
        #expect(!session.hasAccount)
    }

    // MARK: Aides

    private func scannedMember(reader: MockChipReader.Scenario, session: AppSession? = nil,
                               signer: ChipSigner? = nil) async -> OnboardingModel {
        let model = OnboardingModel(
            session: session ?? AppSession(store: InMemoryLocalWalletStore(), config: .testnet),
            reader: MockChipReader(scenario: reader, delay: .zero),
            service: MockOnboardingService(scenario: .member, delay: .zero),
            signer: signer ?? MockChipSigner(delay: .zero),
            makeSetup: { _ in throw CancellationError() }
        )
        model.path = [.reading]
        await model.scan()
        return model
    }
}

/// Infineon simulée pour VERIFY PIN : SELECT (octet « PIN actif »), GET KEY INFO, VERIFY PIN (63 C2 si faux, 69 83 si
/// bloquée). Garde toutes les commandes reçues.
private final class PINInfineon: APDUTransport, @unchecked Sendable {
    private(set) var sent: [Data] = []
    let key: ChipPublicKey
    let pinActive: Bool
    let pin: String?
    let locked: Bool

    init(key: ChipPublicKey, pinActive: Bool, pin: String?, locked: Bool = false) {
        self.key = key
        self.pinActive = pinActive
        self.pin = pin
        self.locked = locked
    }

    func send(_ apdu: Data) async throws -> APDUResponse {
        sent.append(apdu)
        let ok = { (data: Data) in APDUResponse(data: data, sw1: 0x90, sw2: 0x00) }
        if apdu == Infineon2Go.selectAPDU { return ok(Data([pinActive ? 0x01 : 0x00])) }
        if apdu.prefix(2) == Data([0x00, 0x16]) { return ok(Data(count: 8) + key.bytes) }
        if apdu.prefix(2) == Data([0x00, 0x44]) {
            if locked { return APDUResponse(data: Data(), sw1: 0x69, sw2: 0x83) }
            let typed = String(decoding: apdu.dropFirst(5), as: UTF8.self)
            return typed == pin ? ok(Data()) : APDUResponse(data: Data(), sw1: 0x63, sw2: 0xC2)
        }
        return APDUResponse(data: Data(), sw1: 0x6D, sw2: 0x00)
    }
}

private struct RefusingStore: LocalWalletStore {
    func load() throws -> LocalWallet { LocalWallet() }
    func save(_ wallet: LocalWallet) throws { throw CocoaError(.fileWriteNoPermission) }
    func erase() throws {}
}
