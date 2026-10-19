import Foundation
import Testing
@testable import ChimpDAO

/// Écrans H atteignables : H1 (carte neuve chargée d'argent, depuis A2) et H2 (« Look who's back! », téléphone qui a
/// déjà ouvert un compte fermé depuis).
struct GiftCardAndNewPhoneTests {
    private func makeModel(service: MockOnboardingService.Scenario, session: AppSession = AppSession(store: InMemoryLocalWalletStore(), config: .testnet)) -> OnboardingModel {
        OnboardingModel(session: session, reader: MockChipReader(scenario: .infineon, delay: .zero),
                        service: MockOnboardingService(scenario: service, delay: .zero),
                        signer: MockChipSigner(delay: .zero), joinService: MockAddCardService(),
                        makeSetup: { try AccountSetupModel(choice: $0, service: MockAccountSetupService(delay: .zero), creator: AccountCreator(chain: MockAccountCreationChain(delay: .zero)), signer: MockChipSigner(delay: .zero), session: nil) })
    }

    private func scanned(_ service: MockOnboardingService.Scenario) async -> OnboardingModel {
        let model = makeModel(service: service)
        model.path = [.reading]
        await model.scan()
        return model
    }

    private final class FixedOracle: PriceOracle, @unchecked Sendable {
        let prices: [String: Decimal]
        private(set) var asked: [Set<String>] = []
        init(_ prices: [String: Decimal]) { self.prices = prices }
        func usdPrices(for codes: Set<String>) async -> [String: Decimal] {
            asked.append(codes)
            return prices.filter { codes.contains($0.key) }
        }
    }

    private var giftChoice: CardChoice {
        CardChoice(kind: .fresh, card: ChipKeyInfo(kind: .infineon2Go, publicKey: MockChipReader.secp256k1Key, pinActive: false),
                   tokenID: 688, pocket: "CPOCKET", pocketIsEmpty: false,
                   pocketBalances: [AssetAmount(code: "XLM", amount: 250), AssetAmount(code: "USDC", amount: 0)])
    }

    // MARK: H1

    @Test("A2 : carte neuve avec de l'argent sur son wallet → H1 ; vide → A3")
    func routesGiftCard() async {
        let loaded = await scanned(.freshWithMoney)
        guard case .giftCard(let choice) = loaded.path.last else {
            Issue.record("H1 attendu, obtenu \(String(describing: loaded.path.last))")
            return
        }
        #expect(choice.pocketBalances?.map(\.code) == ["XLM", "USDC"])
        #expect(choice.tokenID == 688)

        let empty = await scanned(.fresh)
        guard case .choice = empty.path.last else {
            Issue.record("A3 attendu")
            return
        }
    }

    @Test("A2 : carte orpheline, même avec de l'argent → A3 « This card is yours » (comme le terminal)")
    func orphanIsNotAGift() {
        let inspection = CardInspection(
            card: ChipKeyInfo(kind: .infineon2Go, publicKey: MockChipReader.secp256k1Key, pinActive: false),
            resolution: .orphan(lastKnown: nil), tokenID: 1, pocket: "CPOCKET", pocketIsEmpty: false,
            pocketBalances: [AssetAmount(code: "XLM", amount: 5)]
        )
        #expect(!inspection.isLoadedGiftCard)
    }

    @Test("H1 : « Put it in my jungle » rejoint un compte, « Start a fresh jungle » crée un compte")
    func giftCardChoices() async {
        let model = await scanned(.freshWithMoney)
        guard case .giftCard(let choice) = model.path.last else { return }
        model.startJoin(with: choice)
        #expect(model.path.last == .join)
        #expect(model.join != nil)

        let other = await scanned(.freshWithMoney)
        guard case .giftCard(let again) = other.path.last else { return }
        other.startNewAccount(with: again)
        #expect(other.path.last == .yourName)
    }

    @Test("H1 : total et lignes en dollars avec les prix de l'oracle ; actifs à zéro masqués ; sans prix, par actif")
    func giftCardAmounts() async {
        let oracle = FixedOracle(["XLM": Decimal(string: "0.25")!])
        let model = GiftCardModel(choice: giftChoice, oracle: oracle)
        #expect(model.total == WalletViewModel.assetText([AssetAmount(code: "XLM", amount: 250)]), "Avant les prix : par actif")
        await model.load()
        #expect(oracle.asked == [["XLM"]], "Seulement les actifs détenus")
        let usd = Decimal.FormatStyle.Currency(code: "USD").presentation(.narrow)
        #expect(model.total == Decimal(string: "62.5")!.formatted(usd))
        #expect(model.lines.map(\.code) == ["XLM"])
        #expect(model.lines.first?.amount == SendAsset.xlm.formattedWithCode(250))
        #expect(model.lines.first?.value == Decimal(string: "62.5")!.formatted(usd))

        let noPrice = GiftCardModel(choice: giftChoice, oracle: nil)
        await noPrice.load()
        #expect(noPrice.lines.first?.value == nil)
    }

    // MARK: H2

    @Test("H2 : « Look who's back! » après « Disconnect this phone », pas sur un téléphone neuf ni après « Erase everything »")
    func returningPhone() throws {
        let store = InMemoryLocalWalletStore(LocalWallet(
            firstName: "Barth", tourSeen: true,
            account: SavedAccount(address: "CAAAA", cards: [SavedCard(publicKey: "04aa", chip: "infineon2Go", tokenID: 7, pocket: nil, name: "Banana", color: "banana")])
        ))
        let session = AppSession(store: store, config: .testnet)
        #expect(!makeModel(service: .fresh, session: session).isReturning)
        try session.disconnect()
        #expect(makeModel(service: .fresh, session: session).isReturning)
        try session.eraseEverything()
        #expect(!makeModel(service: .fresh, session: session).isReturning)
        #expect(!makeModel(service: .fresh).isReturning)
    }
}
