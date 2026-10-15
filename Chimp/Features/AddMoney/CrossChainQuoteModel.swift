import Foundation
import Observation

/// N1 · « From another chain » (tranche 2, D4, voie de repli du grant ; écran construit sans maquette, décision de Barth du
/// 2026-10-15) : chaîne et jeton d'origine, montant, devis **à blanc** de NEAR Intents vers Stellar (XLM ou USDC), la limite
/// dite en clair, **aucun bouton d'envoi**. Ne connaît que `OneClickQuoting`.
@Observable
final class CrossChainQuoteModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// La liste des jetons n'a pas pu être lue.
        case failed
    }

    enum QuoteIssue: Equatable {
        /// NEAR Intents n'a pas de prix pour cette paire en ce moment.
        case pairUnavailable
        case amountTooLow
        /// Réseau, API.
        case unavailable
    }

    enum QuoteState: Equatable {
        case idle
        case loading
        case quoted(OneClickQuote)
        case failed(QuoteIssue)
    }

    private(set) var phase: Phase = .loading
    private(set) var tokens: [OneClickToken] = []
    private(set) var chain = "eth"
    private(set) var origin: OneClickToken?
    /// Ce qui arriverait sur Stellar.
    private(set) var destination: SendAsset = .xlm
    private(set) var amount = AmountEntry()
    private(set) var quoteState: QuoteState = .idle
    private(set) var rejectedKeyCount = 0
    private(set) var technicalDetails: String?

    var isChainSheetPresented = false
    var isTokenSheetPresented = false

    private let client: OneClickQuoting
    private let recipient: String
    private let debounce: Duration
    private var quoteTask: Task<Void, Never>?

    /// L'ordre de la liste : les chaînes les plus courantes d'abord, puis les autres par nom.
    static let preferredChains = ["eth", "base", "arb", "sol", "btc", "op", "pol", "avax", "bsc", "near"]

    init(client: OneClickQuoting, recipient: String, debounce: Duration = .milliseconds(600)) {
        self.client = client
        self.recipient = recipient
        self.debounce = debounce
    }

    // MARK: Chargement

    func load() async {
        phase = .loading
        do {
            tokens = try await client.tokens()
            phase = .loaded
            selectChain(chains.contains(chain) ? chain : chains.first ?? chain)
        } catch is CancellationError {
        } catch {
            technicalDetails = SendFlowModel.details(error)
            phase = .failed
        }
    }

    /// Les chaînes d'origine (Stellar exclu : c'est la destination).
    var chains: [String] {
        let all = Set(tokens.map(\.blockchain)).subtracting(["stellar"])
        let preferred = Self.preferredChains.filter(all.contains)
        return preferred + all.subtracting(preferred).sorted { Self.chainName($0) < Self.chainName($1) }
    }

    /// Les jetons d'une chaîne : USDC d'abord, puis par symbole.
    func tokens(on chain: String) -> [OneClickToken] {
        tokens.filter { $0.blockchain == chain }.sorted { lhs, rhs in
            if (lhs.symbol == "USDC") != (rhs.symbol == "USDC") { return lhs.symbol == "USDC" }
            return lhs.symbol < rhs.symbol
        }
    }

    /// Le jeton Stellar d'arrivée, tel que l'API le nomme.
    var destinationToken: OneClickToken? {
        tokens.first { $0.blockchain == "stellar" && $0.symbol == destination.code }
    }

    /// Décimales tapables : celles du jeton, 6 au plus.
    var fractionDigits: Int { min(origin?.decimals ?? 6, 6) }

    // MARK: Choix

    func selectChain(_ chain: String) {
        self.chain = chain
        origin = tokens(on: chain).first
        isChainSheetPresented = false
        amount = amount.clamped(toFractionDigits: fractionDigits)
        amountChanged()
    }

    func selectOrigin(_ token: OneClickToken) {
        origin = token
        isTokenSheetPresented = false
        amount = amount.clamped(toFractionDigits: fractionDigits)
        amountChanged()
    }

    func selectDestination(_ asset: SendAsset) {
        guard asset == .xlm || asset == .usdc else { return }
        destination = asset
        amountChanged()
    }

    func press(_ key: ChimpKeypadKey) {
        if amount.apply(key, maxFractionDigits: fractionDigits) {
            amountChanged()
        } else {
            rejectedKeyCount += 1
        }
    }

    // MARK: Devis

    /// Montant tapé en unités du jeton d'origine (entier, sans arrondi) ; `nil` si rien n'est tapé.
    static func units(of amount: Decimal, decimals: Int) -> String? {
        guard amount > 0 else { return nil }
        var value = amount
        for _ in 0..<decimals { value *= 10 }
        guard value == value.truncated(to: 0) else { return nil }
        return NSDecimalNumber(decimal: value).stringValue
    }

    private func amountChanged() {
        quoteTask?.cancel()
        guard amount.value > 0, origin != nil else {
            quoteState = .idle
            return
        }
        quoteState = .loading
        let debounce = debounce
        quoteTask = Task { [weak self] in
            if debounce > .zero {
                try? await Task.sleep(for: debounce)
                guard !Task.isCancelled else { return }
            }
            await self?.refreshQuote()
        }
    }

    func refreshQuote() async {
        guard let origin, let destination = destinationToken,
              let units = Self.units(of: amount.value, decimals: origin.decimals) else {
            quoteState = .idle
            return
        }
        /// Le devis qui arrive correspond-il encore à l'écran (jeton, montant, destination) ?
        func isCurrent() -> Bool {
            self.origin == origin && Self.units(of: amount.value, decimals: origin.decimals) == units && destinationToken == destination
        }
        quoteState = .loading
        do {
            let quote = try await client.dryQuote(origin: origin, amountUnits: units, destination: destination, recipient: recipient)
            guard isCurrent() else { return }
            technicalDetails = nil
            quoteState = .quoted(quote)
        } catch is CancellationError {
        } catch {
            guard isCurrent() else { return }
            technicalDetails = SendFlowModel.details(error)
            quoteState = .failed(Self.issue(for: error))
        }
    }

    static func issue(for error: Error) -> QuoteIssue {
        switch error {
        case OneClickError.pairUnavailable: .pairUnavailable
        case OneClickError.amountTooLow: .amountTooLow
        default: .unavailable
        }
    }

    // MARK: Noms

    /// Nom affiché d'une blockchain de l'API (« eth » → « Ethereum ») ; inconnue : le code en capitales.
    static func chainName(_ code: String) -> String {
        let names = [
            "eth": "Ethereum", "base": "Base", "arb": "Arbitrum", "sol": "Solana", "btc": "Bitcoin", "op": "Optimism",
            "pol": "Polygon", "avax": "Avalanche", "bsc": "BNB Chain", "near": "NEAR", "tron": "Tron", "ton": "TON",
            "sui": "Sui", "xrp": "XRP Ledger", "doge": "Dogecoin", "ltc": "Litecoin", "zec": "Zcash", "aptos": "Aptos",
            "cardano": "Cardano", "gnosis": "Gnosis", "bera": "Berachain", "monad": "Monad", "starknet": "Starknet",
            "scroll": "Scroll", "bch": "Bitcoin Cash", "dash": "Dash", "stellar": "Stellar",
        ]
        return names[code] ?? code.uppercased()
    }
}
