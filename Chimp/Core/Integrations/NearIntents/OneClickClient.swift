import Foundation

/// Un jeton que l'API 1Click de NEAR Intents sait échanger (`GET /v0/tokens`).
struct OneClickToken: Equatable, Hashable, Sendable, Decodable, Identifiable {
    let assetId: String
    let decimals: Int
    /// Code de la blockchain (« eth », « base », « sol », « stellar »…).
    let blockchain: String
    let symbol: String

    var id: String { assetId }
}

/// Un devis **à blanc** (`dry: true`) : un prix, rien d'autre. Aucune adresse de dépôt n'est créée, rien ne peut être
/// envoyé. Les quantités viennent de l'API (pas d'un pool) ; jamais converties en dollars.
struct OneClickQuote: Equatable, Sendable {
    let amountIn: Decimal
    /// Ce qui arriverait sur Stellar, d'après le devis.
    let amountOut: Decimal
    /// Le minimum garanti par le devis, à la tolérance demandée.
    let minimumOut: Decimal
    /// Durée estimée, en secondes.
    let timeEstimate: Int
    let quotedAt: Date
}

enum OneClickError: Error, Equatable {
    /// « Quoting for this pair is not available » : pas de prix pour cette paire en ce moment.
    case pairUnavailable
    /// « recipient is not valid » : l'adresse de destination est refusée (une adresse de carte, C…).
    case recipientRefused
    /// Montant trop petit pour un devis.
    case amountTooLow
    case http(Int, String)
    case malformed
}

protocol OneClickQuoting: AnyObject {
    func tokens() async throws -> [OneClickToken]
    func dryQuote(origin: OneClickToken, amountUnits: String, destination: OneClickToken, recipient: String) async throws -> OneClickQuote
}

/// L'API publique 1Click de NEAR Intents (`docs.near-intents.org`), **sans clé** (principe 1 : une API publique sans clé
/// est tolérée pour un devis, jamais pour signer). Tranche 2, D4, voie de repli du grant : **devis seulement**. NEAR
/// Intents n'a pas de testnet (Stellar mainnet seulement) et refuse les adresses de carte (C…, revérifié le 2026-10-15) :
/// l'app ne demande jamais d'adresse de dépôt et ne propose aucun envoi. Absent de `reference/`.
///
/// Devis : `POST /v0/quote` avec `dry: true`, `EXACT_INPUT`, remboursement `INTENTS` (aucun dépôt n'existe, donc rien
/// n'est jamais remboursé ; on évite ainsi de donner l'adresse de quelqu'un d'autre sur la chaîne d'origine).
final class OneClickClient: OneClickQuoting {
    typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let api: URL
    /// Compte de remboursement exigé par l'API pour un devis `INTENTS` ; jamais utilisé (aucun dépôt).
    let refundAccount: String
    var transport: HTTPTransport = { request in try await OneClickClient.session.data(for: request) }
    var now: () -> Date = { Date() }
    /// Tolérance du devis : 1 % (le minimum affiché en découle).
    static let slippageBasisPoints = 100

    private var cachedTokens: (at: Date, tokens: [OneClickToken])?
    static let tokensCacheDuration: TimeInterval = 10 * 60

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    init(api: URL, refundAccount: String) {
        self.api = api
        self.refundAccount = refundAccount
    }

    func tokens() async throws -> [OneClickToken] {
        if let cachedTokens, now().timeIntervalSince(cachedTokens.at) < Self.tokensCacheDuration { return cachedTokens.tokens }
        var request = URLRequest(url: api.appending(path: "v0/tokens"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport(request)
        try Self.check(response, data: data)
        guard let tokens = try? JSONDecoder().decode([OneClickToken].self, from: data) else { throw OneClickError.malformed }
        cachedTokens = (now(), tokens)
        return tokens
    }

    func dryQuote(origin: OneClickToken, amountUnits: String, destination: OneClickToken, recipient: String) async throws -> OneClickQuote {
        var request = URLRequest(url: api.appending(path: "v0/quote"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.body(
            origin: origin, amountUnits: amountUnits, destination: destination, recipient: recipient,
            refundAccount: refundAccount, deadline: now().addingTimeInterval(3600)
        ))
        let (data, response) = try await transport(request)
        try Self.check(response, data: data)
        return try Self.quote(from: data, origin: origin, destination: destination, at: now())
    }

    /// Le corps du devis (testé tel quel) : toujours `dry: true`.
    static func body(
        origin: OneClickToken, amountUnits: String, destination: OneClickToken, recipient: String, refundAccount: String, deadline: Date
    ) -> [String: Any] {
        [
            "dry": true,
            "swapType": "EXACT_INPUT",
            "slippageTolerance": slippageBasisPoints,
            "originAsset": origin.assetId,
            "depositType": "ORIGIN_CHAIN",
            "destinationAsset": destination.assetId,
            "amount": amountUnits,
            "refundTo": refundAccount,
            "refundType": "INTENTS",
            "recipient": recipient,
            "recipientType": "DESTINATION_CHAIN",
            "deadline": ISO8601DateFormatter().string(from: deadline),
        ]
    }

    private struct QuoteResponse: Decodable {
        struct Quote: Decodable {
            let amountInFormatted: String
            let amountOutFormatted: String
            let minAmountOut: String
            let timeEstimate: Int
            let depositAddress: String?
        }
        let quote: Quote
    }

    static func quote(from data: Data, origin: OneClickToken, destination: OneClickToken, at: Date) throws -> OneClickQuote {
        guard let response = try? JSONDecoder().decode(QuoteResponse.self, from: data),
              let amountIn = decimal(response.quote.amountInFormatted),
              let amountOut = decimal(response.quote.amountOutFormatted),
              let minimumUnits = decimal(response.quote.minAmountOut) else { throw OneClickError.malformed }
        // Un devis à blanc n'a jamais d'adresse de dépôt : sinon, on ne s'en sert pas comme d'un devis.
        guard response.quote.depositAddress == nil, amountOut >= 0, amountIn > 0 else { throw OneClickError.malformed }
        var minimum = minimumUnits
        for _ in 0..<destination.decimals { minimum /= 10 }
        return OneClickQuote(amountIn: amountIn, amountOut: amountOut, minimumOut: minimum, timeEstimate: response.quote.timeEstimate, quotedAt: at)
    }

    /// Les refus de l'API, avec un nom quand on le connaît.
    static func check(_ response: URLResponse, data: Data) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard !(200..<300).contains(status) else { return }
        let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? ""
        let lowered = message.lowercased()
        if lowered.contains("pair is not available") { throw OneClickError.pairUnavailable }
        if lowered.contains("recipient is not valid") { throw OneClickError.recipientRefused }
        if lowered.contains("too low") || lowered.contains("too small") { throw OneClickError.amountTooLow }
        throw OneClickError.http(status, message)
    }

    private static func decimal(_ text: String) -> Decimal? {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// Devis factices (catalogue, simulateur, tests).
final class MockOneClick: OneClickQuoting {
    enum Scenario: String, CaseIterable, Identifiable {
        case normal
        case pairUnavailable
        case offline
        var id: String { rawValue }
    }

    var scenario: Scenario
    var delay: Duration
    private(set) var quoteCount = 0

    static let tokens: [OneClickToken] = [
        OneClickToken(assetId: "nep141:eth-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48.omft.near", decimals: 6, blockchain: "eth", symbol: "USDC"),
        OneClickToken(assetId: "nep141:eth.omft.near", decimals: 18, blockchain: "eth", symbol: "ETH"),
        OneClickToken(assetId: "nep141:base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913.omft.near", decimals: 6, blockchain: "base", symbol: "USDC"),
        OneClickToken(assetId: "nep141:sol-5ce3bf3a31af18be40ba30f721101b4341690186.omft.near", decimals: 6, blockchain: "sol", symbol: "USDC"),
        OneClickToken(assetId: "nep141:btc.omft.near", decimals: 8, blockchain: "btc", symbol: "BTC"),
        OneClickToken(assetId: "nep245:v2_1.omni.hot.tg:1100_111bzQBB5v7AhLyPMDwS8uJgQV24KaAPXtwyVWu2KXbbfQU6NXRCz", decimals: 7, blockchain: "stellar", symbol: "XLM"),
        OneClickToken(assetId: "nep245:v2_1.omni.hot.tg:1100_111bzQBB65GxAPAVoxqmMcgYo5oS3txhqs1Uh1cgahKQUeTUq1TJu", decimals: 7, blockchain: "stellar", symbol: "USDC"),
    ]

    init(scenario: Scenario = .normal, delay: Duration = .milliseconds(500)) {
        self.scenario = scenario
        self.delay = delay
    }

    func tokens() async throws -> [OneClickToken] {
        try await Task.sleep(for: delay)
        if scenario == .offline { throw URLError(.notConnectedToInternet) }
        return Self.tokens
    }

    func dryQuote(origin: OneClickToken, amountUnits: String, destination: OneClickToken, recipient: String) async throws -> OneClickQuote {
        quoteCount += 1
        try await Task.sleep(for: delay)
        if scenario == .pairUnavailable { throw OneClickError.pairUnavailable }
        var amount = Decimal(string: amountUnits) ?? 0
        for _ in 0..<origin.decimals { amount /= 10 }
        // 10 USDC → 54,11 XLM (devis réel du 2026-10-15) ; USDC → USDC : 0,25 % de moins.
        let rate: Decimal = destination.symbol == "XLM" ? Decimal(string: "5.411")! : Decimal(string: "0.9975")!
        let out = (amount * rate).truncated(to: 7)
        return OneClickQuote(amountIn: amount, amountOut: out, minimumOut: (out * Decimal(string: "0.99")!).truncated(to: 7), timeEstimate: 50, quotedAt: .now)
    }
}
