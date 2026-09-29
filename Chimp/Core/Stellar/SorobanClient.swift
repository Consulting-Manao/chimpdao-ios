import Foundation
import stellarsdk

/// Erreurs réseau Stellar. Toutes remontent à l'écran avec leur texte d'origine.
enum StellarError: Error, Equatable {
    /// Le serveur RPC n'a pas répondu correctement.
    case rpc(String)
    /// La simulation a échoué ; le texte est celui du RPC (contient par exemple `Error(Contract, #200)`).
    case simulationFailed(String)
    /// Une lecture qui doit répondre n'a rendu aucune valeur (`simulateValue` du terminal).
    case noReturnValue(String)
    /// L'envoi a été refusé (`sendTransaction` en `ERROR`).
    case submitFailed(String)
    /// La transaction est incluse mais a échoué.
    case transactionFailed(hash: String, detail: String)
    /// Envoyée, mais pas confirmée dans le délai : **ne pas renvoyer**, vérifier d'abord dans l'explorateur.
    case notConfirmed(hash: String)
    /// Réponse inattendue.
    case invalidResponse(String)

    /// `isContractTrap` du terminal (`lib/errors.ts`) : le contrat a refusé, par opposition à une panne réseau.
    var isContractTrap: Bool {
        guard case .simulationFailed(let message) = self else { return false }
        return message.range(
            of: #"Error\(Contract, #\d+\)|HostError|MissingValue|UnreachableCodeReached"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}

extension StellarError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .rpc(let detail): "Stellar RPC error: \(detail)"
        case .simulationFailed(let detail): "Simulation failed: \(detail)"
        case .noReturnValue(let what): "\(what) returned no value."
        case .submitFailed(let detail): "Submission refused: \(detail)"
        case .transactionFailed(let hash, let detail): "Transaction failed (\(hash)): \(detail)"
        case .notConfirmed(let hash): "Sent, but the network did not confirm it in time. Check the receipt before retrying: \(hash)"
        case .invalidResponse(let detail): "Unexpected answer from Stellar: \(detail)"
        }
    }
}

/// Client Soroban minimal : construire, simuler, assembler, envoyer et attendre une transaction.
/// Portage de `reference/terminal/src/chain/soroban.ts` (`builderFor`, `simulateOutcome`, `simulateValue`,
/// `submit`) et de l'assemblage de `prepareTransaction` du SDK JS (`assembleTransaction`).
struct SorobanClient {
    let config: ChimpNetworkConfig
    private let server: SorobanServer

    /// Délai par appel RPC (`NET_CALL_MS` = 15 s) et délai total d'attente de confirmation (`NET_TOTAL_MS` = 60 s).
    static let callTimeout: TimeInterval = 15
    static let confirmationBudget: Duration = .seconds(60)
    /// Durée de validité d'une transaction construite (`TX_TIMEOUT_S` = 60 s dans `chain/env.ts`).
    static let transactionTimeout: UInt64 = 60

    init(config: ChimpNetworkConfig) {
        self.config = config
        let session = URLSession(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = Self.callTimeout
            return configuration
        }())
        server = SorobanServer(endpoint: config.endpoints.rpc.absoluteString, urlSession: session)
    }

    var network: Network { .custom(passphrase: config.passphrase) }

    // MARK: Construction

    /// Compte source avec son numéro de séquence à jour (`builderFor` : un `getAccount` neuf par transaction).
    func account(_ accountID: String) async throws -> Account {
        switch await server.getAccount(accountId: accountID) {
        case .success(let account): return account
        case .failure(let error): throw StellarError.rpc(Self.describe(error))
        }
    }

    /// Transaction à une seule opération d'appel de contrat, valable `transactionTimeout` secondes.
    func contractCall(source: Account, contract: String, function: String, arguments: [SCValXDR]) throws -> Transaction {
        let operation = try InvokeHostFunctionOperation.forInvokingContract(
            contractId: contract,
            functionName: function,
            functionArguments: arguments
        )
        let now = UInt64(Date().timeIntervalSince1970)
        return try Transaction(
            sourceAccount: source,
            operations: [operation],
            memo: Memo.none,
            preconditions: TransactionPreconditions(timeBounds: TimeBounds(minTime: 0, maxTime: now + Self.transactionTimeout))
        )
    }

    // MARK: Simulation

    /// Simule ; lève `simulationFailed` avec le texte du RPC si l'appel échoue (`simulateOutcome`).
    func simulate(_ transaction: Transaction) async throws -> SimulateTransactionResponse {
        switch await server.simulateTransaction(simulateTxRequest: SimulateTransactionRequest(transaction: transaction)) {
        case .success(let response):
            if let error = response.error { throw StellarError.simulationFailed(error) }
            return response
        case .failure(let error):
            throw StellarError.rpc(Self.describe(error))
        }
    }

    /// Lecture seule : simule un appel et renvoie sa valeur, `nil` si la simulation n'a rendu aucune valeur.
    func read(source: Account, contract: String, function: String, arguments: [SCValXDR] = []) async throws -> SCValXDR? {
        // Une copie du compte : `Transaction` incrémente la séquence du compte qu'on lui donne.
        let copy = try Account(accountId: source.accountId, sequenceNumber: source.sequenceNumber)
        let response = try await simulate(try contractCall(source: copy, contract: contract, function: function, arguments: arguments))
        return response.results?.first?.value
    }

    /// Lecture qui doit répondre (`simulateValue`) : l'absence de valeur est une erreur, jamais « rien ».
    func readValue(source: Account, contract: String, function: String, arguments: [SCValXDR] = []) async throws -> SCValXDR {
        guard let value = try await read(source: source, contract: contract, function: function, arguments: arguments) else {
            throw StellarError.noReturnValue(function)
        }
        return value
    }

    // MARK: Assemblage et envoi

    /// `assembleTransaction` du SDK JS : données Soroban de la simulation, frais = frais de base + `minResourceFee`,
    /// et entrées d'autorisation de la simulation seulement si l'opération n'en porte pas déjà.
    func assemble(_ transaction: Transaction, with simulation: SimulateTransactionResponse) throws {
        guard let data = simulation.transactionData, let resourceFee = simulation.minResourceFee else {
            throw StellarError.invalidResponse("simulation returned no transaction data")
        }
        transaction.setSorobanTransactionData(data: data)
        transaction.addResourceFee(resourceFee: resourceFee)
        let existingAuth = (transaction.operations.first as? InvokeHostFunctionOperation)?.auth ?? []
        if existingAuth.isEmpty {
            transaction.setSorobanAuth(auth: simulation.sorobanAuth)
        }
    }

    /// Envoie une transaction déjà signée et attend son résultat (`submit` : 1ʳᵉ vérification à ~3 s,
    /// puis toutes les ~1 s, dans un budget total de 60 s). Renvoie le hash.
    func submitAndWait(_ transaction: Transaction) async throws -> String {
        let sent: SendTransactionResponse
        switch await server.sendTransaction(transaction: transaction) {
        case .success(let response): sent = response
        case .failure(let error): throw StellarError.rpc(Self.describe(error))
        }
        if sent.status == SendTransactionResponse.STATUS_ERROR {
            throw StellarError.submitFailed(sent.errorResultXdr ?? sent.error?.message ?? sent.status)
        }
        let hash = sent.transactionId

        let clock = ContinuousClock()
        let deadline = clock.now + Self.confirmationBudget
        var wait: Duration = .seconds(3)
        while clock.now < deadline {
            try await Task.sleep(for: wait)
            let polledAt = clock.now
            switch await server.getTransaction(transactionHash: hash) {
            case .success(let response):
                if response.status == GetTransactionResponse.STATUS_SUCCESS { return hash }
                if response.status == GetTransactionResponse.STATUS_FAILED {
                    throw StellarError.transactionFailed(hash: hash, detail: response.resultXdr ?? "no result")
                }
            case .failure:
                // Une vérification ratée n'est pas un échec de la transaction : on réessaie jusqu'au délai.
                break
            }
            wait = max(.zero, .seconds(1) - (clock.now - polledAt))
        }
        throw StellarError.notConfirmed(hash: hash)
    }

    static func describe(_ error: SorobanRpcRequestError) -> String {
        switch error {
        case .requestFailed(let message): message
        case .errorResponse(let error): "\(error.code): \(error.message ?? "")"
        case .parsingResponseFailed(let message, _): message
        }
    }
}
