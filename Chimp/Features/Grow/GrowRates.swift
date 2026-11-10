import Foundation
import SwiftUI

/// Les taux annuels du moment, pour l'affichage seulement (demande de Barth du 2026-11-10 : ceux du testnet) : jamais un
/// taux promis, jamais pour signer. Un protocole sans source n'affiche rien.
protocol GrowRateReading: Sendable {
    /// Le taux par protocole, en fraction (0,0115 = 1,15 % par an) ; absent s'il est inconnu.
    func rates() async -> [ChimpPotProtocol: Decimal]
}

/// Le taux de dépôt du marché XOXNO proposé par l'app, lu dans l'API publique de XOXNO (sans clé) :
/// `GET /stellar-lending/v1/assets`, champ `supplyApy` (fraction ; `docs/stellar-lending/dev/integrator-api`).
struct XoxnoRateClient: GrowRateReading {
    typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let api: URL
    let hubID: UInt32
    /// Le SAC de l'actif du marché.
    let asset: String
    var transport: HTTPTransport = { request in try await XoxnoRateClient.session.data(for: request) }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }()

    /// Au-delà de 1000 % par an, le chiffre est tenu pour faux.
    static let maximumRate: Decimal = 10

    private struct Market: Decodable {
        // Facultatifs : une ligne sans actif simple (jeton de liquidité…) ne doit pas faire échouer toute la réponse.
        let hubId: UInt32?
        let sac: String?
        let supplyApy: Decimal?
        let dataStatus: String?
    }

    init(api: URL, hubID: UInt32, asset: String) {
        self.api = api
        self.hubID = hubID
        self.asset = asset
    }

    init?(config: ChimpNetworkConfig) {
        guard config.features.grow, let xoxno = config.integrations?.xoxno, let api = xoxno.ratesAPI,
              let usdc = try? SACClient.stellarAssets(config: config).first(where: { $0.code == xoxno.assetCode })?.contract else { return nil }
        self.init(api: api, hubID: xoxno.hubID, asset: usdc)
    }

    func rates() async -> [ChimpPotProtocol: Decimal] {
        var request = URLRequest(url: api.appending(path: "stellar-lending/v1/assets"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await transport(request), (response as? HTTPURLResponse)?.statusCode == 200,
              let rate = Self.rate(from: data, hubID: hubID, asset: asset) else { return [:] }
        return [.xoxno: rate]
    }

    /// Le taux du bon marché (même hub, même actif, données à jour), `nil` s'il manque ou n'est pas plausible.
    static func rate(from data: Data, hubID: UInt32, asset: String) -> Decimal? {
        guard let markets = try? JSONDecoder().decode([Market].self, from: data),
              let market = markets.first(where: { $0.hubId == hubID && $0.sac == asset }), market.dataStatus == "ready",
              let rate = market.supplyApy, rate >= 0, rate <= maximumRate else { return nil }
        return rate
    }
}

/// Taux factices (catalogue, simulateur).
struct MockGrowRates: GrowRateReading {
    var values: [ChimpPotProtocol: Decimal] = [.xoxno: Decimal(string: "0.0115")!]
    func rates() async -> [ChimpPotProtocol: Decimal] { values }
}

extension EnvironmentValues {
    /// Les taux lus par Grow, pour les écrans poussés depuis lui (montant d'un dépôt, page d'un pot).
    @Entry var chimpPotRates: [ChimpPotProtocol: Decimal] = [:]
}

extension GrowView {
    /// « ~1.1% a year » ; « ~0% a year ».
    static func rateText(_ fraction: Decimal, locale: Locale) -> String {
        let percent = NSDecimalNumber(decimal: fraction * 100).doubleValue
        let number = percent.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return String(localized: "~\(number)% a year")
    }

    /// « Grows USDC · ~1.1% a year » ; le texte seul sans taux connu.
    static func withRate(_ text: String, rate: Decimal?, locale: Locale) -> String {
        rate.map { "\(text) · \(rateText($0, locale: locale))" } ?? text
    }
}
