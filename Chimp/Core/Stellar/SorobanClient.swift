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
    /// Aucun `recovery_id` n'est accepté : le contrat refuse la signature de la carte.
    case signatureRejected(String)

    /// `isStaleFootprint` du terminal : l'écriture réelle a dépassé l'empreinte déclarée (un ledger s'est fermé entre
    /// la simulation et l'envoi). Une nouvelle simulation suffit.
    var isStaleFootprint: Bool {
        switch self {
        case .transactionFailed(_, let detail), .submitFailed(let detail): detail.contains("exceeds amount specified")
        default: false
        }
    }

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
        case .signatureRejected(let detail): "The contract rejected the card's signature: \(detail)"
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

    /// Numéro du dernier ledger fermé (`getLatestLedger`), pour l'expiration des autorisations.
    func latestLedger() async throws -> UInt32 {
        switch await server.getLatestLedger() {
        case .success(let response): return response.sequence
        case .failure(let error): throw StellarError.rpc(Self.describe(error))
        }
    }

    /// Le contrat existe-t-il déjà ? Lit l'entrée « instance » du contrat (`getContractData(address,
    /// scvLedgerKeyContractInstance)` dans `deployAccount`). Écart minimal : le terminal traite **toute** erreur
    /// comme « pas encore déployé » ; ici seule une réponse vide l'est, une panne réseau remonte.
    func isDeployed(_ contract: String) async throws -> Bool {
        let key = LedgerKeyXDR.contractData(LedgerKeyContractDataXDR(
            contract: try SCAddressXDR(contractId: contract),
            key: .ledgerKeyContractInstance,
            durability: .persistent
        ))
        guard let encoded = key.xdrEncoded else { throw StellarError.invalidResponse("could not encode ledger key") }
        switch await server.getLedgerEntries(base64EncodedKeys: [encoded]) {
        case .success(let response): return !response.entries.isEmpty
        case .failure(let error): throw StellarError.rpc(Self.describe(error))
        }
    }

    /// Transaction à une seule opération d'appel de contrat, valable `transactionTimeout` secondes.
    func contractCall(
        source: Account,
        contract: String,
        function: String,
        arguments: [SCValXDR],
        auth: [SorobanAuthorizationEntryXDR] = []
    ) throws -> Transaction {
        let operation = try InvokeHostFunctionOperation.forInvokingContract(
            contractId: contract,
            functionName: function,
            functionArguments: arguments
        )
        operation.auth = auth
        return try singleOperation(source: source, operation: operation)
    }

    /// Transaction à une seule opération, frais de base 100 stroops, valable `transactionTimeout` secondes
    /// (`setTimeout(60)` du terminal).
    func singleOperation(source: Account, operation: InvokeHostFunctionOperation) throws -> Transaction {
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
    /// `authMode` : `nil` = défaut du RPC (`enforce` dès qu'une entrée d'autorisation est jointe, `record` sinon).
    func simulate(_ transaction: Transaction, authMode: String? = nil) async throws -> SimulateTransactionResponse {
        let request = SimulateTransactionRequest(transaction: transaction, authMode: authMode)
        switch await server.simulateTransaction(simulateTxRequest: request) {
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

    /// `refitAuth` : re-simule en mode `enforce` une fois les signatures en place, pour que les ressources couvrent
    /// `__check_auth`, puis recalcule les frais : part classique inchangée + nouveaux frais de ressources.
    func refit(_ transaction: Transaction) async throws {
        let simulation: SimulateTransactionResponse
        do {
            simulation = try await simulate(transaction, authMode: "enforce")
        } catch StellarError.simulationFailed(let detail) {
            throw StellarError.simulationFailed("auth re-sim failed: \(detail)")
        }
        guard let data = simulation.transactionData else {
            throw StellarError.invalidResponse("auth re-sim returned no transaction data")
        }
        var previousResourceFee: Int64 = 0
        if case .sorobanTransactionData(let previous) = transaction.transactionXDR.ext {
            previousResourceFee = previous.resourceFee
        }
        let classicFee = Int64(transaction.fee) - previousResourceFee
        let total = classicFee + data.resourceFee
        guard total >= 0, total <= Int64(UInt32.max) else { throw StellarError.invalidResponse("fee out of range: \(total)") }
        transaction.setSorobanTransactionData(data: data)
        transaction.setFee(fee: UInt32(total))
    }

    /// `refitAndSubmit` : `refit`, frais signés par le serveur de frais, envoi et attente. Une seule nouvelle tentative
    /// si l'empreinte déclarée est devenue trop petite entre la simulation et l'envoi (« exceeds amount specified »).
    /// Renvoie le hash de la transaction.
    func refitAndSubmit(_ transaction: Transaction, feeSigner: FeeSigner) async throws -> String {
        var attempt = 0
        while true {
            try await refit(transaction)
            do {
                let signed = try await feeSigner.signFees(transaction, network: network, passphrase: config.passphrase)
                return try await submitAndWait(signed)
            } catch let error as StellarError where attempt == 0 && error.isStaleFootprint {
                attempt += 1
            }
        }
    }

    /// Pour les transactions sans signature de puce (déploiement d'un compte) : `prepareTransaction` puis envoi
    /// (`sendSoroban` du terminal). Simulation, assemblage, frais signés par le serveur de frais, envoi et attente.
    func prepareAndSubmit(_ transaction: Transaction, feeSigner: FeeSigner) async throws -> String {
        try assemble(transaction, with: try await simulate(transaction))
        let signed = try await feeSigner.signFees(transaction, network: network, passphrase: config.passphrase)
        return try await submitAndWait(signed)
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
            let diagnostics = Self.diagnosticText(sent.diagnosticEvents ?? [])
            let detail = sent.errorResultXdr ?? sent.error?.message ?? sent.status
            throw StellarError.submitFailed(diagnostics.isEmpty ? detail : "\(detail) — \(diagnostics)")
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
                    // Le diagnostic est la seule chose qui dise *pourquoi* (et qui révèle une empreinte trop petite).
                    let events = (response.events?.diagnosticEventsXdr ?? []).compactMap { try? DiagnosticEventXDR(xdr: $0) }
                    let diagnostics = Self.diagnosticText(events)
                    throw StellarError.transactionFailed(hash: hash, detail: diagnostics.isEmpty ? (response.resultXdr ?? "no result") : diagnostics)
                }
            case .failure:
                // Une vérification ratée n'est pas un échec de la transaction : on réessaie jusqu'au délai.
                break
            }
            wait = max(.zero, .seconds(1) - (clock.now - polledAt))
        }
        throw StellarError.notConfirmed(hash: hash)
    }

    /// `diagnosticText` : les données des événements de diagnostic dont un sujet est `error`, lisibles.
    static func diagnosticText(_ events: [DiagnosticEventXDR]) -> String {
        events.compactMap { event -> String? in
            guard case .v0(let body) = event.event.body else { return nil }
            guard body.topics.contains(where: { $0.symbol == "error" }) else { return nil }
            return readable(body.data)
        }.joined(separator: "; ")
    }

    private static func readable(_ value: SCValXDR) -> String {
        switch value {
        case .symbol(let text), .string(let text): return text
        case .vec(let items): return "[" + (items ?? []).map(readable).joined(separator: ", ") + "]"
        case .u32(let number): return String(number)
        case .i32(let number): return String(number)
        case .error(let error): return "\(error)"
        default: return value.xdrEncoded ?? "?"
        }
    }

    static func describe(_ error: SorobanRpcRequestError) -> String {
        switch error {
        case .requestFailed(let message): message
        case .errorResponse(let error): "\(error.code): \(error.message ?? "")"
        case .parsingResponseFailed(let message, _): message
        }
    }
}
