import Foundation
import stellarsdk

/// Mettre à jour le code d'un contrat (« Updates », étape 2). Portage de `update-run.ts` (`performUpdate`,
/// `inspectUpdate`) et des routes de `provisioning.ts` (`updateAccountCode`, `accountHopCalls`, `upgradePurse`,
/// `accountVersion`, `accountFactory`, `checkUpdate`, `runUpdate`). Voir `CLIENT-INTEGRATION.md` §6.5 à §6.7.
///
/// Découpé pour l'iPhone comme les autres appels signés par une carte : **avant le tap** (lectures de la chaîne, choix de
/// la route, autorisation préparée, règle 9), puis **après le tap** (envoi, puis relecture du contrat, quoi qu'il arrive).
///
/// Écarts avec la référence (DESIGN_NOTES §13) :
/// - code de la version **archivé** : refus avec une phrase, pas de restauration par l'app (le terminal la paie avec sa
///   propre clé de frais ; l'app n'a pas de clé, et le serveur de frais n'est pas prévu pour ça) ;
/// - compte v2 sans factory (saut interrompu) : `set_factory` puis `update()` **en un seul lot du router**, une seule
///   signature (le terminal fait deux signatures ; deux taps d'affilée sur iPhone) ;
/// - compte v2 dont le factory enregistré n'est pas celui de `Config/` : refus, rien n'est signé (`update()` installerait
///   ce que ce factory-là désigne).

/// Les fonctions qu'une carte signe sur ses propres contrats (`cardLifecycleShape` de `card-auth.ts`) : la Pocket et le
/// Main account répondent **à eux-mêmes** (`require_auth` sur leur propre adresse), donc le signataire est le contrat
/// appelé. Réclamé par adresse **et** fonction : une forme qui réclamerait un appel qu'elle ne comprend pas ferait signer
/// autre chose. Rien n'est « pris » : chaque fonction est une feuille.
struct CardLifecycleShape: AuthShape {
    /// `require_chip` sur la Pocket.
    static let pocketMethods: Set<String> = ["set_owner", "upgrade", "set_upgrade_policy"]
    /// `require_self` sur le compte, 1 carte sur n.
    static let accountMethods: Set<String> = [
        "add_card", "remove_card", "add_passkey", "remove_passkey", "abandon", "upgrade", "update", "set_factory", "set_upgrade_policy",
    ]

    var pocket: String?
    let account: String?

    func signer(of call: ContractCall) -> String? {
        if let pocket, call.contract == pocket, Self.pocketMethods.contains(call.function) { return call.contract }
        if let account, call.contract == account, Self.accountMethods.contains(call.function) { return call.contract }
        return nil
    }

    func pulls(of call: ContractCall, from: String) throws -> [ContractCall] { [] }
}

/// Le contrat à mettre à jour et la version visée (`UpdateTarget`).
struct UpdateTarget: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Le Main account : n'importe quelle carte du compte signe.
        case account
        /// Le wallet d'une carte (`Manual`) : seulement cette carte signe.
        case pocket
    }

    let kind: Kind
    let address: String
    /// La version à faire tourner, hexadécimal minuscule.
    let wasmHash: String
}

/// L'issue d'une mise à jour (`UpdateOutcome`).
enum UpdateOutcome: Equatable, Sendable {
    /// La chaîne faisait déjà tourner la version visée : rien n'a été signé.
    case alreadyCurrent
    /// Le contrat fait tourner la version visée. Hash `nil` : arrivée malgré une erreur à l'envoi.
    case updated(transactionHash: String?)
}

enum UpdateError: Error, Equatable, LocalizedError {
    /// Le contrat suit la flotte : il n'a pas de code à lui à mettre à jour (`upgrade-managed`).
    case followsFleet
    /// Le code de la version n'est pas installé sur le réseau (`update-wasm-missing`).
    case wasmMissing(hash: String)
    /// Le code de la version est archivé (il se restaure, mais pas depuis l'app).
    case wasmArchived(hash: String)
    /// Le compte demande à un autre factory que celui de ChimpDAO ce qu'il doit installer : rien n'est signé.
    case unexpectedFactory(found: String, expected: String)
    /// Envoyée, mais le contrat ne fait pas encore tourner la version (`update-unverified`).
    case unverified(hash: String, transactionHash: String?)

    var errorDescription: String? {
        switch self {
        case .followsFleet: "This follows ChimpDAO's code and updates by itself. Nothing to sign."
        case .wasmMissing: "The new version isn't on the network yet. Nothing was signed."
        case .wasmArchived: "The new version is asleep on the network and must be woken up by ChimpDAO first. Nothing was signed."
        case .unexpectedFactory: "This account takes its updates from an unknown source. For your safety, nothing was signed."
        case .unverified: "The update was sent, but the account doesn't run the new version yet."
        }
    }
}

/// Ce dont la logique d'une mise à jour a besoin de la chaîne (`UpdateDeps`), derrière un protocole pour les tests.
protocol UpdateChainReading {
    /// Le code que le contrat fait tourner, lu **sur la chaîne**, jamais dans un cache.
    func executable(of address: String) async throws -> ContractExecutable
    func wasmState(_ hash: String) async throws -> WasmState
}

/// La logique d'une mise à jour, chaque effet injecté (`update-run.ts`). L'état visé est « le hash du code = la cible » :
/// la refaire, ou la faire depuis un autre téléphone, ne change rien. L'ordre est tout le dessin :
/// 1. lire la chaîne ; 2. déjà là : s'arrêter, ne rien demander ; 3. refuser ce qui ne peut pas se faire ;
/// 4. signer et envoyer, puis **relire** quoi qu'il arrive.
enum UpdateRun {
    /// Pauses entre les relectures : un ledger fermé met un moment à être lisible.
    static let readbackDelay: Duration = .milliseconds(1500)
    static let readbackTries = 3
    static let ambiguousTries = 4

    enum Preflight: Equatable {
        case current
        case needed
    }

    static func runs(_ executable: ContractExecutable, _ hash: String) -> Bool {
        if case .wasm(let current) = executable { return ContractUpdates.normHash(current) == ContractUpdates.normHash(hash) }
        return false
    }

    /// Avant le tap (`inspectUpdate` + les refus du début de `performUpdate`) : y a-t-il quelque chose à faire, et
    /// peut-on le faire ? Une Pocket qui suit la flotte, ou une version absente ou archivée : refus, sans tap.
    static func preflight(_ target: UpdateTarget, chain: UpdateChainReading) async throws -> Preflight {
        let now = try await chain.executable(of: target.address)
        if runs(now, target.wasmHash) { return .current }
        if case .fleet = now { throw UpdateError.followsFleet }
        switch try await chain.wasmState(ContractUpdates.normHash(target.wasmHash)) {
        case .live: return .needed
        case .missing: throw UpdateError.wasmMissing(hash: ContractUpdates.normHash(target.wasmHash))
        case .archived: throw UpdateError.wasmArchived(hash: ContractUpdates.normHash(target.wasmHash))
        }
    }

    /// Une erreur qui ne dit pas si la transaction est arrivée (`isAmbiguous`) : le réseau ne l'a pas confirmée à temps,
    /// ou n'a pas répondu à l'envoi. Distincte d'un refus, après lequel une relecture est une formalité.
    static func isAmbiguous(_ error: Error) -> Bool {
        switch error {
        case StellarError.notConfirmed, StellarError.sendUnanswered: true
        default: false
        }
    }

    /// Après le tap : envoie, puis relit le contrat quoi qu'il arrive (fin de `performUpdate`). Une erreur ambiguë est
    /// relue plus longtemps ; un refus, une fois. Arrivée malgré l'erreur : réussite, sans hash.
    static func sendAndConfirm(
        _ target: UpdateTarget,
        chain: UpdateChainReading,
        send: () async throws -> String,
        sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> UpdateOutcome {
        let wasmHash = ContractUpdates.normHash(target.wasmHash)
        var sent: String?
        var failure: Error?
        do {
            sent = try await send()
        } catch {
            failure = error
        }
        let tries = failure.map { isAmbiguous($0) ? ambiguousTries : 1 } ?? readbackTries
        for attempt in 0..<tries {
            if attempt > 0 { try await sleep(readbackDelay * attempt) }
            // Une lecture ratée n'est pas un verdict : on réessaie, puis on retombe sur l'erreur.
            if let after = try? await chain.executable(of: target.address), runs(after, wasmHash) {
                return .updated(transactionHash: sent)
            }
        }
        if let failure { throw failure }
        throw UpdateError.unverified(hash: wasmHash, transactionHash: sent)
    }
}

/// Ce qui est prêt avant le tap : la route choisie et l'autorisation que la carte signera.
struct PreparedUpdate {
    enum Route: Equatable {
        /// Compte v1 (code d'avant les passkeys) : `upgrade(hash)` puis `set_factory(factory)`, un lot du router.
        case accountHop
        /// Compte v2 sans factory (saut interrompu) : `set_factory(factory)` puis `update()`, un lot du router.
        case accountSetFactoryThenUpdate
        /// Compte v2 : `update()`, sans argument (il installe ce que son factory désigne).
        case accountUpdate
        /// Wallet d'une carte `Manual` : `upgrade(hash)`, signé par sa puce.
        case pocketUpgrade
    }

    let target: UpdateTarget
    let route: Route
    /// L'adresse du factory dont le compte recevra ses mises à jour, **en entier** sur l'écran de vérification.
    let factory: String
    let call: PreparedIntegrationCall
}

/// Lectures et appels réels d'une mise à jour.
struct ContractUpdateClient: UpdateChainReading {
    let client: SorobanClient
    let config: ChimpNetworkConfig

    private var reader: SimulationReader { SimulationReader(client: client, source: config.feePayer) }
    private var ledger: SorobanLedgerEntryReader { SorobanLedgerEntryReader(client: client) }

    // MARK: Lectures

    func executable(of address: String) async throws -> ContractExecutable {
        guard let found = try await FleetClient.readExecutables([address], reader: ledger)[address] else {
            throw StellarError.invalidResponse("\(address.prefix(8))… has no contract instance")
        }
        return found
    }

    func wasmState(_ hash: String) async throws -> WasmState {
        try await FleetClient.wasmState(hash, reader: ledger)
    }

    /// La génération du code du compte (`accountVersion`) : le code d'avant les passkeys n'a pas `version()`, et c'est
    /// ainsi qu'il se reconnaît (un refus du contrat se lit 1).
    func accountVersion(_ account: String) async throws -> UInt32 {
        do {
            let value = try await reader.readValue(contract: account, function: "version", arguments: [])
            guard case .u32(let version) = value else { throw StellarError.invalidResponse("version returned \(value)") }
            return version
        } catch {
            if FleetClient.isContractTrap(error) { return 1 }
            throw error
        }
    }

    /// Le factory que le compte interroge (`accountFactory`) ; `nil` s'il n'en a pas reçu, ou si son code est trop ancien.
    func accountFactory(_ account: String) async throws -> String? {
        do {
            let value = try await reader.readValue(contract: account, function: "factory", arguments: [])
            if case .void = value { return nil }
            guard let address = value.address else { throw StellarError.invalidResponse("factory returned \(value)") }
            return try address.toStrKey()
        } catch {
            if FleetClient.isContractTrap(error) { return nil }
            throw error
        }
    }

    // MARK: Avant le tap

    /// Y a-t-il quelque chose à signer (`checkUpdate`) ? Lit la chaîne. Un compte qui fait déjà tourner la version mais n'a
    /// jamais reçu son factory (saut interrompu) a encore une signature à donner.
    func check(_ target: UpdateTarget) async throws -> UpdateRun.Preflight {
        let preflight = try await UpdateRun.preflight(target, chain: self)
        if preflight == .current, target.kind == .account, try await accountVersion(target.address) >= 2,
           try await accountFactory(target.address) == nil {
            return .needed
        }
        return preflight
    }

    /// La route, lue sur la chaîne et jamais retenue (`updateAccountCode`, `upgradePurse`).
    func route(for target: UpdateTarget) async throws -> PreparedUpdate.Route {
        switch target.kind {
        case .pocket:
            return .pocketUpgrade
        case .account:
            guard try await accountVersion(target.address) >= 2 else { return .accountHop }
            guard let factory = try await accountFactory(target.address) else { return .accountSetFactoryThenUpdate }
            // Seul point de confiance de `update()` : le factory vient de `Config/`, jamais du compte ni du réseau.
            guard factory == config.contracts.factory else {
                throw UpdateError.unexpectedFactory(found: factory, expected: config.contracts.factory)
            }
            return .accountUpdate
        }
    }

    /// Les appels de chaque route (`accountHopCalls`, `update`, `upgrade`), sans réseau : la racine signée et, pour un lot
    /// du router, ses jambes. Le factory est celui de `Config/`.
    static func calls(
        for route: PreparedUpdate.Route, target: UpdateTarget, factory: String, router: String
    ) throws -> (root: ContractCall, legs: [ContractCall]?) {
        guard let hash = Data(hex: ContractUpdates.normHash(target.wasmHash)), hash.count == 32 else {
            throw StellarError.invalidResponse("not a 32-byte wasm hash: \(target.wasmHash)")
        }
        let upgrade = ContractCall(contract: target.address, function: "upgrade", arguments: [.bytes(hash)])
        let setFactory = ContractCall(contract: target.address, function: "set_factory", arguments: [try ContractArgument.address(factory)])
        let update = ContractCall(contract: target.address, function: "update", arguments: [])
        switch route {
        case .pocketUpgrade, .accountUpdate:
            return (route == .pocketUpgrade ? upgrade : update, nil)
        case .accountHop:
            let legs = [upgrade, setFactory]
            return (try RouterBatch.call(router: router, caller: target.address, legs: legs), legs)
        case .accountSetFactoryThenUpdate:
            let legs = [setFactory, update]
            return (try RouterBatch.call(router: router, caller: target.address, legs: legs), legs)
        }
    }

    /// Prépare la mise à jour, avant le tap : route lue sur la chaîne, autorisation préparée comme pour les intégrations
    /// (Main account : simulation et arbre vérifié ; Pocket : arbre déclaré). `acceptedKeys` : les cartes du compte, ou
    /// la seule carte de la Pocket. À appeler après `check` (`.needed`).
    func prepare(_ target: UpdateTarget, acceptedKeys: [ChipPublicKey]) async throws -> PreparedUpdate {
        let route = try await route(for: target)
        let factory = config.contracts.factory
        let (root, legs) = try Self.calls(for: route, target: target, factory: factory, router: config.contracts.router)
        let authorizer: CallAuthorizer = target.kind == .pocket ? .pocket(target.address) : .account(target.address)
        let shape = target.kind == .pocket
            ? CardLifecycleShape(pocket: target.address, account: nil)
            : CardLifecycleShape(pocket: nil, account: target.address)
        let call = try await IntegrationCallClient(client: client, config: config).prepare(
            call: root, legs: legs, authorizer: authorizer, shape: shape, acceptedKeys: acceptedKeys
        )
        return PreparedUpdate(target: target, route: route, factory: factory, call: call)
    }

    // MARK: Après le tap

    /// Envoie l'autorisation signée, puis relit le contrat jusqu'à ce qu'il fasse tourner la version (`runUpdate`).
    func send(
        _ prepared: PreparedUpdate,
        signed: CardSignatures,
        feeSigner: FeeSigner,
        onProgress: ((PaymentProgress) -> Void)? = nil
    ) async throws -> UpdateOutcome {
        let integration = IntegrationCallClient(client: client, config: config)
        let outcome = try await UpdateRun.sendAndConfirm(prepared.target, chain: self) {
            try await integration.sendSigned(prepared.call, signed: signed, feeSigner: feeSigner, onProgress: onProgress)
        }
        // Le factory n'est pas lu dans le code : une route qui l'enregistre est vérifiée par relecture, elle aussi.
        if prepared.target.kind == .account, prepared.route != .accountUpdate,
           try await accountFactory(prepared.target.address) != config.contracts.factory {
            throw UpdateError.unverified(hash: ContractUpdates.normHash(prepared.target.wasmHash), transactionHash: {
                if case .updated(let hash) = outcome { return hash } else { return nil }
            }())
        }
        return outcome
    }
}
