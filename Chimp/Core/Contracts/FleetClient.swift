import Foundation
import stellarsdk

/// Mises à jour du code des contrats, partie **lecture de la chaîne** : portage fidèle de
/// `reference/terminal/src/chain/fleet.ts` (lectures seulement ; `restoreWasm` viendra avec la mise à jour elle-même).
/// Ici on lit, jamais on ne décide : `ContractUpdates` juge.
///
/// - `FleetClient.readFleet` : la vue `fleet()` du factory quand il l'a ; sinon l'ancien `pocket_wasm_hash()` et le hash
///   du compte de `Config/`, marqués `legacy`.
/// - `FleetClient.readExecutables` : le code de plusieurs contrats en **un** `getLedgerEntries`, sans simulation.
/// - `FleetClient.wasmState` : le code d'une version est-il installé et vivant ?

/// La vue `fleet()` du factory, décodée. Forme exacte (historique du plus ancien au plus récent, tête en dernier) :
/// `Fleet { epoch: u32, pocket: Option<BytesN<32>>, account: Option<BytesN<32>>, pocket_history: Vec<BytesN<32>>,
/// account_history: Vec<BytesN<32>> }`.
struct FleetView: Equatable, Sendable {
    var epoch: UInt32
    var pocket: String?
    var account: String?
    var pocketHistory: [String]
    var accountHistory: [String]
}

/// `fleet()` n'a pas la forme attendue : le contrat et l'app ne sont pas d'accord sur le format. Jamais remplacé par une
/// valeur par défaut, qui se lirait « rien n'est publié ».
struct FleetFormatError: Error, Equatable, LocalizedError {
    let detail: String
    var errorDescription: String? { "fleet(): \(detail)" }
}

/// D'où la flotte est lue : la chaîne dans l'app, un faux dans les tests (`FleetReader`).
protocol FleetReading {
    /// La vue `fleet()`, ou `nil` si le factory est antérieur à `fleet()`. Une panne de transport remonte.
    func view() async throws -> FleetView?
    /// L'ancien getter : le wasm de Pocket publié, ou `nil` s'il n'y en a pas.
    func pocketHead() async throws -> String?
}

/// Les entrées du ledger dont ces lectures ont besoin (`LedgerReader`), derrière un protocole pour les tests.
protocol LedgerEntryReading {
    func latestLedger() async throws -> UInt32
    /// Les entrées présentes (une entrée absente ou archivée n'y est pas), clé en base64 telle que rendue par le RPC.
    func entries(_ base64Keys: [String]) async throws -> [(key: String, data: LedgerEntryDataXDR?, liveUntil: UInt32?)]
}

/// Le code d'une version sur le ledger. `archived` se restaure (par n'importe qui) ; `missing`, non.
enum WasmState: Equatable, Sendable {
    case live
    case archived
    case missing
}

enum FleetClient {
    // MARK: Flotte

    /// Décode la réponse de `fleet()` (`decodeFleetView`). Strict sur la forme, tolérant seulement sur l'écriture des
    /// noms de champs (`pocket_history` ou `pocketHistory`).
    static func decodeView(_ value: SCValXDR) throws -> FleetView {
        guard case .map(let entries) = value else { throw FleetFormatError(detail: "returned something other than a struct") }
        let fields = entries ?? []
        func field(_ names: String...) -> SCValXDR? {
            fields.first { entry in
                if case .symbol(let name) = entry.key { names.contains(name) } else { false }
            }?.val
        }
        guard case .u32(let epoch)? = field("epoch") else { throw FleetFormatError(detail: "epoch is not a u32") }
        return FleetView(
            epoch: epoch,
            pocket: try optionalHash(field("pocket"), "pocket"),
            account: try optionalHash(field("account"), "account"),
            pocketHistory: try hashList(field("pocket_history", "pocketHistory"), "pocket_history"),
            accountHistory: try hashList(field("account_history", "accountHistory"), "account_history")
        )
    }

    private static func hash(_ value: SCValXDR, _ what: String) throws -> String {
        guard case .bytes(let data) = value, data.count == 32 else { throw FleetFormatError(detail: "\(what) is not a 32-byte hash") }
        return data.hexString
    }

    private static func optionalHash(_ value: SCValXDR?, _ what: String) throws -> String? {
        switch value {
        case nil, .void?: nil
        case let value?: try hash(value, what)
        }
    }

    private static func hashList(_ value: SCValXDR?, _ what: String) throws -> [String] {
        switch value {
        case nil, .void?: return []
        case .vec(let items)?: return try (items ?? []).enumerated().map { try hash($1, "\(what)[\($0)]") }
        default: throw FleetFormatError(detail: "\(what) is not a list")
        }
    }

    /// La flotte telle que l'app doit la juger (`readFleet`). `fleet()` d'abord ; sur un factory sans `fleet()`, la cible
    /// `pocket` est le hash publié seul et la cible `account` celui de `Config/`, toutes deux `legacy`. Un factory qui a
    /// `fleet()` mais n'a pas encore publié de compte prend `Config/` pour le compte seulement.
    static func readFleet(_ reader: FleetReading, bundledAccount: String?) async throws -> Fleet {
        let bundled = FleetTarget(head: bundledAccount.map(ContractUpdates.normHash), history: [], legacy: true)
        if let view = try await reader.view() {
            return Fleet(
                epoch: view.epoch,
                pocket: FleetTarget(head: view.pocket, history: view.pocketHistory, legacy: false),
                account: view.account.map { FleetTarget(head: $0, history: view.accountHistory, legacy: false) } ?? bundled
            )
        }
        let pocketHead = try await reader.pocketHead()
        return Fleet(
            epoch: nil,
            pocket: FleetTarget(head: pocketHead.map(ContractUpdates.normHash), history: [], legacy: true),
            account: bundled
        )
    }

    /// Le contrat a dit non, par opposition au réseau qui n'a pas pu le lui demander (`isContractTrap`). Seul un refus
    /// du contrat fait passer au mode `legacy` ; une panne de transport n'en est jamais un.
    static func isContractTrap(_ error: Error) -> Bool {
        guard case StellarError.simulationFailed(let message) = error else { return false }
        return message.range(of: #"Error\(Contract, #\d+\)|HostError|MissingValue|UnreachableCodeReached"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: Code des contrats

    /// La clé de l'entrée « instance » d'un contrat : là où vit son code.
    static func instanceKey(_ contract: String) throws -> LedgerKeyXDR {
        .contractData(LedgerKeyContractDataXDR(contract: try SCAddressXDR(contractId: contract), key: .ledgerKeyContractInstance, durability: .persistent))
    }

    /// La clé du code d'une version (`codeKey`).
    static func codeKey(_ hash: String) throws -> LedgerKeyXDR {
        .contractCode(try LedgerKeyContractCodeXDR(wasmId: ContractUpdates.normHash(hash)))
    }

    /// Le code d'une entrée « instance », ou `nil` si ce n'en est pas une (`executableFromEntry`).
    static func executable(from data: LedgerEntryDataXDR) -> ContractExecutable? {
        guard case .contractData(let entry) = data, case .contractInstance(let instance) = entry.val else { return nil }
        switch instance.executable {
        case .wasm(let hash):
            return .wasm(hash: hash.wrapped.hexString)
        case .externalRef(let ref):
            return .fleet(owner: (try? ref.executableOwner.toStrKey()) ?? "", tag: ref.tagString ?? ref.tag.hexString)
        case .token:
            return .asset
        }
    }

    /// Le RPC limite une requête à 200 clés ; on reste bien en dessous.
    static let keysPerRequest = 100

    /// Le code de plusieurs contrats, en aussi peu de requêtes que possible (une pour un Main account et ses cartes).
    /// Un contrat sans entrée « instance » vivante est simplement absent du résultat : archivé ou jamais déployé, ce
    /// n'est jamais une raison de deviner un hash (« unknown » pour l'appelant).
    static func readExecutables(_ addresses: [String], reader: LedgerEntryReading) async throws -> [String: ContractExecutable] {
        var unique: [String] = []
        for address in addresses where !unique.contains(address) { unique.append(address) }
        var byKey: [String: String] = [:]
        for address in unique {
            guard let encoded = try instanceKey(address).xdrEncoded else { throw StellarError.invalidResponse("could not encode ledger key") }
            byKey[encoded] = address
        }
        var out: [String: ContractExecutable] = [:]
        for start in stride(from: 0, to: unique.count, by: keysPerRequest) {
            let chunk = unique[start..<min(start + keysPerRequest, unique.count)]
            let keys = try chunk.map { address -> String in
                guard let encoded = try instanceKey(address).xdrEncoded else { throw StellarError.invalidResponse("could not encode ledger key") }
                return encoded
            }
            for entry in try await reader.entries(keys) {
                guard let address = byKey[entry.key], let data = entry.data, let executable = executable(from: data) else { continue }
                out[address] = executable
            }
        }
        return out
    }

    /// Le code de cette version est-il installé et vivant (`wasmState`) ? Demandé avant toute mise à jour : un code absent
    /// ferait échouer la mise à jour **après** le tap. Un TTL de 0 veut dire « pas de TTL rendu », pas « expiré ».
    static func wasmState(_ hash: String, reader: LedgerEntryReading) async throws -> WasmState {
        guard let encoded = try codeKey(hash).xdrEncoded else { throw StellarError.invalidResponse("could not encode ledger key") }
        let latest = try await reader.latestLedger()
        guard let entry = try await reader.entries([encoded]).first else { return .missing }
        if let until = entry.liveUntil, until > 0, until < latest { return .archived }
        return .live
    }
}

// MARK: Réseau

/// La flotte lue sur le factory du réseau, par simulation (`chainFleetReader`).
struct ChainFleetReader: FleetReading {
    let reader: ContractReading
    let factory: String

    func view() async throws -> FleetView? {
        do {
            return try FleetClient.decodeView(try await reader.readValue(contract: factory, function: "fleet", arguments: []))
        } catch {
            // Un refus du contrat : un factory plus ancien, sans `fleet()`. Une panne de transport n'est pas une réponse,
            // et ne doit jamais faire passer une histoire pour une tête seule.
            if FleetClient.isContractTrap(error) { return nil }
            throw error
        }
    }

    func pocketHead() async throws -> String? {
        let value = try await reader.readValue(contract: factory, function: "pocket_wasm_hash", arguments: [])
        if case .void = value { return nil }
        guard case .bytes(let data) = value, data.count == 32 else { throw FleetFormatError(detail: "pocket_wasm_hash is not a 32-byte hash") }
        return data.hexString
    }
}

/// Les entrées du ledger par le RPC du réseau.
struct SorobanLedgerEntryReader: LedgerEntryReading {
    let client: SorobanClient

    func latestLedger() async throws -> UInt32 { try await client.latestLedger() }

    func entries(_ base64Keys: [String]) async throws -> [(key: String, data: LedgerEntryDataXDR?, liveUntil: UInt32?)] {
        try await client.ledgerEntries(base64Keys).map { entry in
            (key: entry.key, data: entry.valueXdr, liveUntil: entry.liveUntilLedgerSeq.map { UInt32(clamping: $0) })
        }
    }
}
