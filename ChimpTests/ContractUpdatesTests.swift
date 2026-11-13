import Foundation
import Testing
import stellarsdk
@testable import ChimpDAO

/// Mises à jour du code des contrats, étape 1 (lecture) : portage des cas de
/// `reference/terminal/src/chain/updates.test.ts` et `fleet.test.ts`, mêmes valeurs.
struct ContractUpdatesTests {
    // Trois versions publiées, de la plus ancienne à la plus récente, tête en dernier : la forme que rend `fleet()`.
    static let r1 = String(repeating: "11", count: 32)
    static let r2 = String(repeating: "22", count: 32)
    static let r3 = String(repeating: "33", count: 32)
    static let stranger = String(repeating: "99", count: 32)

    let published = FleetTarget(head: r3, history: [r1, r2, r3], legacy: false)
    let legacy = FleetTarget(head: r3, history: [], legacy: true)
    let fleetRef = ContractExecutable.fleet(owner: "CFACTORY", tag: "pocket")

    // MARK: updateStatus

    @Test("À jour sur la tête")
    func upToDate() {
        #expect(ContractUpdates.status(target: published, current: .wasm(hash: Self.r3)) == .upToDate(hash: Self.r3))
    }

    @Test("Une version de retard : la tête est proposée")
    func oneBehind() {
        #expect(ContractUpdates.status(target: published, current: .wasm(hash: Self.r2)) == .available(from: Self.r2, to: Self.r3))
    }

    @Test("Deux versions de retard : la tête est encore proposée")
    func twoBehind() {
        #expect(ContractUpdates.status(target: published, current: .wasm(hash: Self.r1)) == .available(from: Self.r1, to: Self.r3))
    }

    @Test("Un hash jamais publié par la flotte n'est jamais proposé")
    func stranger() {
        let got = ContractUpdates.status(target: published, current: .wasm(hash: Self.stranger))
        #expect(got == .custom(hash: Self.stranger))
        #expect(!got.wantsUpdate)
    }

    @Test("Une mise à jour ne pointe que vers la tête : jamais de retour en arrière")
    func onlyHead() {
        for from in [Self.r1, Self.r2] {
            guard case .available(_, let to) = ContractUpdates.status(target: published, current: .wasm(hash: from)) else {
                Issue.record("expected available for \(from)"); continue
            }
            #expect(to == Self.r3)
        }
        #expect(!ContractUpdates.status(target: published, current: .wasm(hash: Self.r3)).wantsUpdate)
    }

    @Test("Une Pocket qui suit la flotte est « managed », quelle que soit la cible")
    func managed() {
        #expect(ContractUpdates.status(target: published, current: fleetRef) == .managed)
        #expect(ContractUpdates.status(target: legacy, current: fleetRef) == .managed)
        #expect(ContractUpdates.status(target: FleetTarget(head: nil, history: [], legacy: true), current: fleetRef) == .managed)
    }

    @Test("Rien de publié : « unknown », pas « en retard »")
    func unknown() {
        #expect(ContractUpdates.status(target: FleetTarget(head: nil, history: [], legacy: false), current: .wasm(hash: Self.r1)) == .unknown)
    }

    @Test("Un contrat sans wasm est « custom »")
    func asset() {
        #expect(ContractUpdates.status(target: published, current: .asset) == .custom(hash: nil))
    }

    @Test("Cible legacy (une tête, pas d'historique) : toute différence est proposée, la tête est à jour")
    func legacyTarget() {
        #expect(ContractUpdates.status(target: legacy, current: .wasm(hash: Self.r1)) == .available(from: Self.r1, to: Self.r3))
        #expect(ContractUpdates.status(target: legacy, current: .wasm(hash: Self.stranger)) == .available(from: Self.stranger, to: Self.r3))
        #expect(ContractUpdates.status(target: legacy, current: .wasm(hash: Self.r3)) == .upToDate(hash: Self.r3))
    }

    @Test("Hash comparés sans tenir compte de la casse ni du préfixe 0x")
    func caseAndPrefix() {
        #expect(ContractUpdates.status(target: published, current: .wasm(hash: Self.r3.uppercased())) == .upToDate(hash: Self.r3))
        #expect(ContractUpdates.status(target: published, current: .wasm(hash: "0x" + Self.r2)).wantsUpdate)
        #expect(ContractUpdates.normHash("0xABCD") == "abcd")
    }

    @Test("Retour en arrière publié [R1, R2, R3, R2] : R2 est la cible, R3 est en retard")
    func rolledBack() {
        let rolledBack = FleetTarget(head: Self.r2, history: [Self.r1, Self.r2, Self.r3, Self.r2], legacy: false)
        #expect(ContractUpdates.status(target: rolledBack, current: .wasm(hash: Self.r3)) == .available(from: Self.r3, to: Self.r2))
        #expect(ContractUpdates.status(target: rolledBack, current: .wasm(hash: Self.r2)) == .upToDate(hash: Self.r2))
    }

    // MARK: birthRecognised, sameFleet

    @Test("Naissance d'un compte : la tête et ce qu'elle a remplacé, jamais un wasm inconnu")
    func birth() {
        #expect(ContractUpdates.birthRecognised(target: published, hash: Self.r3))
        #expect(ContractUpdates.birthRecognised(target: published, hash: Self.r1))
        #expect(!ContractUpdates.birthRecognised(target: published, hash: Self.stranger))
        #expect(ContractUpdates.birthRecognised(target: FleetTarget(head: nil, history: [], legacy: false), hash: Self.stranger))
        #expect(ContractUpdates.birthRecognised(target: FleetTarget(head: Self.r2, history: [], legacy: true), hash: Self.r2))
    }

    @Test("Même flotte : identique, ou la moindre différence")
    func sameFleet() {
        let f = Fleet(epoch: 4, pocket: published, account: legacy)
        #expect(ContractUpdates.sameFleet(f, f))
        var epoch = f; epoch.epoch = 5
        #expect(!ContractUpdates.sameFleet(f, epoch))
        var account = f; account.account.head = Self.r1
        #expect(!ContractUpdates.sameFleet(f, account))
        var pocket = f; pocket.pocket.history = [Self.r2, Self.r3]
        #expect(!ContractUpdates.sameFleet(f, pocket))
    }

    // MARK: decodeFleetView

    static func bytes(_ hex: String) -> SCValXDR { .bytes(Data(hex: hex)!) }

    static func entry(_ key: String, _ value: SCValXDR) -> SCMapEntryXDR { SCMapEntryXDR(key: .symbol(key), val: value) }

    /// La réponse de `fleet()` telle que le contrat l'encode : une map aux clés triées.
    static let wire = SCValXDR.map([
        entry("account", .void),
        entry("account_history", .vec([])),
        entry("epoch", .u32(3)),
        entry("pocket", bytes(r3)),
        entry("pocket_history", .vec([bytes(r1), bytes(r2), bytes(r3)])),
    ])

    @Test("fleet() : la structure du factory, tête en dernier")
    func decodeView() throws {
        #expect(try FleetClient.decodeView(Self.wire) == FleetView(
            epoch: 3, pocket: Self.r3, account: nil, pocketHistory: [Self.r1, Self.r2, Self.r3], accountHistory: []
        ))
    }

    @Test("fleet() : noms de champs en camelCase acceptés aussi")
    func decodeCamel() throws {
        let camel = SCValXDR.map([
            Self.entry("epoch", .u32(1)), Self.entry("pocket", .void), Self.entry("account", Self.bytes(Self.r1)),
            Self.entry("pocketHistory", .vec([])), Self.entry("accountHistory", .vec([Self.bytes(Self.r1)])),
        ])
        let view = try FleetClient.decodeView(camel)
        #expect(view.account == Self.r1)
        #expect(view.accountHistory == [Self.r1])
    }

    @Test("fleet() : une forme inattendue est refusée, jamais lue « rien de publié »", arguments: [
        SCValXDR.u32(7),
        .map([entry("pocket", bytes(r3))]),
        .map([entry("epoch", .u32(3)), entry("pocket", .bytes(Data(repeating: 0, count: 31)))]),
        .map([entry("epoch", .u32(3)), entry("pocket_history", .string("nope"))]),
    ])
    func decodeRefuses(_ bad: SCValXDR) {
        #expect(throws: FleetFormatError.self) { try FleetClient.decodeView(bad) }
    }

    // MARK: readFleet

    final class FakeFleet: FleetReading {
        let result: Result<FleetView?, Error>
        let head: String?
        private(set) var pocketHeadCalls = 0

        init(_ result: Result<FleetView?, Error>, pocketHead: String? = nil) {
            self.result = result
            head = pocketHead
        }

        func view() async throws -> FleetView? { try result.get() }
        func pocketHead() async throws -> String? {
            pocketHeadCalls += 1
            return head
        }
    }

    static let bundled = String(repeating: "aa", count: 32)
    let view = FleetView(epoch: 5, pocket: r3, account: r2, pocketHistory: [r1, r2, r3], accountHistory: [r1, r2])

    @Test("fleet() d'abord, avec ses historiques ; l'ancien getter n'est même pas appelé")
    func prefersView() async throws {
        let reader = FakeFleet(.success(view), pocketHead: Self.r1)
        let fleet = try await FleetClient.readFleet(reader, bundledAccount: Self.bundled)
        #expect(fleet == Fleet(
            epoch: 5,
            pocket: FleetTarget(head: Self.r3, history: [Self.r1, Self.r2, Self.r3], legacy: false),
            account: FleetTarget(head: Self.r2, history: [Self.r1, Self.r2], legacy: false)
        ))
        #expect(reader.pocketHeadCalls == 0)
    }

    @Test("Ancien factory : le hash de Pocket publié seul et le compte de Config/, en legacy")
    func legacyFactory() async throws {
        let fleet = try await FleetClient.readFleet(FakeFleet(.success(nil), pocketHead: Self.r1), bundledAccount: Self.bundled)
        #expect(fleet == Fleet(
            epoch: nil,
            pocket: FleetTarget(head: Self.r1, history: [], legacy: true),
            account: FleetTarget(head: Self.bundled, history: [], legacy: true)
        ))
    }

    @Test("Ancien factory sans rien de publié : pas de tête, pas d'erreur")
    func legacyUnpinned() async throws {
        let fleet = try await FleetClient.readFleet(FakeFleet(.success(nil)), bundledAccount: Self.bundled)
        #expect(fleet.pocket == FleetTarget(head: nil, history: [], legacy: true))
    }

    @Test("fleet() sans compte publié : Config/ pour le compte seulement")
    func bundledAccountOnly() async throws {
        var noAccount = view
        noAccount.account = nil
        noAccount.accountHistory = []
        let fleet = try await FleetClient.readFleet(FakeFleet(.success(noAccount)), bundledAccount: Self.bundled)
        #expect(!fleet.pocket.legacy)
        #expect(fleet.account == FleetTarget(head: Self.bundled, history: [], legacy: true))
    }

    @Test("Aucun hash de compte sur ce réseau : pas de tête de compte")
    func noBundledAccount() async throws {
        let fleet = try await FleetClient.readFleet(FakeFleet(.success(nil), pocketHead: Self.r1), bundledAccount: nil)
        #expect(fleet.account.head == nil)
    }

    @Test("Une panne de lecture n'est pas « pas de fleet() » : elle remonte")
    func transportFailure() async {
        await #expect(throws: StellarError.rpc("fetch failed")) {
            try await FleetClient.readFleet(FakeFleet(.failure(StellarError.rpc("fetch failed")), pocketHead: Self.r1), bundledAccount: Self.bundled)
        }
    }

    @Test("Refus du contrat (fonction absente) = ancien factory ; panne de transport ≠ refus")
    func contractTrap() {
        #expect(FleetClient.isContractTrap(StellarError.simulationFailed("HostError: Error(WasmVm, MissingValue)")))
        #expect(FleetClient.isContractTrap(StellarError.simulationFailed("Error(Contract, #12)")))
        #expect(!FleetClient.isContractTrap(StellarError.rpc("The request timed out.")))
        #expect(!FleetClient.isContractTrap(StellarError.simulationFailed("something else")))
    }

    // MARK: readExecutables, wasmState

    final class FakeLedger: LedgerEntryReading {
        var latest: UInt32 = 500
        var stored: [String: (data: LedgerEntryDataXDR?, liveUntil: UInt32?)] = [:]
        private(set) var requests: [[String]] = []

        func latestLedger() async throws -> UInt32 { latest }
        func entries(_ base64Keys: [String]) async throws -> [(key: String, data: LedgerEntryDataXDR?, liveUntil: UInt32?)] {
            requests.append(base64Keys)
            return base64Keys.compactMap { key in stored[key].map { (key: key, data: $0.data, liveUntil: $0.liveUntil) } }
        }
    }

    static let a = "CDWPHF7DRJ37GLFZGQDSO6RTX4QR75WTNKJUMFJRETQLIOAHFBU6RGYR"
    static let b = "CDGFNWFN7ZKU4XDPNXOGDQ4JZ7SZCMXLL3PYFESOCCA2L5DM3ZBCPEKC"
    static let c = "CAOL3K7VQTDZELQMKTAJB3WUQGL5JLXJKZ2Y44F77NH4CZNLW5I755XI"

    static func instance(_ contract: String, _ executable: ContractExecutableXDR) throws -> LedgerEntryDataXDR {
        .contractData(ContractDataEntryXDR(
            ext: .void, contract: try SCAddressXDR(contractId: contract), key: .ledgerKeyContractInstance,
            durability: .persistent, val: .contractInstance(SCContractInstanceXDR(executable: executable))
        ))
    }

    static func key(_ contract: String) throws -> String { try FleetClient.instanceKey(contract).xdrEncoded! }

    @Test("Code de plusieurs contrats en UNE requête, chacun rendu à son adresse")
    func readExecutables() async throws {
        let ledger = FakeLedger()
        ledger.stored[try Self.key(Self.a)] = (try Self.instance(Self.a, .wasm(WrappedData32(Data(hex: Self.r2)!))), 900)
        ledger.stored[try Self.key(Self.b)] = (try Self.instance(Self.b, .externalRef(
            ContractExecutableExternalRefXDR(executableOwner: try SCAddressXDR(contractId: Self.a), tag: "pocket")
        )), 900)
        ledger.stored[try Self.key(Self.c)] = (try Self.instance(Self.c, .token), 900)
        let got = try await FleetClient.readExecutables([Self.a, Self.b, Self.c], reader: ledger)
        #expect(got[Self.a] == .wasm(hash: Self.r2))
        #expect(got[Self.b] == .fleet(owner: Self.a, tag: "pocket"))
        #expect(got[Self.c] == .asset)
        #expect(ledger.requests.count == 1)
    }

    @Test("Un contrat sans instance vivante est absent du résultat, jamais deviné")
    func missingInstance() async throws {
        let ledger = FakeLedger()
        ledger.stored[try Self.key(Self.a)] = (try Self.instance(Self.a, .wasm(WrappedData32(Data(hex: Self.r1)!))), 900)
        let got = try await FleetClient.readExecutables([Self.a, Self.b], reader: ledger)
        #expect(got.keys.sorted() == [Self.a])
    }

    @Test("Une seule demande par adresse distincte")
    func distinctAddresses() async throws {
        let ledger = FakeLedger()
        _ = try await FleetClient.readExecutables([Self.a, Self.a, Self.a], reader: ledger)
        #expect(ledger.requests == [[try Self.key(Self.a)]])
    }

    @Test("Une très grande demande est coupée sous la limite de clés du RPC")
    func chunks() async throws {
        let ledger = FakeLedger()
        let many = (0..<150).map { i in
            try! ContractIdUtils.deriveContractId(
                deployer: try SCAddressXDR(contractId: Self.a), salt: Data(repeating: UInt8(i), count: 32), network: .testnet
            )
        }
        _ = try await FleetClient.readExecutables(many, reader: ledger)
        #expect(ledger.requests.map(\.count) == [100, 50])
    }

    static func codeEntry(liveUntil: UInt32?) -> (data: LedgerEntryDataXDR?, liveUntil: UInt32?) { (nil, liveUntil) }

    @Test("Code d'une version : vivant tant que son TTL est devant le ledger ; archivé après ; TTL 0 = vivant ; absent")
    func wasmState() async throws {
        let ledger = FakeLedger()
        let key = try FleetClient.codeKey(Self.r1).xdrEncoded!
        ledger.stored[key] = Self.codeEntry(liveUntil: 900)
        #expect(try await FleetClient.wasmState(Self.r1, reader: ledger) == .live)
        ledger.stored[key] = Self.codeEntry(liveUntil: 100)
        #expect(try await FleetClient.wasmState(Self.r1, reader: ledger) == .archived)
        ledger.stored[key] = Self.codeEntry(liveUntil: 0)
        #expect(try await FleetClient.wasmState(Self.r1, reader: ledger) == .live)
        ledger.stored = [:]
        #expect(try await FleetClient.wasmState(Self.r1, reader: ledger) == .missing)
    }
}
