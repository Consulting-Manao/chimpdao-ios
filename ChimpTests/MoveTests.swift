import Foundation
import Testing
@testable import ChimpDAO

/// Move (E1, E2) : le parcours Envoyer entre ses propres tiroirs (`moveFunds` du terminal, ARCHITECTURE §3.9).
struct MoveTests {
    private func loadedMove(cards: MockSendService.CardSetup = .allWithPin, order: SigningOrder = .pinThenTap) async -> (SendFlowModel, MockSendService) {
        let service = MockSendService(cardSetup: cards, delay: .zero, nfcDelay: .zero)
        let model = SendFlowModel(service: service, signingOrder: order, kind: .move)
        await model.load()
        return (model, service)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Par défaut : de Main vers le wallet de la première carte (maquette E1)")
    func defaults() async {
        let (model, _) = await loadedMove()
        #expect(model.isMove)
        #expect(model.selectedDrawer?.id == "main")
        #expect(model.destinationDrawer?.title == "Jungle's wallet")
        #expect(!model.canReview, "Pas de montant")
        model.setAmount(50)
        #expect(model.canReview)
        #expect(model.destinationBalanceLine.after == SendAsset.usdc.formattedWithCode(Decimal(string: "112.5")!))
    }

    @Test("Jamais le même tiroir des deux côtés : choisir l'autre côté échange, ⇅ échange")
    func neverSameDrawer() async {
        let (model, _) = await loadedMove()
        model.select(drawerID: "0421")
        #expect(model.selectedDrawer?.id == "0421")
        #expect(model.destinationDrawer?.id == "main")
        model.selectDestination(drawerID: "0421")
        #expect(model.destinationDrawer?.id == "0421")
        #expect(model.selectedDrawer?.id == "main")
        model.swapDrawers()
        #expect(model.selectedDrawer?.id == "0421")
        #expect(model.destinationDrawer?.id == "main")
        model.selectDestination(drawerID: "0688")
        #expect(model.selectedDrawer?.id == "0421")
        #expect(model.destinationDrawer?.id == "0688")
    }

    @Test("Montant au-delà du solde du tiroir de départ : refusé")
    func insufficient() async {
        let (model, _) = await loadedMove()
        model.select(drawerID: "0421")
        model.setAmount(100)
        #expect(model.amountIssue != nil)
        #expect(!model.canReview)
    }

    @Test("Brouillon : l'adresse exacte du tiroir d'arrivée, son nom, le tiroir de départ, marqué Move")
    func draft() async throws {
        let (model, _) = await loadedMove()
        model.setAmount(50)
        model.continueToReview()
        let draft = try #require(model.draft)
        #expect(draft.isMove)
        #expect(draft.recipient.address == MockReceiveDataSource.jungleAddress)
        #expect(draft.recipient.kind == .contract)
        #expect(draft.recipientName == "Jungle's wallet")
        #expect(draft.drawer.kind == .main)
        #expect(draft.destination?.id == "0421")
        #expect(model.isReviewPresented)
    }

    @Test("Depuis Main : n'importe quelle carte, PIN puis un tap, puis C9")
    func fromMain() async {
        let (model, service) = await loadedMove()
        model.setAmount(50)
        model.continueToReview()
        #expect(model.signingSteps == [.pin, .tapToSign])
        model.confirmReview()
        await waitUntil { model.signingStage == .enteringPin }
        model.pinEntered("1234")
        model.scanCard()
        await waitUntil { if case .finished(.sent) = model.signingStage { true } else { false } }
        guard case .finished(.sent(let receipt)) = model.signingStage else { Issue.record("expected sent, got \(model.signingStage)"); return }
        #expect(receipt.summary.recipientLabel == "Jungle's wallet")
        #expect(receipt.summary.drawerTitle == "Main account")
        #expect(service.signCount == 1)
    }

    @Test("Depuis le wallet d'une carte sans PIN : un seul tap ; vers Main")
    func fromCardWithoutPIN() async {
        let (model, service) = await loadedMove(cards: .noPin)
        model.select(drawerID: "0421")
        #expect(model.destinationDrawer?.id == "main")
        model.setAmount(10)
        model.continueToReview()
        #expect(model.signingSteps == [.tapToSign])
        model.confirmReview()
        // Pas de PIN : la fenêtre NFC s'ouvre dès « Looks good ».
        await waitUntil { if case .finished(.sent) = model.signingStage { true } else { false } }
        #expect(service.lastPin == nil)
        #expect(model.draft?.recipient.address == MockReceiveDataSource.mainAddress)
    }

    @Test("Un seul tiroir (Main seul) : pas de Move possible")
    func mainOnly() async {
        let service = MockSendService(dataScenario: .mainOnly, delay: .zero, nfcDelay: .zero)
        let model = SendFlowModel(service: service, kind: .move)
        await model.load()
        model.setAmount(1)
        #expect(model.destinationDrawer == nil)
        #expect(!model.canReview)
    }

    @Test("Un envoi n'a jamais de tiroir d'arrivée")
    func sendHasNoDestination() async {
        let service = MockSendService(delay: .zero, nfcDelay: .zero)
        let model = SendFlowModel(service: service)
        await model.load()
        #expect(model.destinationDrawer == nil)
        model.choose(SendContact(id: "maya", name: "Maya", color: .pink, address: MockSendService.mayaAddress))
        model.setAmount(10)
        model.continueToReview()
        #expect(model.draft?.isMove == false)
    }
}
