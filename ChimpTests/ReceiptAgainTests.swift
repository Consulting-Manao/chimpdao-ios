import Foundation
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 3, étape 5 : chaque bouton « again » d'un reçu relance sa propre action, et seulement elle.
/// Garde-fou du bug du 2026-10-14 : « Pay again » du reçu d'un envoi (C9) était branché par erreur sur l'action du swap
/// (fermeture finale sans étiquette associée au mauvais paramètre). Les reçus n'ont plus qu'une action typée,
/// `ReceiptAgain`, que chaque écran traite explicitement.
@MainActor
struct ReceiptAgainTests {
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test("Reçus de l'Activity : envoi → Pay again, paiement reçu → Send back, swap → Swap again ; Move et carte ajoutée : aucun")
    func receiptButtons() async throws {
        let activity = ActivityViewModel(source: MockActivityDataSource(scenario: .standard))
        await activity.refresh()
        let receipts = activity.records.compactMap { activity.receipt(for: $0) }
        func again(_ stamp: ActivityStamp) throws -> ReceiptAgain? {
            try #require(receipts.first { $0.stamp == stamp }, "pas de reçu \(stamp) dans les données factices").again
        }

        guard case .payAgain(let pay)? = try again(.paid) else { Issue.record("envoi : pas « Pay again »"); return }
        #expect(pay.origin == .payAgain)
        guard case .sendBack(let back)? = try again(.gotIt) else { Issue.record("reçu : pas « Send back »"); return }
        #expect(back.origin == .sendBack)
        guard case .swapAgain? = try again(.swapped) else { Issue.record("swap : pas « Swap again »"); return }
        #expect(try again(.moved) == nil)
        if receipts.contains(where: { $0.stamp == .newCard }) { #expect(try again(.newCard) == nil) }
    }

    @Test("Activity : Pay again et Send back ouvrent Envoyer (jamais Swap), Swap again ouvre Swap (jamais Envoyer)")
    func activityRouting() {
        let send = SendPrefill(address: MockSendService.mayaAddress, asset: .xlm, amount: 5, origin: .payAgain)
        let back = SendPrefill(address: MockSendService.mayaAddress, asset: .usdc, amount: 2, origin: .sendBack)
        let swap = SwapPrefill(drawerAddress: MockReceiveDataSource.mainAddress, given: .xlm, received: .usdc, amount: 400)
        #expect(ReceiptAgain.payAgain(send).sendPrefill == send)
        #expect(ReceiptAgain.payAgain(send).swapPrefill == nil)
        #expect(ReceiptAgain.sendBack(back).sendPrefill == back)
        #expect(ReceiptAgain.sendBack(back).swapPrefill == nil)
        #expect(ReceiptAgain.swapAgain(swap).swapPrefill == swap)
        #expect(ReceiptAgain.swapAgain(swap).sendPrefill == nil)
    }

    @Test("Reçu de C9 (après un envoi) : seul Pay again relance Envoyer, avec l'envoi qui vient de partir")
    func sendReceipt() async {
        let model = SendFlowModel(service: MockSendService(delay: .zero, nfcDelay: .zero))
        model.pasteAddress(MockSendService.mayaAddress)
        await model.load()
        model.setAmount(25)
        model.continueToReview()
        model.confirmReview()
        await waitUntil { model.signingStage == .enteringPin }
        model.pinEntered("1234")
        model.scanCard()
        await waitUntil { model.sendAgainPrefill != nil }
        var relaunched: [SendPrefill] = []
        model.onSendAgain = { relaunched.append($0) }

        model.receiptAgain(.swapAgain(SwapPrefill(drawerAddress: MockReceiveDataSource.mainAddress, given: .xlm, received: .usdc, amount: 1)))
        model.receiptAgain(.sendBack(SendPrefill(address: MockSendService.mayaAddress, asset: .xlm, amount: 1, origin: .sendBack)))
        try? await Task.sleep(for: .milliseconds(500))
        #expect(relaunched.isEmpty, "Un reçu d'envoi ne lance ni un swap ni un renvoi")

        model.receiptAgain(.payAgain(SendPrefill(address: MockSendService.mayaAddress, asset: .usdc, amount: 25, origin: .payAgain)))
        await waitUntil { !relaunched.isEmpty }
        #expect(relaunched == [SendPrefill(address: MockSendService.mayaAddress, asset: .usdc, amount: 25, origin: .payAgain)])
    }

    @Test("Reçu de E5 (après un swap) : seul Swap again relance le swap, avec le swap du reçu")
    func swapReceipt() {
        let model = SwapFlowModel(service: MockSwapService(delay: .zero), quoteDebounce: .zero)
        var relaunched: [SwapPrefill] = []
        model.onSwapAgain = { relaunched.append($0) }
        let swap = SwapPrefill(drawerAddress: MockReceiveDataSource.mainAddress, given: .xlm, received: .usdc, amount: 400)

        model.receiptAgain(.payAgain(SendPrefill(address: MockSendService.mayaAddress, asset: .xlm, amount: 1, origin: .payAgain)))
        model.receiptAgain(.sendBack(SendPrefill(address: MockSendService.mayaAddress, asset: .xlm, amount: 1, origin: .sendBack)))
        #expect(relaunched.isEmpty, "Un reçu de swap ne lance pas Envoyer")

        model.receiptAgain(.swapAgain(swap))
        #expect(relaunched == [swap])
    }
}
