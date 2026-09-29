import Foundation
import Testing
@testable import ChimpDAO

/// Déroulé de la signature (C4 → C5 / C6) dans les deux ordres PIN / tap, avec le service factice.
struct SendSigningTests {
    /// Parcours prêt sur la vérification : 10 USDC pour Maya, depuis `drawerID`.
    private func reviewReady(
        drawerID: String,
        order: SigningOrder,
        cards: MockSendService.CardSetup = .allWithPin,
        nfcDelay: Duration = .zero
    ) async -> (SendFlowModel, MockSendService) {
        let service = MockSendService(cardSetup: cards, delay: .zero, nfcDelay: nfcDelay)
        let model = SendFlowModel(service: service, signingOrder: order)
        await model.load()
        model.choose(SendContact(id: "maya", name: "Maya", color: .pink, address: MockSendService.mayaAddress))
        model.select(drawerID: drawerID)
        model.setAmount(10)
        model.continueToReview()
        return (model, service)
    }

    private func isSent(_ model: SendFlowModel) -> Bool {
        if case .finished(.sent) = model.signingStage { return true }
        return false
    }

    /// Attend qu'une tâche lancée par le ViewModel ait fait son effet (2 s au plus).
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: PIN puis tap

    @Test("PIN puis tap : PIN, puis un seul tap qui signe avec ce PIN")
    func pinThenTap() async {
        let (model, service) = await reviewReady(drawerID: "0421", order: .pinThenTap)
        #expect(model.signingSteps == [.pin, .tapToSign])

        model.confirmReview()
        await waitUntil { model.signingStage == .enteringPin }
        #expect(model.signingStage == .enteringPin)

        model.pinEntered("1234")
        #expect(model.signingStage == .waitingForTap(.tapToSign))

        model.scanCard()
        await waitUntil { isSent(model) }
        #expect(isSent(model))
        #expect(service.readCount == 0)
        #expect(service.signCount == 1)
        #expect(service.lastPin == "1234")
        #expect(model.pin.isEmpty, "Le PIN est effacé dès la signature")
    }

    // MARK: Tap puis PIN

    @Test("Tap puis PIN : lecture de la carte, PIN, second tap qui signe")
    func tapThenPin() async {
        let (model, service) = await reviewReady(drawerID: "0421", order: .tapThenPin)
        #expect(model.signingSteps == [.tapToRead, .pin, .tapToSign])

        model.confirmReview()
        await waitUntil { model.signingStage == .waitingForTap(.tapToRead) }
        #expect(model.signingStage == .waitingForTap(.tapToRead))

        model.scanCard()
        await waitUntil { model.signingStage == .enteringPin }
        #expect(model.signingStage == .enteringPin)
        #expect(model.cardCheck?.cardName == "Jungle")
        #expect(service.signCount == 0, "Le premier tap ne signe rien")

        model.pinEntered("4321")
        #expect(model.signingStage == .waitingForTap(.tapToSign))
        model.scanCard()
        await waitUntil { isSent(model) }
        #expect(service.readCount == 1)
        #expect(service.signCount == 1)
        #expect(service.lastPin == "4321")
    }

    @Test("Tap puis PIN depuis Main : le PIN et le second tap concernent la carte lue")
    func tapThenPinFromMain() async {
        let (model, service) = await reviewReady(drawerID: "main", order: .tapThenPin, cards: .mixed)
        model.confirmReview()
        await waitUntil { model.signingStage == .waitingForTap(.tapToRead) }
        model.scanCard()
        await waitUntil { model.signingStage == .enteringPin }
        #expect(model.cardCheck == CardCheck(cardName: "Jungle", cardColor: .jungle, usesPin: true))
        model.pinEntered("1111")
        model.scanCard()
        await waitUntil { isSent(model) }
        #expect(service.lastPin == "1111")
    }

    // MARK: Cartes sans PIN

    @Test("Carte sans PIN (DUOX) : un seul tap, dans les deux ordres, sans PIN envoyé", arguments: SigningOrder.allCases)
    func cardWithoutPin(order: SigningOrder) async {
        let (model, service) = await reviewReady(drawerID: "0421", order: order, cards: .noPin)
        #expect(model.signingSteps == [.tapToSign])

        model.confirmReview()
        await waitUntil { model.signingStage == .waitingForTap(.tapToSign) }
        #expect(model.signingStage == .waitingForTap(.tapToSign))
        model.scanCard()
        await waitUntil { isSent(model) }
        #expect(service.readCount == 0)
        #expect(service.signCount == 1)
        #expect(service.lastPin == nil)
    }

    @Test("Wallet d'une carte sans PIN, compte mixte : pas de PIN demandé")
    func mixedAccountCardWithoutPin() async {
        let (model, _) = await reviewReady(drawerID: "0688", order: .pinThenTap, cards: .mixed)
        #expect(model.signingSteps == [.tapToSign])
    }

    // MARK: Anti-double envoi et verrous

    @Test("« Looks good » et « Scan my card » tapés deux fois : une seule préparation, une seule signature")
    func noDoubleSend() async {
        let (model, service) = await reviewReady(drawerID: "0421", order: .pinThenTap)
        model.confirmReview()
        model.confirmReview()
        await waitUntil { model.signingStage == .enteringPin }
        #expect(service.prepareCount == 1)

        model.pinEntered("1234")
        model.scanCard()
        model.scanCard()
        await waitUntil { isSent(model) }
        #expect(service.signCount == 1)

        model.confirmReview()
        #expect(service.prepareCount == 1, "Rien ne repart une fois signé")
    }

    @Test("Verrous : préparation, scan et après signature ; pas pendant le PIN ou l'attente du tap")
    func locks() async {
        let (model, _) = await reviewReady(drawerID: "0421", order: .pinThenTap, nfcDelay: .milliseconds(300))
        #expect(!model.isSigningLocked)
        model.confirmReview()
        #expect(model.isSigningLocked, "Préparation")
        await waitUntil { model.signingStage == .enteringPin }
        #expect(!model.isSigningLocked)
        model.pinEntered("1234")
        #expect(!model.isSigningLocked)
        model.scanCard()
        #expect(model.isSigningLocked, "Scan")
        await waitUntil { isSent(model) }
        #expect(model.isSigningLocked, "Signé puis envoyé")
        #expect(!model.isSigningSheetPresented)
    }

    @Test("Annuler pendant le PIN : retour à la vérification, PIN effacé ; impossible pendant un scan")
    func cancel() async {
        let (model, service) = await reviewReady(drawerID: "0421", order: .pinThenTap, nfcDelay: .milliseconds(300))
        model.confirmReview()
        await waitUntil { model.signingStage == .enteringPin }
        model.pin = "12"
        model.cancelSigning()
        #expect(model.signingStage == .idle)
        #expect(model.pin.isEmpty)

        model.confirmReview()
        await waitUntil { model.signingStage == .enteringPin }
        #expect(service.prepareCount == 2)
        model.pinEntered("1234")
        model.scanCard()
        model.cancelSigning()
        #expect(model.signingStage == .scanning(.tapToSign), "Un scan en cours ne s'annule pas")
        await waitUntil { isSent(model) }
        #expect(isSent(model))
    }

    @Test("PIN incomplet ignoré")
    func incompletePinIgnored() async {
        let (model, _) = await reviewReady(drawerID: "0421", order: .pinThenTap)
        model.confirmReview()
        await waitUntil { model.signingStage == .enteringPin }
        model.pinEntered("12")
        #expect(model.signingStage == .enteringPin)
    }

    @Test("Le brouillon vérifié porte le réseau, le montant exact et le destinataire")
    func draftContent() async {
        let (model, _) = await reviewReady(drawerID: "main", order: .pinThenTap)
        let draft = model.draft
        #expect(draft?.network == .testnet)
        #expect(draft?.amount == 10)
        #expect(draft?.asset == .usdc)
        #expect(draft?.recipient.address == MockSendService.mayaAddress)
        #expect(draft?.recipientName == "Maya")
        #expect(draft?.drawer.id == "main")
    }

    @Test("Adresse groupée par 4 pour la vérification")
    func groupedAddress() {
        #expect(SendReviewView.grouped("GCQF355RQF") == "GCQF 355R QF")
    }
}
