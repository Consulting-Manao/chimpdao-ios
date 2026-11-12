import Foundation
import Testing
@testable import ChimpDAO

/// « Somebody likes you! » (carte partenaire, D5) avec un faux contrat `prize` (`MockPrizeService`) : vérification, PIN,
/// un seul tap, et les garde-fous d'Envoyer (rien de signé avant la vérification, trace gardée dès le retour de la carte,
/// aucune double signature, issue incertaine revérifiée, ligne d'historique).
struct PrizeClaimTests {
    private func waitUntil(seconds: Double = 3, _ condition: () -> Bool) async {
        for _ in 0..<Int(seconds * 100) where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func model(_ service: MockPrizeService, gift: PrizeGift? = MockPrizeService.banana) async -> PrizeClaimModel {
        let model = PrizeClaimModel(service: service, gift: gift)
        await model.loadIfNeeded()
        return model
    }

    /// Jusqu'au PIN tapé (Infineon).
    private func signWithPIN(_ model: PrizeClaimModel) async {
        model.open()
        model.confirmReview()
        await waitUntil { model.stage == .enteringPin }
        model.pinEntered("1234")
    }

    @Test("Ouvrir, vérifier, PIN, un tap : l'attestation et deux autorisations du wallet (Infineon), envoyé une fois")
    func success() async {
        let service = MockPrizeService(delay: .milliseconds(20))
        let model = await model(service)
        #expect(model.signingSteps == [.pin, .tapToSign])
        await signWithPIN(model)
        await waitUntil { if case .finished = model.stage { true } else { false } }
        guard case .finished(.sent(let receipt)) = model.stage else { Issue.record("expected sent, got \(model.stage)"); return }
        #expect(receipt.gift.amount == 250)
        #expect(service.signedDigestCounts == [3])
        #expect(service.submitted == 1)
        #expect(service.pendingSend == nil)
    }

    @Test("DUOX : pas de PIN, une attestation et une autorisation du wallet")
    func duox() async {
        let duox = PrizeGift(
            cardKey: MockChipReader.p256Key, cardName: "Leaf", cardColor: .leaf, cardNumber: nil,
            wallet: MockPrizeService.banana.wallet, amount: 10, usesPin: false, curve: .p256
        )
        let signer = MockChipSigner(outcome: .success(.p256(signature: Data(repeating: 0x11, count: 64), rndB: Data(repeating: 0xAB, count: 16))), delay: .zero)
        let service = MockPrizeService(gifts: [duox], signer: signer, delay: .milliseconds(20))
        let model = await model(service, gift: duox)
        #expect(model.signingSteps == [.tapToSign])
        model.open()
        model.confirmReview()
        await waitUntil { if case .finished = model.stage { true } else { false } }
        #expect(service.signedDigestCounts == [2])
        guard case .finished(.sent) = model.stage else { Issue.record("expected sent, got \(model.stage)"); return }
    }

    @Test("Le coffre a changé : rien n'est signé, la vérification montre le nouveau montant")
    func amountChanged() async {
        let service = MockPrizeService(scenario: .amountChanged(300), delay: .milliseconds(20))
        let model = await model(service)
        await signWithPIN(model)
        await waitUntil { model.preparationIssue != nil }
        #expect(model.preparationIssue == .amountChanged)
        #expect(model.gift?.amount == 300)
        #expect(model.stage == .idle)
        #expect(service.signedDigestCounts.isEmpty)
        #expect(service.submitted == 0)
    }

    @Test("Déjà ouvert (coffre vide) ou wallet qui ne détient plus la carte : rien n'est signé")
    func refusedBeforeSigning() async {
        for (scenario, issue) in [(MockPrizeService.Scenario.amountChanged(0), PrizeClaimModel.PreparationIssue.alreadyOpened),
                                  (.notOwner, .notOwner)] {
            let service = MockPrizeService(scenario: scenario, delay: .milliseconds(20))
            let model = await model(service)
            await signWithPIN(model)
            await waitUntil { model.preparationIssue != nil }
            #expect(model.preparationIssue == issue)
            #expect(service.signedDigestCounts.isEmpty)
            #expect(service.submitted == 0)
        }
    }

    @Test("Pas de réponse, autorisation encore valable : gardée sur le téléphone, « Try again » renvoie la même signature")
    func unansweredThenResend() async {
        let until = Date.now.addingTimeInterval(120)
        let service = MockPrizeService(scenario: .unanswered(.waiting(untilLedger: 1_120, estimatedEnd: until)), delay: .milliseconds(20))
        let model = await model(service)
        await signWithPIN(model)
        await waitUntil { if case .finished = model.stage { true } else { false } }
        #expect(model.stage == .finished(.waiting(until: until)))
        #expect(service.pendingSend?.prize?.cardName == "Banana")
        #expect(service.pendingSend?.trace.eventSender == MockPrizeService.prize)
        #expect(model.canResend)
        model.resend()
        await waitUntil { service.submitted == 2 }
        // Aucune nouvelle signature : la même autorisation (même nonce), une seule exécution possible.
        #expect(service.signedDigestCounts == [3])
    }

    @Test("Pas de réponse, puis « Nothing was moved » (certain) : trace effacée, nouvelle tentative possible")
    func unansweredThenNothing() async {
        let service = MockPrizeService(scenario: .unanswered(.nothingSent), delay: .milliseconds(20))
        let model = await model(service)
        await signWithPIN(model)
        await waitUntil { if case .finished = model.stage { true } else { false } }
        #expect(model.stage == .finished(.nothingSent))
        #expect(service.pendingSend == nil)
        #expect(model.canTryAgain)
        model.tryAgain()
        #expect(model.stage == .idle)
    }

    @Test("Un retrait en attente gardé sur le téléphone : son état d'abord (« Check again »), jamais un nouveau")
    func resumesPending() async {
        let trace = PaymentTrace(
            token: "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC", from: MockPrizeService.banana.wallet,
            destination: MockPrizeService.banana.wallet, units: 2_500_000_000, nonce: 42, preparedAtLedger: 1_000,
            expirationLedger: 1_120, eventSender: MockPrizeService.prize, eventRecipient: MockPrizeService.banana.wallet
        )
        let pending = PendingSend(
            trace: trace, recipient: trace.from, recipientName: "Banana's wallet", drawerTitle: "Banana's wallet", asset: "xlm",
            amount: 250, signedAt: .now, prize: PendingPrize(cardKey: MockChipReader.secp256k1Key.hex, cardName: "Banana")
        )
        let service = MockPrizeService(scenario: .unanswered(.nothingSent), delay: .milliseconds(20), pending: pending)
        let model = await model(service, gift: nil)
        #expect(model.resumedPending)
        #expect(model.stage == .finished(.nothingSent))
        #expect(!model.canTryAgain)
        #expect(model.shownGift?.cardName == "Banana")
    }

    @Test("Une autre opération attend son issue (un envoi) : rien ne se signe")
    func blockedByOtherPending() async {
        let trace = PaymentTrace(
            token: "C", from: "C", destination: "G", units: 1, nonce: 1, preparedAtLedger: 1, expirationLedger: 2
        )
        let pending = PendingSend(trace: trace, recipient: "G", recipientName: nil, drawerTitle: "Main account", asset: "xlm", amount: 1, signedAt: .now)
        let service = MockPrizeService(delay: .milliseconds(20), pending: pending)
        let model = await model(service)
        #expect(model.blockedByPendingPayment)
        model.open()
        model.confirmReview()
        #expect(model.stage == .idle)
    }

    @Test("Une autre carte tapée : « Wrong banana! », rien n'est envoyé")
    func wrongCard() async {
        let service = MockPrizeService(signer: OtherCardSigner(), delay: .milliseconds(20))
        let model = await model(service)
        await signWithPIN(model)
        await waitUntil { if case .wrongCard = model.stage { true } else { false } }
        guard case .wrongCard(let wrong) = model.stage else { Issue.record("expected wrongCard, got \(model.stage)"); return }
        #expect(wrong.needed?.name == "Banana")
        #expect(service.submitted == 0)
    }

    @Test("Historique : un cadeau ouvert est une réception du wallet de la carte, titrée « A gift for … »")
    func activityLine() {
        let record = PrizeReceipt(gift: MockPrizeService.banana, transactionHash: "ab", sentAt: .now, explorerURL: nil)
            .activityRecord(prize: MockPrizeService.prize)
        #expect(record.isGift == true)
        #expect(record.from == MockPrizeService.prize)
        #expect(record.to == MockPrizeService.banana.wallet)
        #expect(record.kind(drawers: [MockPrizeService.banana.wallet]) == .received)
        let row = ActivityViewModel.row(
            for: record, drawers: [ActivityDrawer(address: MockPrizeService.banana.wallet, name: "Banana", title: "Banana's wallet", isMain: false)],
            addresses: [MockPrizeService.banana.wallet], cardName: { _ in nil }
        )
        #expect(row?.title == "A gift for Banana")
    }
}

/// Une carte qui n'est pas celle du cadeau.
private struct OtherCardSigner: ChipSigner {
    func sign(digests: [Data], expectedKey: ChipPublicKey, pin: String?) async throws -> [ChipSignedDigest] { throw ChipError.wrongCard }
    func sign(digests: [Data], acceptedKeys: [ChipPublicKey], pin: String?) async throws -> CardSignatures { throw ChipError.wrongCard }
    func sign(
        digests: [Data], followUp: @escaping @Sendable ([ChipSignedDigest]) throws -> [Data], acceptedKeys: [ChipPublicKey], pin: String?
    ) async throws -> CardSignatures {
        throw ChipError.cardNotAccepted(tapped: MockChipReader.p256Key)
    }
    func readOrSign(digests: [Data], acceptedKeys: [ChipPublicKey]) async throws -> ReadOrSign { throw ChipError.wrongCard }
    func setPINAndSign(digests: [Data], expectedKey: ChipPublicKey, newPIN: String) async throws -> PINSetupSignatures { throw ChipError.wrongCard }
    func verifyPIN(expectedKey: ChipPublicKey, pin: String) async throws { throw ChipError.wrongCard }
}
