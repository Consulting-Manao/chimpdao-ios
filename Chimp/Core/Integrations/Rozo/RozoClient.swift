import Foundation

/// Une commande ROZO (`POST /payments`, `GET /payments/{id}`), lue telle que l'API la rend. Les montants arrivent tantôt
/// en texte (« 0.10 »), tantôt en nombre (0.1) : les deux sont lus.
struct RozoOrder: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// En attente de l'USDC sur la chaîne d'origine.
        case unpaid
        /// ROZO a reçu l'USDC, le paiement sur Stellar suit.
        case payinCompleted
        /// Le paiement sur Stellar est parti (vu au premier test réel, le 2026-10-16 ; absent de la documentation).
        case payoutStarted
        /// Payé sur Stellar.
        case completed
        /// Renvoyé (erreur de paiement, liquidité…) : un remboursement passe par le support de ROZO.
        case bounced
        case expired
        case other(String)

        init(_ raw: String) {
            switch raw {
            case "payment_unpaid": self = .unpaid
            case "payment_payin_completed": self = .payinCompleted
            case "payment_payout_started": self = .payoutStarted
            case "payment_completed": self = .completed
            case "payment_bounced": self = .bounced
            case "payment_expired": self = .expired
            default: self = .other(raw)
            }
        }

        /// Plus rien ne changera.
        var isFinal: Bool { self == .completed || self == .bounced || self == .expired }
    }

    let id: String
    let status: Status
    let expiresAt: Date?
    let sourceChainId: String
    let sourceToken: String
    /// Ce qu'il faut envoyer, **exactement** (ROZO peut ajouter un centime pour distinguer deux commandes).
    let sourceAmount: Decimal
    /// Adresse de dépôt de ROZO, sur la chaîne d'origine.
    let depositAddress: String
    let destinationChainId: String
    let destinationAddress: String
    let destinationToken: String
    let destinationAmount: Decimal
    /// Le paiement de ROZO sur Stellar, une fois fait.
    let destinationTxHash: String?
    let errorMessage: String?

    /// Ce qui ne va pas dans cette commande par rapport à ce qu'on a demandé ; vide = elle peut être montrée. Même règle
    /// que `orderProblems` du script `tools/rozo-base-sepolia`. Une commande qui ne passe pas n'est jamais montrée : son
    /// adresse de dépôt pourrait envoyer l'argent ailleurs.
    func problems(recipient: String, requested: Decimal?, config: IntegrationConfig.Rozo) -> [String] {
        var problems: [String] = []
        if id.isEmpty { problems.append("no order id") }
        if destinationChainId != config.stellarChainId { problems.append("pays out on chain \(destinationChainId)") }
        if destinationAddress != recipient { problems.append("pays \(destinationAddress), not \(recipient)") }
        if destinationToken != config.stellarToken { problems.append("pays \(destinationToken)") }
        if sourceChainId != config.sourceChainId { problems.append("takes money on chain \(sourceChainId)") }
        if sourceToken.lowercased() != config.sourceToken.lowercased() { problems.append("takes token \(sourceToken)") }
        if !Self.isEVMAddress(depositAddress) { problems.append("deposit address \(depositAddress) is not an address") }
        if sourceAmount < config.minimumAmount || sourceAmount > config.maximumAmount + Self.maximumBump {
            problems.append("amount \(sourceAmount) is out of bounds")
        }
        if let requested, sourceAmount < requested || sourceAmount > requested + Self.maximumBump {
            problems.append("amount \(sourceAmount) instead of \(requested)")
        }
        if destinationAmount <= 0 || destinationAmount > sourceAmount { problems.append("pays \(destinationAmount) for \(sourceAmount)") }
        return problems
    }

    /// Au-delà de 5 centimes ajoutés au montant demandé, la commande est refusée.
    static let maximumBump: Decimal = Decimal(string: "0.05")!

    static func isEVMAddress(_ text: String) -> Bool {
        text.range(of: "^0x[0-9a-fA-F]{40}$", options: .regularExpression) != nil
    }
}

/// Un devis à blanc (`?dryrun=true`) : rien n'est créé chez ROZO.
struct RozoQuote: Equatable, Sendable {
    let sourceAmount: Decimal
    let destinationAmount: Decimal
    let fee: Decimal
}

enum RozoError: Error, Equatable {
    /// « destination.receiverAddress invalid for chain ».
    case invalidAddress
    case amountTooHigh
    case amountTooLow
    /// La commande rendue ne correspond pas à la demande : rien n'est montré.
    case orderMismatch([String])
    case http(Int, String)
    case malformed
}

protocol RozoPaying: AnyObject {
    func quote(amount: Decimal, recipient: String) async throws -> RozoQuote
    func createOrder(amount: Decimal, recipient: String) async throws -> RozoOrder
    func order(id: String) async throws -> RozoOrder
}

/// L'API publique de paiement de ROZO (`docs.rozo.ai`, « Bridge API »), **sans clé** : un identifiant d'application dans
/// chaque commande. Tranche 2, D4, décision de Barth du 2026-10-16 : ROZO est un **intermédiaire de confiance** ; l'app
/// crée la commande, en vérifie chaque champ, montre l'adresse de dépôt et suit **sa** commande par son identifiant
/// (jamais `/payments/check`, qui montre les commandes des autres). L'app n'envoie rien sur la chaîne d'origine : c'est
/// l'utilisateur, depuis son propre wallet. Absent de `reference/`.
final class RozoClient: RozoPaying {
    typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let config: IntegrationConfig.Rozo
    var transport: HTTPTransport = { request in try await RozoClient.session.data(for: request) }
    var orderReference: () -> String = { "chimpdao-\(UUID().uuidString.prefix(8).lowercased())" }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    init(config: IntegrationConfig.Rozo) {
        self.config = config
    }

    func quote(amount: Decimal, recipient: String) async throws -> RozoQuote {
        let data = try await send(path: "payments", query: "dryrun=true", body: body(amount: amount, recipient: recipient))
        guard let order = try? JSONDecoder().decode(OrderResponse.self, from: data),
              let source = order.source.amount?.value, let destination = order.destination.amount?.value else { throw RozoError.malformed }
        return RozoQuote(sourceAmount: source, destinationAmount: destination, fee: order.fee?.value ?? order.source.fee?.value ?? 0)
    }

    func createOrder(amount: Decimal, recipient: String) async throws -> RozoOrder {
        let order = try Self.order(from: try await send(path: "payments", body: body(amount: amount, recipient: recipient)))
        let problems = order.problems(recipient: recipient, requested: amount, config: config)
        guard problems.isEmpty else { throw RozoError.orderMismatch(problems) }
        return order
    }

    func order(id: String) async throws -> RozoOrder {
        guard id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { throw RozoError.malformed }
        return try Self.order(from: try await send(path: "payments/\(id)", body: nil))
    }

    /// Le corps d'une commande (testé tel quel) : `exactIn`, USDC des deux côtés, montant à deux décimales.
    func body(amount: Decimal, recipient: String) -> [String: Any] {
        [
            "appId": config.appId,
            "orderId": orderReference(),
            "type": "exactIn",
            "display": ["title": "ChimpDAO", "currency": "USD"],
            "source": ["chainId": config.sourceChainId, "tokenSymbol": "USDC", "amount": Self.amountText(amount)],
            "destination": ["chainId": config.stellarChainId, "receiverAddress": recipient, "tokenSymbol": "USDC"],
        ]
    }

    /// « 0.10 », « 1.00 » (point décimal, toujours deux décimales).
    static func amountText(_ amount: Decimal) -> String {
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .down)
        let text = NSDecimalNumber(decimal: rounded).stringValue
        let parts = text.split(separator: ".", maxSplits: 1)
        let fraction = parts.count > 1 ? String(parts[1]) : ""
        return "\(parts[0]).\(fraction.padding(toLength: 2, withPad: "0", startingAt: 0))"
    }

    private func send(path: String, query: String? = nil, body: [String: Any]?) async throws -> Data {
        var components = URLComponents(url: config.api.appending(path: path), resolvingAgainstBaseURL: false)
        components?.query = query
        guard let url = components?.url else { throw RozoError.malformed }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await transport(request)
        try Self.check(response, data: data)
        return data
    }

    /// Les refus de l'API, avec un nom quand on le connaît (`{"error":{"code":…,"message":…}}`).
    static func check(_ response: URLResponse, data: Data) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard !(200..<300).contains(status) else { return }
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let error = object?["error"] as? [String: Any]
        let code = error?["code"] as? String ?? ""
        let message = error?["message"] as? String ?? object?["message"] as? String ?? ""
        switch code {
        case "invalidAddress": throw RozoError.invalidAddress
        case "amountTooHigh": throw RozoError.amountTooHigh
        case "amountTooLow": throw RozoError.amountTooLow
        default: throw RozoError.http(status, code.isEmpty ? message : "\(code): \(message)")
        }
    }

    // MARK: Lecture

    /// Un montant en texte ou en nombre.
    struct FlexibleDecimal: Decodable, Equatable {
        let value: Decimal

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self), let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) {
                self.value = value
            } else if let number = try? container.decode(Double.self), let value = Decimal(string: "\(number)", locale: Locale(identifier: "en_US_POSIX")) {
                self.value = value
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not an amount")
            }
        }
    }

    private struct OrderResponse: Decodable {
        struct Side: Decodable {
            let chainId: String?
            let tokenAddress: String?
            let amount: FlexibleDecimal?
            let receiverAddress: String?
            let fee: FlexibleDecimal?
            let txHash: String?
        }
        let id: String?
        let status: String?
        let expiresAt: String?
        let fee: FlexibleDecimal?
        let errorMessage: String?
        let source: Side
        let destination: Side
    }

    static func order(from data: Data) throws -> RozoOrder {
        guard let response = try? JSONDecoder().decode(OrderResponse.self, from: data),
              let id = response.id, let status = response.status,
              let sourceAmount = response.source.amount?.value, let destinationAmount = response.destination.amount?.value else {
            throw RozoError.malformed
        }
        return RozoOrder(
            id: id, status: RozoOrder.Status(status), expiresAt: response.expiresAt.flatMap { Self.date($0) },
            sourceChainId: response.source.chainId ?? "", sourceToken: response.source.tokenAddress ?? "",
            sourceAmount: sourceAmount, depositAddress: response.source.receiverAddress ?? "",
            destinationChainId: response.destination.chainId ?? "", destinationAddress: response.destination.receiverAddress ?? "",
            destinationToken: response.destination.tokenAddress ?? "", destinationAmount: destinationAmount,
            destinationTxHash: response.destination.txHash, errorMessage: response.errorMessage
        )
    }

    /// « 2026-10-16T07:29:54.93+00:00 » (fractions de seconde de longueur variable, ou absentes).
    static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        guard let seconds = formatter.date(from: trimmed) else { return nil }
        guard let fraction = text.range(of: #"\.\d+"#, options: .regularExpression).flatMap({ Double("0" + text[$0]) }) else { return seconds }
        return seconds.addingTimeInterval(fraction)
    }
}

/// Commandes factices (catalogue, simulateur, tests) : la commande avance d'un état à chaque lecture.
final class MockRozo: RozoPaying {
    enum Scenario: String, CaseIterable, Identifiable {
        case normal
        case bounced
        case expired
        case offline
        /// ROZO rend une commande vers un autre destinataire : refusée.
        case mismatch
        var id: String { rawValue }
    }

    var scenario: Scenario
    var delay: Duration
    var now: () -> Date = { .now }
    private(set) var reads = 0
    private var created: RozoOrder?

    static let depositAddress = "0x4843B70de3Aa77CFbfDA0BAf468e3C4f32B1FA34"

    init(scenario: Scenario = .normal, delay: Duration = .milliseconds(400)) {
        self.scenario = scenario
        self.delay = delay
    }

    func quote(amount: Decimal, recipient: String) async throws -> RozoQuote {
        try await Task.sleep(for: delay)
        if scenario == .offline { throw URLError(.notConnectedToInternet) }
        if amount > 1 { throw RozoError.amountTooHigh }
        return RozoQuote(sourceAmount: amount, destinationAmount: amount, fee: 0)
    }

    func createOrder(amount: Decimal, recipient: String) async throws -> RozoOrder {
        try await Task.sleep(for: delay)
        if scenario == .offline { throw URLError(.notConnectedToInternet) }
        if scenario == .mismatch { throw RozoError.orderMismatch(["pays CCDO6J7W…, not \(recipient)"]) }
        let order = Self.order(status: .unpaid, amount: amount + Decimal(string: "0.01")!, recipient: recipient, expiresAt: now().addingTimeInterval(600))
        created = order
        reads = 0
        return order
    }

    func order(id: String) async throws -> RozoOrder {
        try await Task.sleep(for: delay)
        guard let created, created.id == id else { throw RozoError.http(404, "not found") }
        reads += 1
        let status: RozoOrder.Status = switch (scenario, reads) {
        case (_, ..<3): .unpaid
        case (.expired, _): .expired
        case (_, 3): .payinCompleted
        case (.bounced, _): .bounced
        default: .completed
        }
        return Self.order(status: status, amount: created.sourceAmount, recipient: created.destinationAddress, expiresAt: created.expiresAt)
    }

    static func order(status: RozoOrder.Status, amount: Decimal, recipient: String, expiresAt: Date?) -> RozoOrder {
        let config = IntegrationConfig.testnet.rozo
        return RozoOrder(
            id: "pay_mockOrder1", status: status, expiresAt: expiresAt, sourceChainId: config.sourceChainId,
            sourceToken: config.sourceToken, sourceAmount: amount, depositAddress: depositAddress,
            destinationChainId: config.stellarChainId, destinationAddress: recipient, destinationToken: config.stellarToken,
            destinationAmount: amount, destinationTxHash: status == .completed ? "e7eedc04fb5605550a0e5c8c98ad310fe26f93b3bee5c6bf65af24d6477c4572" : nil,
            errorMessage: status == .bounced ? "insufficientLiquidity" : nil
        )
    }
}
