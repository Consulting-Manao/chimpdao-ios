import Foundation
import stellarsdk

/// Fait signer les frais d'une transaction par le payeur de frais de ChimpDAO. L'app ne détient aucune clé :
/// elle envoie l'enveloppe au serveur de frais, qui la renvoie signée **sans la soumettre** (ARCHITECTURE §3.3).
/// Implémenté par `WorkerFeeSigner` (le Worker) et `MockFeeSigner` (tests, simulateur).
protocol FeeSigner {
    func signFees(_ transaction: Transaction, network: Network, passphrase: String) async throws -> Transaction
}

enum FeeSignerError: Error, Equatable, LocalizedError {
    /// 5xx : le serveur est en panne ou surchargé. Ce n'est pas un refus de la transaction.
    case unavailable(String?)
    /// 429 deux fois de suite : trop de signatures depuis cette adresse IP.
    case busy
    /// Le serveur a refusé de signer (forme de la transaction : source, opération, frais trop élevés…).
    case refused(String)
    /// Le serveur a renvoyé une autre transaction que celle envoyée.
    case changedTransaction
    /// Réponse illisible.
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): "The fee signer is unavailable right now, try again\(reason.map { " (\($0))" } ?? "")."
        case .busy: "The fee signer is busy, try again in a moment."
        case .refused(let reason): "The fee signer refused to sign: \(reason)"
        case .changedTransaction: "The fee signer returned a different transaction."
        case .invalidResponse(let detail): "Unexpected answer from the fee signer: \(detail)"
        }
    }
}

/// Portage de `signRemotely` (`reference/terminal/src/chain/soroban.ts`) :
/// `POST <url>` avec `{"xdr": <enveloppe base64>, "network": <passphrase>}` → `{"xdr": <enveloppe signée>}`.
/// Un 429 est attendu une fois (délai `retry-after` s'il est > 0, plafonné à 10 s, sinon 5 s), puis signalé :
/// l'onboarding enchaîne deux transactions et le serveur n'accepte qu'une signature toutes les 5 s par adresse IP.
struct WorkerFeeSigner: FeeSigner {
    typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias Sleep = @Sendable (Duration) async throws -> Void

    let url: URL
    var transport: HTTPTransport = { request in try await WorkerFeeSigner.session.data(for: request) }
    var sleep: Sleep = { try await Task.sleep(for: $0) }

    /// Délai par appel (`NET_CALL_MS` = 15 s).
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = SorobanClient.callTimeout
        return URLSession(configuration: configuration)
    }()

    func signFees(_ transaction: Transaction, network: Network, passphrase: String) async throws -> Transaction {
        let body = try JSONSerialization.data(withJSONObject: [
            "xdr": try transaction.encodedEnvelope(),
            "network": passphrase,
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body

        var (data, response) = try await send(request)
        if response.statusCode == 429 {
            try await sleep(Self.retryDelay(retryAfter: response.value(forHTTPHeaderField: "retry-after")))
            (data, response) = try await send(request)
        }

        let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let reason = answer["reason"] as? String
        if response.statusCode >= 500 { throw FeeSignerError.unavailable(reason) }
        if response.statusCode == 429 { throw FeeSignerError.busy }
        guard (200..<300).contains(response.statusCode), let signedXDR = answer["xdr"] as? String else {
            throw FeeSignerError.refused(reason ?? "HTTP \(response.statusCode)")
        }

        let signed: Transaction
        do {
            signed = try Transaction(envelopeXdr: signedXDR)
        } catch {
            throw FeeSignerError.invalidResponse("unreadable envelope")
        }
        // Garde-fou ajouté (absent du terminal) : la transaction signée doit être exactement celle qu'on a envoyée.
        guard try signed.getTransactionHash(network: network) == transaction.getTransactionHash(network: network) else {
            throw FeeSignerError.changedTransaction
        }
        return signed
    }

    /// `retry-after` n'est pris que s'il vaut plus de 0 (plafonné à 10 s) ; absent, nul ou illisible : 5 s.
    static func retryDelay(retryAfter: String?) -> Duration {
        guard let value = retryAfter.flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }), value > 0, value.isFinite else {
            return .seconds(5)
        }
        return .milliseconds(Int(min(value, 10) * 1000))
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { throw FeeSignerError.invalidResponse("not an HTTP response") }
        return (data, http)
    }
}

/// Faux serveur de frais : renvoie la transaction telle quelle (non signée) ou une erreur. Aucune requête réseau.
final class MockFeeSigner: FeeSigner, @unchecked Sendable {
    var failure: FeeSignerError?
    private(set) var signedCount = 0

    init(failure: FeeSignerError? = nil) {
        self.failure = failure
    }

    func signFees(_ transaction: Transaction, network: Network, passphrase: String) async throws -> Transaction {
        if let failure { throw failure }
        signedCount += 1
        return transaction
    }
}
