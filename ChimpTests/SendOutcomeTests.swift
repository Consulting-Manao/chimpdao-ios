import Foundation
import Testing
@testable import ChimpDAO

/// Jalon 7, étape 2 : envoi après la signature et son issue (C9, non confirmé, attendre, rien n'est parti, impossible
/// à dire), paiement en attente gardé sur le téléphone, erreurs avant toute signature, tiroirs du vrai service.
struct SendOutcomeTests {
    /// Parcours prêt sur la vérification : 1 XLM pour Maya, depuis Main, ordre « PIN puis tap ».
    private func reviewReady(_ result: MockSendService.ResultScenario = .sent) async -> (SendFlowModel, MockSendService) {
        let service = MockSendService(resultScenario: result, delay: .zero, nfcDelay: .zero)
        service.authorizationWait = .seconds(1)
        let model = SendFlowModel(service: service, signingOrder: .pinThenTap)
        await model.loadIfNeeded()
        model.choose(SendContact(id: "maya", name: "Maya", color: .pink, address: MockSendService.mayaAddress))
        model.select(drawerID: "main")
        model.select(asset: .xlm)
        model.setAmount(1)
        model.continueToReview()
        return (model, service)
    }

    /// PIN puis tap, jusqu'au lancement du scan.
    private func signWithPIN(_ model: SendFlowModel) async {
        model.confirmReview()
        await waitUntil { model.signingStage == .enteringPin }
        model.pinEntered("1234")
        model.scanCard()
    }

    private func waitUntil(seconds: Double = 2, _ condition: () -> Bool) async {
        for _ in 0..<Int(seconds * 100) where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func outcome(_ model: SendFlowModel) -> SendOutcome? {
        if case .finished(let outcome) = model.signingStage { return outcome }
        return nil
    }

    // MARK: Issues

    @Test("Confirmé : C9 avec le reçu, un seul envoi, rien en attente sur le téléphone")
    func sent() async {
        let (model, service) = await reviewReady()
        await signWithPIN(model)
        await waitUntil { outcome(model) != nil }
        guard case .sent(let receipt) = outcome(model) else { Issue.record("expected sent"); return }
        #expect(receipt.summary.recipientName == "Maya")
        #expect(receipt.summary.amount == 1)
        #expect(receipt.summary.asset == .xlm)
        #expect(receipt.transactionHash == MockSendService.fakeHash)
        #expect(model.signed?.cardName == "Jungle")
        #expect(service.submitCount == 1)
        #expect(service.refreshCount == 1, "L'autorisation est revérifiée juste avant le tap")
        #expect(service.pendingSend == nil)
        #expect(model.isSigningLocked, "Pas de retour possible depuis C9, seulement ses boutons")
    }

    @Test("Non confirmé : gardé sur le téléphone, « Check again » le trouve confirmé, puis plus rien en attente")
    func notConfirmedThenSent() async {
        let (model, service) = await reviewReady(.notConfirmedThenSent)
        await signWithPIN(model)
        await waitUntil { outcome(model) != nil }
        #expect(outcome(model) == .notConfirmed)
        #expect(service.pendingSend?.trace.transactionHash == MockSendService.fakeHash)
        #expect(!model.canTryAgain, "Jamais « Send again » quand l'issue est incertaine")
        #expect(model.explorerURL != nil)
        model.confirmReview()
        #expect(service.prepareCount == 1)

        model.checkAgain()
        await waitUntil { service.checkCount == 2 && outcome(model) != nil }
        guard case .sent = outcome(model) else { Issue.record("expected sent"); return }
        #expect(service.pendingSend == nil)
        #expect(service.submitCount == 1)
    }

    @Test("Refusé après la signature : attendre jusqu'à l'expiration, sans renvoi possible, puis « Nothing was sent »")
    func waitThenNothingSent() async {
        let (model, service) = await reviewReady(.rejectedThenNothingSent)
        await signWithPIN(model)
        await waitUntil { outcome(model) != nil }
        guard case .waiting = outcome(model) else { Issue.record("expected waiting"); return }
        #expect(service.pendingSend != nil, "Gardé sur le téléphone tant que l'autorisation peut servir")
        #expect(!model.canTryAgain)
        model.confirmReview()
        #expect(service.prepareCount == 1, "Aucun renvoi pendant l'attente")

        // Revérification automatique à la fin de l'attente (1 s ici, + 1 s de marge).
        await waitUntil(seconds: 4) { outcome(model) == .nothingSent }
        #expect(outcome(model) == .nothingSent)
        #expect(service.pendingSend == nil)
        #expect(model.canTryAgain)
        model.tryAgain()
        #expect(model.signingStage == .idle)
        model.confirmReview()
        await waitUntil { model.signingStage == .enteringPin }
        #expect(service.prepareCount == 2, "Nouvel envoi seulement une fois certain que rien n'est parti")
    }

    @Test("Impossible de trancher : « Can't tell yet », gardé sur le téléphone, jamais « Try again »")
    func undetermined() async {
        let (model, service) = await reviewReady(.undetermined)
        await signWithPIN(model)
        await waitUntil { outcome(model) != nil }
        #expect(outcome(model) == .undetermined)
        #expect(service.pendingSend != nil)
        #expect(!model.canTryAgain)
        #expect(model.technicalDetails?.contains("no longer keeps") == true)
        model.checkAgain()
        await waitUntil { service.checkCount == 2 }
        #expect(service.checkCount == 2)
    }

    @Test("Envoyer rouvert avec un paiement en attente : son état est vérifié, jamais un nouvel envoi")
    func resumePending() async {
        let service = MockSendService(resultScenario: .undetermined, delay: .zero, nfcDelay: .zero)
        service.pendingSend = PendingSend(
            trace: PaymentTrace(token: "t", from: "C", destination: MockSendService.mayaAddress, units: 1, nonce: 1, preparedAtLedger: 1, expirationLedger: 121),
            recipient: MockSendService.mayaAddress, recipientName: "Maya", drawerTitle: "Main account",
            asset: SendAsset.xlm.rawValue, amount: 1, signedAt: .now
        )
        let model = SendFlowModel(service: service, signingOrder: .pinThenTap)
        await model.loadIfNeeded()
        #expect(model.resumedPending)
        #expect(service.checkCount == 1)
        #expect(outcome(model) == .undetermined)
        #expect(model.summary?.recipientName == "Maya")
        #expect(model.draft == nil)
        #expect(!model.canTryAgain)
    }

    // MARK: Erreurs avant toute signature

    @Test("PIN faux : retour au PIN avec les essais restants, rien d'envoyé ; le PIN est effacé")
    func wrongPIN() async {
        let (model, service) = await reviewReady()
        service.nextSignError = ChipError.wrongPIN(retriesLeft: 2)
        await signWithPIN(model)
        await waitUntil { model.signingStage == .enteringPin }
        #expect(model.pinState == .wrong(triesLeft: 2))
        #expect(model.pin.isEmpty)
        #expect(service.submitCount == 0)
    }

    @Test("PIN bloqué : état cadenas, rien d'envoyé")
    func lockedPIN() async {
        let (model, service) = await reviewReady()
        service.nextSignError = ChipError.pinLocked
        await signWithPIN(model)
        await waitUntil { model.pinState == .blocked }
        #expect(model.pinState == .blocked)
        #expect(service.submitCount == 0)
    }

    @Test("Feuille NFC annulée : retour à la feuille, sans message")
    func nfcCancelled() async {
        let (model, service) = await reviewReady()
        service.nextSignError = ChipError.cancelled
        await signWithPIN(model)
        await waitUntil { model.signingStage == .waitingForTap(.tapToSign) }
        #expect(model.signingStage == .waitingForTap(.tapToSign))
        #expect(model.tapProblem == nil)
    }

    @Test("Carte retirée trop tôt : message de Chimpy de l'onboarding")
    func cardMoved() async {
        let (model, service) = await reviewReady()
        service.nextSignError = ChipError.transport("Tag connection lost")
        await signWithPIN(model)
        await waitUntil { model.tapProblem != nil }
        #expect(model.tapProblem == .card(.cardMoved))
    }

    // MARK: Ce qui a été signé

    @Test("Résumé d'un paiement en attente : memo ID relu dans l'adresse M, adresse raccourcie sans nom")
    func summaryFromPending() {
        let pending = PendingSend(
            trace: PaymentTrace(token: "t", from: "C", destination: "M", units: 1, nonce: 1, preparedAtLedger: 1, expirationLedger: 2),
            recipient: MockSendService.exchangeMuxedAddress, recipientName: nil, drawerTitle: "Main account",
            asset: "usdc", amount: 25, signedAt: .now
        )
        let summary = SendSummary(pending, network: .testnet)
        #expect(summary.memoID == 1_234_567_890)
        #expect(summary.asset == .usdc)
        #expect(summary.recipientLabel == StellarAddressParser.short(MockSendService.exchangeMuxedAddress))
    }

    @Test("Paiement en attente enregistré dans le fichier du téléphone, puis effacé")
    func pendingPersisted() throws {
        let store = InMemoryLocalWalletStore()
        let session = AppSession(store: store, network: .testnet)
        let pending = PendingSend(
            trace: PaymentTrace(token: "t", from: "C", destination: "G", units: 5_000_000, nonce: -42, preparedAtLedger: 10, expirationLedger: 130, transactionHash: "ab", transactionMaxTime: 99),
            recipient: MockSendService.mayaAddress, recipientName: nil, drawerTitle: "Main account",
            asset: "xlm", amount: Decimal(string: "0.5")!, signedAt: Date(timeIntervalSince1970: 1_000)
        )
        try session.setPendingSend(pending)
        #expect(store.wallet.pendingSend == pending)
        let json = try String(data: FileLocalWalletStore.encoder.encode(store.wallet), encoding: .utf8)!
        let decoded = try FileLocalWalletStore.decoder.decode(LocalWallet.self, from: Data(json.utf8))
        #expect(decoded.pendingSend == pending)
        try session.setPendingSend(nil)
        #expect(store.wallet.pendingSend == nil)
    }

    @Test("Lien explorateur : Stellar Expert, réseau testnet, hash tel quel (`explorerTx` du terminal)")
    func explorerURL() {
        let hash = "6fe0ba5710cb2ade0b653e689f516cf01f3731cf401fb73769bd8d6beda75af4"
        #expect(ChimpNetworkConfig.testnet.explorerURL(transactionHash: hash).absoluteString
            == "https://stellar.expert/explorer/testnet/tx/\(hash)")
    }

    // MARK: Tiroirs du vrai service

    @Test("Vrai service : Main puis le wallet de chaque carte, PIN selon la puce, prix du XLM, récents vides")
    func chainContext() async throws {
        let infineon = MockChipReader.secp256k1Key
        let duox = MockChipReader.p256Key
        let session = AppSession(store: InMemoryLocalWalletStore(LocalWallet(account: SavedAccount(
            address: "CMAIN", cards: [
                SavedCard(publicKey: infineon.hex, chip: ChipKind.infineon2Go.rawValue, tokenID: 7, pocket: "CPOCKET1", name: "Banana", color: "banana"),
                SavedCard(publicKey: duox.hex, chip: ChipKind.duox.rawValue, tokenID: 8, pocket: "CPOCKET2", name: "Leaf", color: "leaf"),
            ]
        ))), network: .testnet)
        let snapshot = WalletSnapshot(
            currencyCode: "USD",
            main: DrawerBalance(assets: [AssetAmount(code: "XLM", amount: 999), AssetAmount(code: "USDC", amount: 0)]),
            cards: [
                CardBalance(id: infineon.hex, number: "0007", name: "Banana", color: .banana, assets: [AssetAmount(code: "XLM", amount: 1000)], pocket: "CPOCKET1"),
                CardBalance(id: duox.hex, number: "0008", name: "Leaf", color: .leaf, assets: [], pocket: "CPOCKET2"),
                CardBalance(id: "04ff", number: "····", name: "Card", color: .jungle, assets: [], pocket: nil),
            ],
            weeklyChange: nil, usdPrices: ["XLM": Decimal(string: "0.23")!], fetchedAt: .now
        )
        let service = ChainSendService(session: session, wallet: FixedWallet(snapshot: snapshot), signer: MockChipSigner())
        let context = try await service.fetchContext()
        #expect(context.drawers.map(\.address) == ["CMAIN", "CPOCKET1", "CPOCKET2"], "Carte sans wallet : pas de tiroir")
        #expect(context.drawers[0].kind == .main)
        #expect(context.drawers[0].balance(of: .xlm) == 999)
        #expect(context.drawers[0].usesPin)
        #expect(context.drawers[1].usesPin, "Infineon : PIN")
        #expect(!context.drawers[2].usesPin, "DUOX : jamais de PIN")
        #expect(context.drawers[1].title == "Banana's wallet")
        #expect(context.usdPrices[.xlm] == Decimal(string: "0.23"))
        #expect(context.recents.isEmpty)
    }
}

/// Wallet factice : un instantané fixe.
private struct FixedWallet: WalletDataSource {
    let snapshot: WalletSnapshot
    var firstName: String? { nil }
    func fetchWallet() async throws -> WalletSnapshot { snapshot }
}
