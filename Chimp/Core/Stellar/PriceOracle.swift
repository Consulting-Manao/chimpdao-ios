import Foundation
import stellarsdk

/// Prix en dollars des actifs, pour le total du Wallet. Portage de `usdRates` et `netWorthIn`
/// (`reference/terminal/src/chain/prices.ts`).
protocol PriceOracle: Sendable {
    /// Prix en USD de chaque code demandé. **Un code absent n'a pas pu être lu** : jamais de prix inventé, et
    /// l'appelant n'affiche alors pas de total partiel (il revient aux montants par actif, décision du 2026-09-29).
    func usdPrices(for codes: Set<String>) async -> [String: Decimal]
}

/// Oracles Reflector (SEP-40) sur **mainnet**, en lecture seule : de simples simulations de `lastprice`, avec un compte
/// source construit localement (séquence 0), jamais lu ni utilisé pour envoyer quoi que ce soit.
/// Prix gardés en mémoire 5 minutes (l'échantillonnage des flux) ; un échec n'est jamais gardé.
final class ReflectorPriceOracle: PriceOracle {
    private let config: PriceOracleConfig
    private let server: SorobanServer
    private let now: () -> ContinuousClock.Instant
    private var cache: (at: ContinuousClock.Instant, prices: [String: Decimal])?

    init(config: PriceOracleConfig = .reflector, now: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.config = config
        self.now = now
        let session = URLSession(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = SorobanClient.callTimeout
            return configuration
        }())
        server = SorobanServer(endpoint: config.rpc.absoluteString, urlSession: session)
    }

    func usdPrices(for codes: Set<String>) async -> [String: Decimal] {
        let wanted = Set(codes.map { $0.uppercased() })
        var have = cache.flatMap { now() - $0.at < config.cacheDuration ? $0.prices : nil } ?? [:]
        for code in wanted where config.stableUSD.contains(code) || code == "USD" { have[code] = 1 }
        if wanted.allSatisfy({ have[$0] != nil }) { return have.filter { wanted.contains($0.key) } }

        // `usdRates` : le flux CEX & DEX d'abord, puis le flux FX (codes de devises). Chaque échec donne « pas de prix ».
        await withTaskGroup(of: (String, Decimal?).self) { group in
            for code in wanted where have[code] == nil {
                group.addTask {
                    if let price = try? await self.lastPrice(feed: self.config.cexFeed, code: code) { return (code, price) }
                    return (code, try? await self.lastPrice(feed: self.config.fxFeed, code: code))
                }
            }
            for await (code, price) in group {
                if let price { have[code] = price }
            }
        }
        cache = (now(), have)
        return have.filter { wanted.contains($0.key) }
    }

    /// `lastprice(Asset::Other(code))` sur un flux, en dollars (`nil` : le flux n'a pas de prix pour ce code).
    private func lastPrice(feed: String, code: String) async throws -> Decimal? {
        let source = try Account(accountId: config.simulationSource, sequenceNumber: 0)
        let operation = try InvokeHostFunctionOperation.forInvokingContract(
            contractId: feed, functionName: "lastprice", functionArguments: [Self.assetArgument(code)]
        )
        let deadline = UInt64(Date().timeIntervalSince1970) + SorobanClient.transactionTimeout
        let transaction = try Transaction(
            sourceAccount: source, operations: [operation], memo: Memo.none,
            preconditions: TransactionPreconditions(timeBounds: TimeBounds(minTime: 0, maxTime: deadline))
        )
        switch await server.simulateTransaction(simulateTxRequest: SimulateTransactionRequest(transaction: transaction)) {
        case .success(let response):
            if let error = response.error { throw StellarError.simulationFailed(error) }
            guard let value = response.results?.first?.value else { throw StellarError.noReturnValue("lastprice") }
            return Self.price(from: value, decimals: config.decimals)
        case .failure(let error):
            throw StellarError.rpc(SorobanClient.describe(error))
        }
    }

    /// SEP-40 `Asset::Other(Symbol(code))` : tous les codes des deux flux sont des symboles.
    static func assetArgument(_ code: String) -> SCValXDR {
        .vec([.symbol("Other"), .symbol(code)])
    }

    /// `Option<PriceData { price: i128, timestamp: u64 }>` → prix en dollars. `None`, une forme inattendue ou un prix
    /// nul ou négatif donnent `nil`, comme `lastPrice` du terminal (`price > 0n ? price : null`).
    static func price(from value: SCValXDR, decimals: Int) -> Decimal? {
        guard case .map(let entries) = value,
              let entry = entries?.first(where: { if case .symbol("price") = $0.key { true } else { false } }),
              case .i128(let parts) = entry.val else { return nil }
        let raw = SACClient.decimal(parts)
        guard raw > 0 else { return nil }
        return raw / pow(Decimal(10), decimals)
    }
}

/// `netWorthIn` (`prices.ts`) en dollars : somme **exacte** des avoirs × prix, tronquée au centime.
/// `nil` si un avoir non nul n'a pas de prix : « a total that quietly skips a holding is a lie ».
enum NetWorth {
    static func usd(_ holdings: [(code: String, amount: Decimal)], prices: [String: Decimal]) -> Decimal? {
        var total = Decimal(0)
        for holding in holdings where holding.amount != 0 {
            guard let price = prices[holding.code.uppercased()] else { return nil }
            total += holding.amount * price
        }
        return truncatedToCents(total)
    }

    /// Tronque vers zéro au centime (`fromUnits(…, 2)` du terminal coupe, il n'arrondit pas).
    static func truncatedToCents(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, value < 0 ? .up : .down)
        return result
    }
}
