import Foundation

/// Prix **indicatif** d'un stablebond d'Etherfuse (tranche 2, D3), pour l'affichage uniquement : jamais pour signer,
/// jamais tiré d'un pool, toujours avec sa source et son heure (décisions de Barth du 2026-10-14 et du 2026-10-15).
/// Absent du terminal : écrit d'après la spécification publique d'Etherfuse (`docs.etherfuse.com/openapi-v2.json`).
struct StablebondPrice: Equatable, Sendable {
    /// « CETES ».
    let code: String
    /// Prix d'un jeton en dollars, d'après Etherfuse (`token_cost_in_usd`).
    let usd: Decimal
    /// Devise du titre (« MXN ») et prix d'un jeton dans cette devise.
    let currency: String
    let fiat: Decimal
    /// Heure de la **plus ancienne** source retenue : l'âge honnête du prix affiché.
    let asOf: Date
    /// Toujours « Etherfuse » : l'écran dit d'où vient le prix.
    var source: String { "Etherfuse" }

    /// Valeur indicative d'une quantité, en dollars.
    func value(of amount: Decimal) -> Decimal { amount * usd }
}

/// Le prix, ou pourquoi il n'y en a pas : sans prix, l'écran montre la quantité seule.
enum StablebondPriceResult: Equatable, Sendable {
    case price(StablebondPrice)
    /// Détail technique (pour le support), jamais montré comme un prix.
    case unavailable(String)

    var price: StablebondPrice? {
        if case .price(let price) = self { return price }
        return nil
    }
}

/// Source du prix indicatif d'un stablebond. Une implémentation factice sert l'UI sans réseau (`MockStablebondPricing`).
protocol StablebondPricing: AnyObject {
    func price(of bond: IntegrationConfig.Stablebond) async -> StablebondPriceResult
}

enum EtherfusePriceError: Error, Equatable {
    case http(Int)
    case malformed(String)
    /// La réponse ne parle pas de ce jeton (autre symbole, autre émetteur, autre mint).
    case notThisBond(String)
    /// Aucune source assez récente.
    case stale
    /// Les sources ne s'accordent pas (plus de 1 % d'écart) : aucun prix plutôt qu'un prix douteux.
    case sourcesDisagree
}

/// L'API publique d'Etherfuse, **sans clé** (« Public. No API key required. ») :
///
/// 1. `GET /lookup/stablebond/{CODE}-{émetteur}` : le titre qui porte **exactement** ce jeton Stellar (symbole, ligne
///    `stellar` avec `tokenIdentifier == CODE-émetteur`) et son adresse Solana, qui sert d'identifiant. Jamais le code
///    seul : il existe d'autres « CETES ». Gardé en mémoire (ne change pas).
/// 2. `GET /lookup/tokens/cost/{mint}?max_age=900` : le prix en dollars et en pesos, et le prix de chaque source de
///    change (« so you can run your own oracle-safety checks ») : toutes doivent s'accorder à 1 % près.
///
/// Testnet : la sandbox (`api.sand.etherfuse.com`), la seule qui connaît l'émetteur sandbox. Prix gardé 5 minutes (la
/// réponse d'Etherfuse est elle-même en cache ~5 minutes) ; un échec n'est jamais gardé.
final class EtherfusePriceClient: StablebondPricing {
    typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let api: URL
    let issuer: String
    var transport: HTTPTransport = { request in try await EtherfusePriceClient.session.data(for: request) }
    var now: () -> Date = { Date() }

    static let cacheDuration: TimeInterval = 5 * 60
    /// Âge maximal d'une source retenue (`max_age`, en secondes).
    static let maxSourceAge = 15 * 60
    /// Écart maximal entre une source et le prix rendu : 1 %.
    static let maxSpreadBasisPoints: Decimal = 100

    private var mints: [String: String] = [:]
    private var cache: [String: (at: Date, price: StablebondPrice)] = [:]

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }()

    init(api: URL, issuer: String) {
        self.api = api
        self.issuer = issuer
    }

    convenience init?(config: ChimpNetworkConfig) {
        guard let etherfuse = config.integrations?.etherfuse else { return nil }
        self.init(api: etherfuse.priceAPI, issuer: etherfuse.issuer)
    }

    func price(of bond: IntegrationConfig.Stablebond) async -> StablebondPriceResult {
        if let cached = cache[bond.code], now().timeIntervalSince(cached.at) < Self.cacheDuration { return .price(cached.price) }
        do {
            let mint: String
            if let known = mints[bond.code] {
                mint = known
            } else {
                mint = try Self.mint(from: try await get(api.appending(path: "lookup/stablebond/\(bond.code)-\(issuer)")), code: bond.code, issuer: issuer)
                mints[bond.code] = mint
            }
            var url = api.appending(path: "lookup/tokens/cost/\(mint)")
            url.append(queryItems: [URLQueryItem(name: "max_age", value: String(Self.maxSourceAge))])
            let price = try Self.price(from: try await get(url), code: bond.code, mint: mint, now: now())
            cache[bond.code] = (now(), price)
            return .price(price)
        } catch {
            return .unavailable(String(describing: error))
        }
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw EtherfusePriceError.http(status) }
        return data
    }

    // MARK: Lecture des réponses

    private struct BondLookup: Decodable {
        struct Chain: Decodable {
            let blockchain: String
            let tokenIdentifier: String
        }
        let symbol: String
        let blockchains: [Chain]
        let solanaMintAddress: String
    }

    private struct TokenCost: Decodable {
        struct Source: Decodable {
            let token_cost_in_usd: String
            let updated_at: Double
        }
        let token_symbol: String
        let token_mint: String
        let currency: String
        let token_cost_in_fiat: String
        let token_cost_in_usd: String
        let sources: [String: Source]
    }

    /// L'adresse Solana du titre qui porte exactement `CODE-émetteur` sur Stellar.
    static func mint(from data: Data, code: String, issuer: String) throws -> String {
        let bond: BondLookup
        do { bond = try JSONDecoder().decode(BondLookup.self, from: data) } catch { throw EtherfusePriceError.malformed("stablebond") }
        guard bond.symbol.uppercased() == code.uppercased() else { throw EtherfusePriceError.notThisBond("symbol \(bond.symbol)") }
        let stellar = "\(code)-\(issuer)"
        guard bond.blockchains.contains(where: { $0.blockchain == "stellar" && $0.tokenIdentifier == stellar }) else {
            throw EtherfusePriceError.notThisBond("no stellar \(stellar)")
        }
        guard !bond.solanaMintAddress.isEmpty else { throw EtherfusePriceError.malformed("no mint") }
        return bond.solanaMintAddress
    }

    /// Le prix, vérifié : même jeton, prix positif, sources assez récentes et d'accord entre elles.
    static func price(from data: Data, code: String, mint: String, now: Date) throws -> StablebondPrice {
        let cost: TokenCost
        do { cost = try JSONDecoder().decode(TokenCost.self, from: data) } catch { throw EtherfusePriceError.malformed("tokens/cost") }
        guard cost.token_mint == mint, cost.token_symbol.uppercased() == code.uppercased() else {
            throw EtherfusePriceError.notThisBond("cost for \(cost.token_symbol)")
        }
        guard let usd = decimal(cost.token_cost_in_usd), usd > 0, let fiat = decimal(cost.token_cost_in_fiat), fiat > 0 else {
            throw EtherfusePriceError.malformed("cost")
        }
        let oldest = now.addingTimeInterval(-Double(maxSourceAge))
        let sources = cost.sources.values.filter { Date(timeIntervalSince1970: $0.updated_at) >= oldest }
        guard !sources.isEmpty else { throw EtherfusePriceError.stale }
        for source in sources {
            guard let value = decimal(source.token_cost_in_usd), value > 0 else { throw EtherfusePriceError.malformed("source") }
            if abs(value - usd) * 10_000 / usd > maxSpreadBasisPoints { throw EtherfusePriceError.sourcesDisagree }
        }
        let asOf = sources.map { Date(timeIntervalSince1970: $0.updated_at) }.min() ?? now
        return StablebondPrice(code: code, usd: usd, currency: cost.currency, fiat: fiat, asOf: asOf)
    }

    private static func decimal(_ text: String) -> Decimal? {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// Prix factice (UI sans réseau, catalogue, tests).
final class MockStablebondPricing: StablebondPricing {
    var result: StablebondPriceResult
    private(set) var calls = 0

    init(result: StablebondPriceResult) {
        self.result = result
    }

    func price(of bond: IntegrationConfig.Stablebond) async -> StablebondPriceResult {
        calls += 1
        return result
    }
}
