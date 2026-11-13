import CoreNFC
import Foundation

/// Ce dont les mises à jour du code (Réglages › Updates) ont besoin sur la chaîne. `ChainUpdatesService` (testnet,
/// `FleetClient` et `ContractUpdateClient` de `Core/`) dans l'app ; `MockUpdatesService` pour le simulateur et les tests.
protocol UpdatesService {
    /// La flotte du factory et le code que font tourner ces contrats (un seul `getLedgerEntries`).
    func read(addresses: [String]) async throws -> (fleet: Fleet, executables: [String: ContractExecutable])
    /// Relu sur la chaîne juste avant la vérification : déjà à jour (rien à signer), ou à faire.
    func check(_ target: UpdateTarget) async throws -> UpdateRun.Preflight
    /// Route lue sur la chaîne et autorisation préparée, avant le tap.
    func prepare(_ target: UpdateTarget, acceptedKeys: [ChipPublicKey]) async throws -> PreparedUpdate
    /// L'autorisation préparée expire-t-elle bientôt ? Alors on la prépare de nouveau avant le tap.
    func needsRefresh(_ prepared: PreparedUpdate) async throws -> Bool
    /// Envoi, puis relecture du contrat.
    func send(_ prepared: PreparedUpdate, signed: CardSignatures) async throws -> UpdateOutcome
}

/// Branché sur `Core/` : lectures et simulations sur le réseau de la session, envoi **uniquement** via le serveur de frais.
struct ChainUpdatesService: UpdatesService {
    let config: ChimpNetworkConfig
    let feeSigner: FeeSigner

    init(config: ChimpNetworkConfig, feeSigner: FeeSigner? = nil) {
        self.config = config
        self.feeSigner = feeSigner ?? WorkerFeeSigner(url: config.feeSignerURL)
    }

    private var client: SorobanClient { SorobanClient(config: config) }
    private var updates: ContractUpdateClient { ContractUpdateClient(client: client, config: config) }

    func read(addresses: [String]) async throws -> (fleet: Fleet, executables: [String: ContractExecutable]) {
        let client = client
        let fleetReader = ChainFleetReader(reader: SimulationReader(client: client, source: config.feePayer), factory: config.contracts.factory)
        async let fleet = FleetClient.readFleet(fleetReader, bundledAccount: config.contracts.accountWasmHash)
        async let executables = FleetClient.readExecutables(addresses, reader: SorobanLedgerEntryReader(client: client))
        return try await (fleet, executables)
    }

    func check(_ target: UpdateTarget) async throws -> UpdateRun.Preflight {
        try await updates.check(target)
    }

    func prepare(_ target: UpdateTarget, acceptedKeys: [ChipPublicKey]) async throws -> PreparedUpdate {
        try await updates.prepare(target, acceptedKeys: acceptedKeys)
    }

    func needsRefresh(_ prepared: PreparedUpdate) async throws -> Bool {
        SorobanAuth.needsRefresh(expirationLedger: prepared.call.expirationLedger, currentLedger: try await client.latestLedger())
    }

    func send(_ prepared: PreparedUpdate, signed: CardSignatures) async throws -> UpdateOutcome {
        try await updates.send(prepared, signed: signed, feeSigner: feeSigner)
    }
}

/// Fausse chaîne : le compte et les wallets « changent de code » comme sur la chaîne, rien ne part. Réglable pour chaque
/// cas d'erreur.
final class MockUpdatesService: UpdatesService, @unchecked Sendable {
    enum Scenario: String, CaseIterable, Identifiable {
        /// Le Main account a une mise à jour, tout passe.
        case accountUpdate
        /// Tout est à jour.
        case upToDate
        /// Le Main account et une carte `Manual` ont une mise à jour.
        case accountAndCard
        /// Stellar injoignable pendant la lecture.
        case networkWhileReading
        /// Déjà fait depuis un autre téléphone : rien à signer.
        case alreadyDone
        /// Le code de la nouvelle version n'est pas sur le réseau.
        case wasmMissing
        /// Envoyée, mais le compte ne fait pas encore tourner la version.
        case notConfirmedYet

        var id: String { rawValue }
    }

    static let oldHash = String(repeating: "04", count: 32)
    static let headHash = String(repeating: "8c", count: 32)
    static let fleetFactory = "CDWPHF7DRJ37GLFZGQDSO6RTX4QR75WTNKJUMFJRETQLIOAHFBU6RGYR"

    let scenario: Scenario
    let delay: Duration
    /// Code de chaque contrat, comme sur la chaîne.
    private(set) var code: [String: ContractExecutable] = [:]
    /// Wallets de cartes `Manual` (les autres suivent la flotte).
    private let manualPockets: Set<String>
    private(set) var sendCount = 0

    init(scenario: Scenario = .accountUpdate, manualPockets: Set<String> = [], delay: Duration = .milliseconds(500)) {
        self.scenario = scenario
        self.delay = delay
        self.manualPockets = manualPockets
    }

    private var fleet: Fleet {
        Fleet(
            epoch: 9,
            pocket: FleetTarget(head: Self.headHash, history: [Self.oldHash, Self.headHash], legacy: false),
            account: FleetTarget(head: Self.headHash, history: [Self.oldHash, Self.headHash], legacy: false)
        )
    }

    private func current(_ address: String) -> ContractExecutable {
        if let known = code[address] { return known }
        if address.hasPrefix("C"), manualPockets.contains(address) {
            return .wasm(hash: scenario == .accountAndCard ? Self.oldHash : Self.headHash)
        }
        return .wasm(hash: scenario == .upToDate ? Self.headHash : Self.oldHash)
    }

    func read(addresses: [String]) async throws -> (fleet: Fleet, executables: [String: ContractExecutable]) {
        try await Task.sleep(for: delay)
        if scenario == .networkWhileReading { throw StellarError.rpc("The request timed out.") }
        var out: [String: ContractExecutable] = [:]
        for address in addresses {
            // Les wallets des cartes enregistrées par l'app suivent la flotte, sauf ceux déclarés `Manual`.
            out[address] = code[address] ?? (manualPockets.contains(address) || addresses.first == address
                ? current(address) : .fleet(owner: Self.fleetFactory, tag: "pocket"))
        }
        return (fleet, out)
    }

    func check(_ target: UpdateTarget) async throws -> UpdateRun.Preflight {
        try await Task.sleep(for: delay)
        switch scenario {
        case .alreadyDone:
            code[target.address] = .wasm(hash: Self.headHash)
            return .current
        case .wasmMissing:
            throw UpdateError.wasmMissing(hash: target.wasmHash)
        default:
            return UpdateRun.runs(current(target.address), target.wasmHash) ? .current : .needed
        }
    }

    func prepare(_ target: UpdateTarget, acceptedKeys: [ChipPublicKey]) async throws -> PreparedUpdate {
        try await Task.sleep(for: delay)
        let route: PreparedUpdate.Route = target.kind == .pocket ? .pocketUpgrade : .accountHop
        let (root, legs) = try ContractUpdateClient.calls(
            for: route, target: target, factory: Self.fleetFactory, router: ChimpNetworkConfig.testnet.contracts.router
        )
        let authorizer: CallAuthorizer = target.kind == .pocket ? .pocket(target.address) : .account(target.address)
        let invocation = try IntegrationCallClient.declaredInvocation(
            call: root, legs: legs, authorizer: authorizer,
            shape: CardLifecycleShape(pocket: target.kind == .pocket ? target.address : nil, account: target.kind == .account ? target.address : nil)
        )
        let declared = try DeclaredAuthorization(
            authorizer: target.address, invocation: invocation, passphrase: ChimpNetworkConfig.testnet.passphrase,
            expirationLedger: 1_000 + SorobanAuth.expirationLedgers, nonce: 7
        )
        let call = PreparedIntegrationCall(
            authorizer: authorizer, call: root, entry: declared.entry, digest: declared.digest,
            expirationLedger: declared.expirationLedger, preparedAtLedger: 1_000, acceptedKeys: acceptedKeys
        )
        return PreparedUpdate(target: target, route: route, factory: Self.fleetFactory, call: call)
    }

    func needsRefresh(_ prepared: PreparedUpdate) async throws -> Bool { false }

    func send(_ prepared: PreparedUpdate, signed: CardSignatures) async throws -> UpdateOutcome {
        try await Task.sleep(for: delay)
        sendCount += 1
        guard prepared.call.acceptedKeys.contains(signed.card.publicKey) else { throw ChipError.cardNotAccepted(tapped: signed.card.publicKey) }
        if scenario == .notConfirmedYet {
            throw UpdateError.unverified(hash: prepared.target.wasmHash, transactionHash: String(repeating: "e", count: 64))
        }
        code[prepared.target.address] = .wasm(hash: Self.headHash)
        return .updated(transactionHash: String(repeating: "e", count: 64))
    }
}

extension UpdatesModel {
    /// Le service de l'app : la chaîne de la session. Sur un appareil sans NFC (simulateur), les builds Debug et Testing
    /// prennent la fausse chaîne (rien ne part), comme le retrait d'une carte.
    static func liveService(_ config: ChimpNetworkConfig) -> UpdatesService {
        #if DESIGN_CATALOG
        if !NFCTagReaderSession.readingAvailable { return MockUpdatesService() }
        #endif
        return ChainUpdatesService(config: config)
    }
}
