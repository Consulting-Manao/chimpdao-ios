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
    /// `sendTransaction` n'a pas répondu (réseau coupé, délai) : la transaction est peut-être arrivée. Comme
    /// `notConfirmed` : **ne pas renvoyer**, vérifier d'abord. Le hash est calculé avant l'envoi.
    case sendUnanswered(hash: String, detail: String)
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
        case .sendUnanswered(let hash, let detail): "Sent, but Stellar didn't answer (\(detail)). Check the receipt before retrying: \(hash)"
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
    func refitAndSubmit(_ transaction: Transaction, feeSigner: FeeSigner, onSent: (() -> Void)? = nil) async throws -> String {
        var attempt = 0
        while true {
            try await refit(transaction)
            do {
                let signed = try await feeSigner.signFees(transaction, network: network, passphrase: config.passphrase)
                return try await submitAndWait(signed, onSent: onSent)
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
    /// `onSent` : appelé dès que le réseau a accepté la transaction, avant l'attente de la confirmation (affichage).
    func submitAndWait(_ transaction: Transaction, onSent: (() -> Void)? = nil) async throws -> String {
        // Hash calculé **avant** l'envoi : si `sendTransaction` ne répond pas, la transaction est peut-être partie,
        // et c'est ce hash qui permettra de vérifier, jamais un renvoi.
        let hash = try transaction.getTransactionHash(network: network)
        let sent: SendTransactionResponse
        switch await server.sendTransaction(transaction: transaction) {
        case .success(let response): sent = response
        case .failure(let error): throw StellarError.sendUnanswered(hash: hash, detail: Self.describe(error))
        }
        if sent.status == SendTransactionResponse.STATUS_ERROR {
            let diagnostics = Self.diagnosticText(sent.diagnosticEvents ?? [])
            let detail = sent.errorResultXdr ?? sent.error?.message ?? sent.status
            throw StellarError.submitFailed(diagnostics.isEmpty ? detail : "\(detail) — \(diagnostics)")
        }
        // Au-delà de ce point, la transaction est acceptée : plus aucune erreur ne doit laisser croire qu'elle n'est pas
        // partie. On suit le hash calculé ici (identique à `transactionId` quand la passphrase est la bonne).
        onSent?()

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

    // MARK: Vérifications après un envoi (« Check again »)

    /// État d'une transaction envoyée, et jusqu'où le RPC a lu la chaîne au moment de la réponse.
    struct TransactionLookup: Equatable {
        enum Status: Equatable {
            case success
            /// Incluse mais échouée : rien n'a bougé (une transaction échoue en bloc).
            case failed(String)
            /// Inconnue du RPC : pas (encore) incluse, ou jamais arrivée.
            case notFound
        }

        let status: Status
        let latestLedger: UInt32
        /// Heure de fermeture de `latestLedger` (secondes depuis 1970, comme les bornes de temps d'une transaction).
        let latestLedgerCloseTime: UInt64
    }

    /// `getTransaction` une fois, sans attendre.
    func lookUpTransaction(_ hash: String) async throws -> TransactionLookup {
        switch await server.getTransaction(transactionHash: hash) {
        case .success(let response):
            guard let closeTime = UInt64(response.latestLedgerCloseTime), response.latestLedger >= 0 else {
                throw StellarError.invalidResponse("getTransaction latest ledger \(response.latestLedger) closed at \(response.latestLedgerCloseTime)")
            }
            let status: TransactionLookup.Status = switch response.status {
            case GetTransactionResponse.STATUS_SUCCESS: .success
            case GetTransactionResponse.STATUS_FAILED: .failed(response.resultXdr ?? "no result")
            default: .notFound
            }
            return TransactionLookup(status: status, latestLedger: UInt32(response.latestLedger), latestLedgerCloseTime: closeTime)
        case .failure(let error):
            throw StellarError.rpc(Self.describe(error))
        }
    }

    /// Enveloppe (base64) d'une transaction incluse, `nil` si le RPC ne la connaît pas.
    func transactionEnvelope(_ hash: String) async throws -> String? {
        switch await server.getTransaction(transactionHash: hash) {
        case .success(let response):
            return response.status == GetTransactionResponse.STATUS_NOT_FOUND ? nil : response.envelopeXdr
        case .failure(let error):
            throw StellarError.rpc(Self.describe(error))
        }
    }

    /// Dernier ledger fermé et son heure de fermeture (secondes depuis 1970).
    func latestLedgerInfo() async throws -> (sequence: UInt32, closeTime: UInt64) {
        switch await server.getLatestLedger() {
        case .success(let response):
            guard let text = response.closeTime, let closeTime = UInt64(text) else {
                throw StellarError.invalidResponse("getLatestLedger returned no close time")
            }
            return (response.sequence, closeTime)
        case .failure(let error):
            throw StellarError.rpc(Self.describe(error))
        }
    }

    /// Résultat d'une recherche d'événements : les transactions qui les ont émis, et la fenêtre que le RPC garde en
    /// mémoire (pour savoir si la recherche a vraiment tout couvert).
    struct EventScan: Equatable {
        let transactionHashes: [String]
        let oldestLedger: UInt32?
        let latestLedger: UInt32
    }

    /// Transactions qui ont émis un événement de `contract` dont les sujets correspondent à `topics` (XDR base64 ou `*`),
    /// des ledgers `startLedger` à `endLedger` inclus (`getEvents`, comme `backfillChainHistory`).
    ///
    /// Le RPC ne parcourt qu'une tranche de ledgers par requête (~10 000 sur testnet) : une page peut revenir **vide avec
    /// un curseur** au milieu de la fenêtre. On suit donc le curseur jusqu'à ce qu'il atteigne `endLedger` ; une page vide
    /// ne veut jamais dire « rien » tant que la fenêtre n'est pas couverte. Vérifié sur testnet le 2026-09-29 : première
    /// requête avec `startLedger` et `endLedger` (exclusif), les suivantes avec le curseur seul (« ledger ranges and cursor
    /// cannot both be set ») ; fenêtre couverte = curseur sur son dernier ledger.
    func eventTransactions(
        contract: String,
        topics: [String],
        startLedger: UInt32,
        endLedger: UInt32
    ) async throws -> EventScan {
        let filter = EventFilter(type: "contract", contractIds: [contract], topics: [TopicFilter(segmentMatchers: topics)])
        let range = try await contractEvents(filters: [filter], startLedger: startLedger, endLedger: endLedger)
        var hashes: [String] = []
        for event in range.events where !hashes.contains(event.transactionHash) {
            hashes.append(event.transactionHash)
        }
        return EventScan(transactionHashes: hashes, oldestLedger: range.oldestLedger, latestLedger: range.latestLedger)
    }

    /// Un événement de contrat tel que le RPC le rend (`getEvents`) : sujets et valeur en XDR base64, non décodés.
    struct ContractEvent: Equatable, Sendable {
        /// Identifiant unique de l'événement (`id` du RPC).
        let id: String
        /// Contrat qui a émis l'événement : fixé par Stellar, impossible à falsifier par un autre contrat.
        let contractID: String
        let ledger: UInt32
        /// Heure de fermeture du ledger (ISO 8601, `ledgerClosedAt`).
        let ledgerClosedAt: String
        let transactionHash: String
        let topics: [String]
        let value: String
    }

    /// Événements trouvés dans une fenêtre de ledgers, et la fenêtre que le RPC garde en mémoire.
    struct EventRange: Equatable, Sendable {
        let events: [ContractEvent]
        let oldestLedger: UInt32?
        let latestLedger: UInt32
    }

    /// Tous les événements qui correspondent à `filters` (5 au plus, chacun avec 5 motifs de sujets au plus), des ledgers
    /// `startLedger` à `endLedger` inclus, dans l'ordre de la chaîne (`getEvents`, comme `backfillChainHistory`).
    /// Même pagination que `eventTransactions` (voir plus haut) : le curseur est suivi jusqu'à couvrir la fenêtre.
    func contractEvents(
        filters: [EventFilter],
        startLedger: UInt32,
        endLedger: UInt32,
        pageLimit: Int = 100
    ) async throws -> EventRange {
        var events: [ContractEvent] = []
        var cursor: String?
        var latest: UInt32 = 0
        var oldest: UInt32?
        for _ in 0..<Self.maxEventPages {
            let response: GetEventsResponse
            switch await server.getEvents(
                startLedger: cursor == nil ? Int(startLedger) : nil,
                endLedger: cursor == nil ? Int(endLedger) + 1 : nil,
                eventFilters: filters,
                paginationOptions: PaginationOptions(cursor: cursor, limit: pageLimit)
            ) {
            case .success(let page): response = page
            case .failure(let error): throw StellarError.rpc(Self.describe(error))
            }
            latest = UInt32(clamping: response.latestLedger)
            oldest = response.oldestLedger.map { UInt32(clamping: $0) }
            // Avec le curseur seul, le RPC peut dépasser la fenêtre : on ne garde que ce qui est dedans.
            for event in response.events where event.ledger <= Int(endLedger) {
                events.append(ContractEvent(
                    id: event.id, contractID: event.contractId, ledger: UInt32(clamping: event.ledger),
                    ledgerClosedAt: event.ledgerClosedAt, transactionHash: event.txHash, topics: event.topic, value: event.value
                ))
            }
            let passedWindow = response.events.contains { $0.ledger > Int(endLedger) }
            guard let next = response.cursor, let reached = Self.cursorLedger(next) else {
                throw StellarError.invalidResponse("getEvents returned no usable cursor")
            }
            if passedWindow || (response.events.count < pageLimit && reached >= endLedger) {
                return EventRange(events: events, oldestLedger: oldest, latestLedger: latest)
            }
            cursor = next
        }
        throw StellarError.invalidResponse("getEvents didn't cover ledgers \(startLedger) to \(endLedger)")
    }

    /// Ledger atteint par un curseur de `getEvents` (« TOID-index » : le TOID porte le numéro de ledger dans ses 32 bits
    /// de poids fort, comme les identifiants d'Horizon).
    static func cursorLedger(_ cursor: String) -> UInt32? {
        guard let toid = cursor.split(separator: "-").first.flatMap({ UInt64($0) }) else { return nil }
        return UInt32(exactly: toid >> 32)
    }

    /// Plafond de requêtes de `eventTransactions` (100 événements ou ~10 000 ledgers chacune).
    static let maxEventPages = 30

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
