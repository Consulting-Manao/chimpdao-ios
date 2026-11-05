import Foundation
import stellarsdk

/// Prix **indicatif** d'un actif par l'oracle RedStone (SEP-40, mainnet), pour l'affichage uniquement : jamais pour
/// signer, toujours avec sa source et son heure (comme le prix d'Etherfuse). Sert l'USDY d'Ondo, que ni Reflector ni Ondo
/// ne donnent sur Stellar (décision de Barth du 2026-11-05).
///
/// `lastprice(Asset::Stellar(contrat du vrai actif sur le mainnet))` → `Option<PriceData { price: i128, timestamp: u64 }>`,
/// 8 décimales, interface lue sur la chaîne le 2026-11-05. Simulation seulement, avec un compte source construit localement
/// (séquence 0), comme `ReflectorPriceOracle`. Prix gardés 5 minutes ; un échec n'est jamais gardé.
final class RedStonePriceClient: StablebondPricing {
    static let cacheDuration: TimeInterval = 5 * 60

    let config: IntegrationConfig.RedStone
    var now: () -> Date = { Date() }
    private let server: SorobanServer
    private var cache: [String: (at: Date, price: StablebondPrice)] = [:]

    init(config: IntegrationConfig.RedStone) {
        self.config = config
        server = SorobanServer(endpoint: config.rpc.absoluteString, urlSession: SorobanClient.session)
    }

    /// Un lecteur par réseau de l'app, partagé par tous les écrans (son cache aussi).
    static func shared(for config: ChimpNetworkConfig) -> RedStonePriceClient? {
        guard let redstone = config.integrations?.redstone else { return nil }
        if let client = clients[config.network] { return client }
        let client = RedStonePriceClient(config: redstone)
        clients[config.network] = client
        return client
    }

    private static var clients: [StellarNetwork: RedStonePriceClient] = [:]

    func price(of bond: IntegrationConfig.Stablebond) async -> StablebondPriceResult {
        if let cached = cache[bond.code], now().timeIntervalSince(cached.at) < Self.cacheDuration { return .price(cached.price) }
        guard let feed = config.mainnetAssets[bond.code] else { return .unavailable("RedStone has no feed for \(bond.code)") }
        do {
            let value = try await lastPrice(of: feed)
            let result = Self.result(from: value, code: bond.code, decimals: config.decimals, now: now(), maximumAge: config.maximumAge)
            if case .price(let price) = result { cache[bond.code] = (now(), price) }
            return result
        } catch {
            return .unavailable(String(describing: error))
        }
    }

    private func lastPrice(of contract: String) async throws -> SCValXDR {
        let source = try Account(accountId: Self.simulationSource, sequenceNumber: 0)
        let operation = try InvokeHostFunctionOperation.forInvokingContract(
            contractId: config.oracle, functionName: "lastprice", functionArguments: [try Self.assetArgument(contract)]
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
            return value
        case .failure(let error):
            throw StellarError.rpc(SorobanClient.describe(error))
        }
    }

    /// Compte source des simulations (jamais lu, jamais utilisé pour envoyer quoi que ce soit), comme Reflector.
    static let simulationSource = "GAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAWHF"

    /// SEP-40 `Asset::Stellar(Address)`.
    static func assetArgument(_ contract: String) throws -> SCValXDR {
        .vec([.symbol("Stellar"), try ContractArgument.address(contract)])
    }

    /// `Option<PriceData>` → le prix en dollars, ou pourquoi il n'y en a pas : `None`, une forme inattendue, un prix nul
    /// ou négatif, ou un prix plus vieux que `maximumAge` (jamais affiché comme un prix du moment).
    static func result(from value: SCValXDR, code: String, decimals: Int, now: Date, maximumAge: TimeInterval) -> StablebondPriceResult {
        guard let usd = ReflectorPriceOracle.price(from: value, decimals: decimals) else { return .unavailable("RedStone has no price for \(code)") }
        guard case .map(let entries) = value,
              let entry = entries?.first(where: { if case .symbol("timestamp") = $0.key { true } else { false } }),
              case .u64(let seconds) = entry.val else { return .unavailable("RedStone price for \(code) has no timestamp") }
        let asOf = Date(timeIntervalSince1970: TimeInterval(seconds))
        guard now.timeIntervalSince(asOf) <= maximumAge else { return .unavailable("RedStone price for \(code) is stale") }
        return .price(StablebondPrice(code: code, usd: usd, currency: "USD", fiat: usd, asOf: asOf, source: "RedStone"))
    }
}
