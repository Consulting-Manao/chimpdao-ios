import Foundation
import Testing
@testable import ChimpDAO

/// Réglages › Updates (étape 3) : la liste (Main account puis chaque wallet de carte, jugés contre la flotte) et le
/// parcours d'une mise à jour sur une fausse chaîne (`MockUpdatesService`) : rien n'est demandé si c'est déjà fait,
/// vérification avant tout, PIN, un tap, relecture, « Check again ».
@MainActor
struct UpdatesFlowTests {
    static let account = "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"
    static let bananaPocket = "CDGFNWFN7ZKU4XDPNXOGDQ4JZ7SZCMXLL3PYFESOCCA2L5DM3ZBCPEKC"
    static let leafPocket = "CAOL3K7VQTDZELQMKTAJB3WUQGL5JLXJKZ2Y44F77NH4CZNLW5I755XI"
    let k1 = MockChipReader.secp256k1Key.hex
    let r1 = MockChipReader.p256Key.hex

    private func waitUntil(seconds: Double = 3, _ condition: () -> Bool) async {
        for _ in 0..<Int(seconds * 100) where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func session(pending: Bool = false) -> AppSession {
        var wallet = LocalWallet(firstName: "Barth", tourSeen: true, account: SavedAccount(address: Self.account, cards: [
            SavedCard(publicKey: k1, chip: "infineon2Go", tokenID: 7, pocket: Self.bananaPocket, name: "Banana", color: "banana"),
            SavedCard(publicKey: r1, chip: "duox", tokenID: 8, pocket: Self.leafPocket, name: "Leaf", color: "leaf"),
        ]))
        if pending {
            let trace = PaymentTrace(token: "C", from: "C", destination: "G", units: 1, nonce: 1, preparedAtLedger: 1, expirationLedger: 2)
            wallet.pendingSend = PendingSend(trace: trace, recipient: "G", recipientName: nil, drawerTitle: "Main account", asset: "XLM", amount: 1, signedAt: .now)
        }
        return AppSession(store: InMemoryLocalWalletStore(wallet), config: .testnet)
    }

    private var cards: [CardBalance] {
        [
            CardBalance(id: k1, number: "0007", name: "Card", color: .jungle, assets: [], pocket: Self.bananaPocket, chip: .infineon2Go),
            CardBalance(id: r1, number: "0008", name: "Card", color: .jungle, assets: [], pocket: Self.leafPocket, chip: .duox),
        ]
    }

    // MARK: Liste

    @Test("Liste : le Main account puis chaque wallet ; noms du téléphone ; le compte en retard, les wallets suivent la flotte")
    func list() async {
        let model = UpdatesModel(session: session(), service: MockUpdatesService(scenario: .accountUpdate, delay: .zero))
        await model.refresh(cards: cards)
        #expect(model.rows.map(\.address) == [Self.account, Self.bananaPocket, Self.leafPocket])
        #expect(model.rows[0].status == .available(from: MockUpdatesService.oldHash, to: MockUpdatesService.headHash))
        #expect(model.rows[1].status == .managed)
        if case .card(_, let name, let color, let number, _) = model.rows[1].subject {
            #expect(name == "Banana")
            #expect(color == .banana)
            #expect(number == "0007")
        } else {
            Issue.record("expected a card row")
        }
        #expect(model.rows[0].target == UpdateTarget(kind: .account, address: Self.account, wasmHash: MockUpdatesService.headHash))
        #expect(model.rows[1].target == nil)
        #expect(model.readyCount == 1)
        #expect(model.summary == String(localized: "1 ready"))
    }

    @Test("Tout à jour : « Up to date », aucune ligne ne s'ouvre ; une carte Manual en retard s'ouvre (cible pocket)")
    func upToDateAndManual() async {
        let upToDate = UpdatesModel(session: session(), service: MockUpdatesService(scenario: .upToDate, delay: .zero))
        await upToDate.refresh(cards: cards)
        #expect(upToDate.readyCount == 0)
        #expect(upToDate.summary == String(localized: "Up to date"))

        let manual = UpdatesModel(session: session(), service: MockUpdatesService(scenario: .accountAndCard, manualPockets: [Self.bananaPocket], delay: .zero))
        await manual.refresh(cards: cards)
        #expect(manual.readyCount == 2)
        #expect(manual.rows[1].target?.kind == .pocket)
    }

    @Test("Stellar injoignable : la liste le dit, jamais « Up to date »")
    func readFailure() async {
        let model = UpdatesModel(session: session(), service: MockUpdatesService(scenario: .networkWhileReading, delay: .zero))
        await model.refresh(cards: cards)
        guard case .failed = model.phase else { Issue.record("expected failed, got \(model.phase)"); return }
        #expect(model.summary == nil)
    }

    // MARK: Parcours

    private func flow(_ service: MockUpdatesService, row index: Int = 0, pending: Bool = false, signer: ChipSigner = MockChipSigner(delay: .zero)) async -> UpdateFlowModel? {
        let session = session(pending: pending)
        let list = UpdatesModel(session: session, service: service)
        await list.refresh(cards: cards)
        let row = list.rows[index]
        guard let target = row.target else { Issue.record("row \(index) has no update"); return nil }
        return UpdateFlowModel(row: row, target: target, session: session, signer: signer, service: service)
    }

    @Test("Main account : n'importe quelle carte du compte signe ; PIN demandé (une Infineon) ; un tap ; envoyée une fois")
    func accountUpdate() async throws {
        let service = MockUpdatesService(scenario: .accountUpdate, delay: .milliseconds(10))
        let model = try #require(await flow(service))
        #expect(Set(model.acceptedKeys.map(\.hex)) == [k1, r1])
        #expect(model.usesPIN)
        await model.start()
        #expect(model.isShowingPINSheet)
        #expect(model.prepared?.route == .accountHop)
        model.pinEntered("1234")
        await waitUntil { if case .done = model.screen { true } else { false } }
        #expect(model.screen == .done(.updated(transactionHash: String(repeating: "e", count: 64))))
        #expect(service.sendCount == 1)
        #expect(model.signerName == "Banana")
    }

    @Test("Déjà fait depuis un autre téléphone : « Already up to date », rien n'est signé")
    func alreadyDone() async throws {
        let service = MockUpdatesService(scenario: .alreadyDone, delay: .zero)
        let model = try #require(await flow(service))
        await model.start()
        #expect(model.screen == .done(.alreadyCurrent))
        #expect(!model.isShowingPINSheet && !model.isShowingTapSheet)
        #expect(service.sendCount == 0)
    }

    @Test("Un paiement attend son issue : rien ne se signe")
    func pendingPayment() async throws {
        let service = MockUpdatesService(scenario: .accountUpdate, delay: .zero)
        let model = try #require(await flow(service, pending: true))
        await model.start()
        #expect(model.problem?.kind == .pendingPayment)
        #expect(!model.isShowingPINSheet)
    }

    @Test("Version absente du réseau : refus avant tout tap, avec une phrase")
    func wasmMissing() async throws {
        let service = MockUpdatesService(scenario: .wasmMissing, delay: .zero)
        let model = try #require(await flow(service))
        await model.start()
        #expect(model.problem?.kind == .refused(.wasmMissing(hash: MockUpdatesService.headHash)))
        #expect(!model.isShowingPINSheet && !model.isShowingTapSheet)
        #expect(service.sendCount == 0)
    }

    @Test("Envoyée mais pas encore relue : « Check again » relit ; toujours pas là → retour à la vérification, sans renvoi")
    func notConfirmed() async throws {
        let service = MockUpdatesService(scenario: .notConfirmedYet, delay: .zero)
        let model = try #require(await flow(service))
        await model.start()
        model.pinEntered("1234")
        await waitUntil { model.isFailed }
        #expect(model.screen == .updating)
        await model.checkAgain()
        #expect(model.screen == .review)
        #expect(service.sendCount == 1)
    }

    @Test("Wallet d'une carte Manual : seule cette carte signe")
    func pocketUpdate() async throws {
        let service = MockUpdatesService(scenario: .accountAndCard, manualPockets: [Self.bananaPocket], delay: .zero)
        let model = try #require(await flow(service, row: 1))
        #expect(model.acceptedKeys.map(\.hex) == [k1])
        #expect(model.usesPIN)
        await model.start()
        #expect(model.prepared?.route == .pocketUpgrade)
    }
}
