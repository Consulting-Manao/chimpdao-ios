import Observation
import SwiftUI

/// H1 · A gift card : ce qu'on montre des soldes d'une carte neuve chargée d'argent. Les prix viennent de l'oracle du
/// Wallet (Reflector) ; sans prix, les montants restent par actif (comme B1). Rien n'est signé ni payé.
@Observable
final class GiftCardModel {
    struct Line: Equatable, Identifiable {
        let code: String
        /// « 250 XLM ».
        let amount: String
        /// « $62.50 », `nil` sans prix.
        let value: String?

        var id: String { code }
    }

    let choice: CardChoice
    private let oracle: PriceOracle?
    private(set) var prices: [String: Decimal] = ["USDC": 1]
    private var hasLoaded = false

    init(choice: CardChoice, oracle: PriceOracle?) {
        self.choice = choice
        self.oracle = oracle
    }

    var number: String { choice.tokenID.map { String(format: "%04u", $0) } ?? "····" }

    private var held: [AssetAmount] { (choice.pocketBalances ?? []).filter { $0.amount != 0 } }

    /// Total sur la carte (« $102.50 »), ou par actif si un prix manque.
    var total: String { Self.total(held, prices: prices) }

    var lines: [Line] { Self.lines(held, prices: prices) }

    /// Prix des actifs détenus (une seule fois). Une lecture ratée laisse les montants par actif.
    func load() async {
        guard !hasLoaded, let oracle else { return }
        hasLoaded = true
        let codes = Set(held.map(\.code))
        guard !codes.isEmpty else { return }
        prices.merge(await oracle.usdPrices(for: codes)) { _, new in new }
    }

    // MARK: Formatage (fonctions pures, testées)

    private static var currency: Decimal.FormatStyle.Currency {
        Decimal.FormatStyle.Currency(code: "USD").presentation(.narrow)
    }

    static func total(_ assets: [AssetAmount], prices: [String: Decimal]) -> String {
        NetWorth.usd(assets.map { ($0.code, $0.amount) }, prices: prices)?.formatted(currency) ?? WalletViewModel.assetText(assets)
    }

    static func lines(_ assets: [AssetAmount], prices: [String: Decimal]) -> [Line] {
        assets.map { asset in
            let known = SendAsset.allCases.first { $0.code == asset.code }
            return Line(
                code: asset.code,
                amount: known?.formattedWithCode(asset.amount) ?? "\(asset.amount) \(asset.code)",
                value: prices[asset.code].map { NetWorth.truncatedToCents(asset.amount * $0).formatted(currency) }
            )
        }
    }
}

/// H1 · A gift card (maquette) : « Somebody likes you! », la carte et ce qu'elle contient, puis les deux choix d'A3.
/// « Put it in my jungle » = rejoindre un compte (A4 → A9, la nouvelle carte d'abord, puis une carte du compte) ;
/// « Start a fresh jungle with it » = créer un compte (A4 → A7). La ligne d'épargne de la maquette (« in XOXNO ») est
/// absente : Grow n'existe pas.
struct GiftCardView: View {
    @State var model: GiftCardModel
    /// `nil` : rejoindre n'est pas disponible (grisé).
    let onJoin: (() -> Void)?
    let onStartNewAccount: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 9) {
                    ChimpCard(name: String(localized: "Card N°\(model.number)"), color: .banana, number: model.number,
                              amount: model.total, subtitle: "inside")
                        .frame(width: 230)
                        .padding(.top, ChimpSpacing.xxl)
                        .padding(.bottom, ChimpSpacing.xxxl)
                    ForEach(model.lines) { line in
                        HStack {
                            Text(verbatim: line.amount)
                            Spacer()
                            if let value = line.value { Text(verbatim: value) }
                        }
                        .chimpFont(.rowTitle)
                        .foregroundStyle(.chimpTextPrimary)
                        .padding(.vertical, 11 + ChimpBorder.regular)
                        .padding(.horizontal, ChimpSpacing.ml + ChimpBorder.regular)
                        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.key), fill: Color(.chimpSurface))
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, ChimpSpacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 11) {
                Button { onJoin?() } label: {
                    VStack(spacing: 2) {
                        Text("Put it in my jungle")
                        Text("One of your cards will let it in")
                            .chimpFont(.captionStrong)
                    }
                }
                .buttonStyle(ChimpButtonStyle(kind: .primary))
                .disabled(onJoin == nil)
                ChimpButton("Start a fresh jungle with it", kind: .secondary, action: onStartNewAccount)
            }
            .padding(.horizontal, ChimpSpacing.xxl)
            .padding(.top, ChimpSpacing.l)
            .padding(.bottom, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
        .task { await model.load() }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: ChimpSpacing.sm) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Somebody\nlikes you!")
                    .chimpFont(.tourTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("This card came stuffed with bananas.")
                    .chimpFont(.bodyL)
            }
            .foregroundStyle(Color(.chimpOnCardBright))
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(.chimpyBanana)
                .resizable()
                .scaledToFit()
                .frame(height: 100)
                .padding(.bottom, -30)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, ChimpSpacing.xxl)
        .padding(.top, ChimpSpacing.xl)
        .padding(.bottom, 26)
        .background {
            Color(.chimpCardLeaf)
                .overlay { ChimpPattern() }
                .ignoresSafeArea(edges: .top)
        }
        .zIndex(1)
    }
}

#Preview {
    GiftCardView(
        model: GiftCardModel(choice: CardChoice(
            kind: .fresh, card: ChipKeyInfo(kind: .infineon2Go, publicKey: MockChipReader.secp256k1Key, pinActive: false),
            tokenID: 688, pocket: nil, pocketIsEmpty: false,
            pocketBalances: [AssetAmount(code: "XLM", amount: 250), AssetAmount(code: "USDC", amount: 40)]
        ), oracle: nil),
        onJoin: {}, onStartNewAccount: {}
    )
}
