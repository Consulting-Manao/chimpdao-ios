#if CHIMP_ADMIN
import Foundation
import Testing
@testable import ChimpDAO

/// « Reserve money for a card » (Chimp Admin, D5), avec un faux contrat `prize` (`MockPrizeReserving`).
struct AdminPrizeTests {
    private func model(_ service: PrizeReserving?) -> AdminPrizeModel {
        AdminPrizeModel(card: MockChipReader.secp256k1Key, title: "Card #007", service: service)
    }

    @Test("Lecture puis dépôt : le montant en stroops, le total relu, les dépôts s'additionnent")
    func reserve() async {
        let service = MockPrizeReserving()
        service.delay = .zero
        let model = model(service)
        await model.load()
        #expect(model.reservation == .loaded(PrizeReservation(tokenID: 7, reserved: 0)))
        model.amountText = "25"
        await model.reserve()
        #expect(service.reserved[MockChipReader.secp256k1Key] == TokenAmount(250_000_000))
        await model.reserve()
        #expect(model.reservation == .loaded(PrizeReservation(tokenID: 7, reserved: TokenAmount(500_000_000))))
        #expect(model.message == .reserved("Reserved 25 test XLM for Card #007. Now reserved: 50 XLM."))
    }

    @Test("Montant hors de 1 à 1000, ou contrat illisible : rien n'est envoyé")
    func refused() async {
        let service = MockPrizeReserving()
        service.delay = .zero
        let model = model(service)
        await model.load()
        for bad in ["0", "1001", "abc", ""] {
            model.amountText = bad
            #expect(!model.canReserve)
            await model.reserve()
        }
        #expect(service.reserved.isEmpty)

        let noContract = self.model(nil)
        await noContract.load()
        #expect(noContract.reservation == .failed("The prize contract isn't deployed on testnet yet."))
        #expect(!noContract.canReserve)
    }

    @Test("Échec du dépôt : dit tel quel, rien n'est compté")
    func failure() async {
        let service = MockPrizeReserving(failing: true)
        service.delay = .zero
        let model = model(service)
        await model.load()
        await model.reserve()
        guard case .failed = model.message else { Issue.record("expected a failure"); return }
        #expect(model.reservation == .loaded(PrizeReservation(tokenID: 7, reserved: 0)))
    }
}
#endif
