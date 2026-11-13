import Foundation
import Testing
import stellarsdk
@testable import ChimpDAO

/// Mises à jour du code, étape 2 : la logique de `update-run.ts` (lire, s'arrêter si c'est déjà là, refuser ce qui ne
/// peut pas se faire, envoyer, relire) et les appels de chaque route (`accountHopCalls`, `update`, `upgrade`).
struct ContractUpdateRunTests {
    static let account = "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"
    static let pocket = "CDGFNWFN7ZKU4XDPNXOGDQ4JZ7SZCMXLL3PYFESOCCA2L5DM3ZBCPEKC"
    static let factory = "CDWPHF7DRJ37GLFZGQDSO6RTX4QR75WTNKJUMFJRETQLIOAHFBU6RGYR"
    static let router = "CAOL3K7VQTDZELQMKTAJB3WUQGL5JLXJKZ2Y44F77NH4CZNLW5I755XI"
    static let old = String(repeating: "11", count: 32)
    static let head = String(repeating: "33", count: 32)

    let target = UpdateTarget(kind: .account, address: account, wasmHash: head)

    /// Une chaîne scriptée : les codes lus, dans l'ordre (le dernier se répète), et l'état du code de la version.
    final class FakeChain: UpdateChainReading {
        var executables: [Result<ContractExecutable, Error>]
        var wasm: WasmState
        private(set) var reads = 0

        init(_ executables: [Result<ContractExecutable, Error>], wasm: WasmState = .live) {
            self.executables = executables
            self.wasm = wasm
        }

        func executable(of address: String) async throws -> ContractExecutable {
            defer { reads += 1 }
            return try executables[min(reads, executables.count - 1)].get()
        }

        func wasmState(_ hash: String) async throws -> WasmState { wasm }
    }

    // MARK: Avant le tap

    @Test("Déjà sur la version : rien à signer")
    func current() async throws {
        #expect(try await UpdateRun.preflight(target, chain: FakeChain([.success(.wasm(hash: Self.head.uppercased()))])) == .current)
    }

    @Test("Version plus ancienne, code de la nouvelle vivant : à faire")
    func needed() async throws {
        #expect(try await UpdateRun.preflight(target, chain: FakeChain([.success(.wasm(hash: Self.old))])) == .needed)
    }

    @Test("Un contrat qui suit la flotte n'a pas de code à lui : refus avant tout tap")
    func followsFleet() async {
        await #expect(throws: UpdateError.followsFleet) {
            try await UpdateRun.preflight(target, chain: FakeChain([.success(.fleet(owner: Self.factory, tag: "pocket"))]))
        }
    }

    @Test("Code de la version absent ou archivé : refus avant tout tap (sinon échec après le tap)")
    func wasmNotLive() async {
        await #expect(throws: UpdateError.wasmMissing(hash: Self.head)) {
            try await UpdateRun.preflight(target, chain: FakeChain([.success(.wasm(hash: Self.old))], wasm: .missing))
        }
        await #expect(throws: UpdateError.wasmArchived(hash: Self.head)) {
            try await UpdateRun.preflight(target, chain: FakeChain([.success(.wasm(hash: Self.old))], wasm: .archived))
        }
    }

    // MARK: Après le tap

    private func run(_ chain: FakeChain, send: @escaping () async throws -> String) async throws -> UpdateOutcome {
        try await UpdateRun.sendAndConfirm(target, chain: chain, send: send, sleep: { _ in })
    }

    @Test("Envoyée, relue sur la version : mise à jour, avec le hash")
    func updated() async throws {
        let chain = FakeChain([.success(.wasm(hash: Self.head))])
        #expect(try await run(chain) { "abc" } == .updated(transactionHash: "abc"))
        #expect(chain.reads == 1)
    }

    @Test("La relecture attend que le ledger soit lisible (3 essais)")
    func readbackRetries() async throws {
        let chain = FakeChain([.success(.wasm(hash: Self.old)), .failure(StellarError.rpc("hiccup")), .success(.wasm(hash: Self.head))])
        #expect(try await run(chain) { "abc" } == .updated(transactionHash: "abc"))
        #expect(chain.reads == 3)
    }

    @Test("Envoyée mais jamais relue sur la version : « pas vérifiée », jamais « réussie »")
    func unverified() async {
        let chain = FakeChain([.success(.wasm(hash: Self.old))])
        await #expect(throws: UpdateError.unverified(hash: Self.head, transactionHash: "abc")) {
            try await self.run(chain) { "abc" }
        }
        #expect(chain.reads == UpdateRun.readbackTries)
    }

    @Test("Refus du réseau, contrat inchangé : l'erreur remonte après une seule relecture")
    func refusal() async {
        let chain = FakeChain([.success(.wasm(hash: Self.old))])
        await #expect(throws: StellarError.transactionFailed(hash: "abc", detail: "no")) {
            try await self.run(chain) { throw StellarError.transactionFailed(hash: "abc", detail: "no") }
        }
        #expect(chain.reads == 1)
    }

    @Test("Erreur ambiguë mais arrivée : relue plus longtemps, réussite sans hash")
    func ambiguousLanded() async throws {
        let chain = FakeChain([.success(.wasm(hash: Self.old)), .success(.wasm(hash: Self.old)), .success(.wasm(hash: Self.head))])
        #expect(try await run(chain) { throw StellarError.notConfirmed(hash: "abc") } == .updated(transactionHash: nil))
        #expect(chain.reads == 3)
    }

    @Test("Erreur ambiguë jamais arrivée : quatre relectures, puis l'erreur")
    func ambiguousNotLanded() async {
        let chain = FakeChain([.success(.wasm(hash: Self.old))])
        await #expect(throws: StellarError.sendUnanswered(hash: "abc", detail: "timeout")) {
            try await self.run(chain) { throw StellarError.sendUnanswered(hash: "abc", detail: "timeout") }
        }
        #expect(chain.reads == UpdateRun.ambiguousTries)
        #expect(UpdateRun.isAmbiguous(StellarError.notConfirmed(hash: "x")))
        #expect(!UpdateRun.isAmbiguous(StellarError.transactionFailed(hash: "x", detail: "no")))
    }

    // MARK: Routes

    static func calls(_ route: PreparedUpdate.Route, kind: UpdateTarget.Kind = .account) throws -> (root: ContractCall, legs: [ContractCall]?) {
        let address = kind == .pocket ? pocket : account
        return try ContractUpdateClient.calls(
            for: route, target: UpdateTarget(kind: kind, address: address, wasmHash: head), factory: factory, router: router
        )
    }

    static let upgradeCall = ContractCall(contract: account, function: "upgrade", arguments: [.bytes(Data(hex: head)!)])

    @Test("Compte v1 : upgrade(hash) puis set_factory(factory de Config/), un seul lot du router signé par le compte")
    func hopCalls() throws {
        let (root, legs) = try Self.calls(.accountHop)
        let setFactory = ContractCall(contract: Self.account, function: "set_factory", arguments: [try ContractArgument.address(Self.factory)])
        #expect(legs == [Self.upgradeCall, setFactory])
        #expect(root == (try RouterBatch.call(router: Self.router, caller: Self.account, legs: [Self.upgradeCall, setFactory])))
        // L'arbre signé : le lot, et sous lui les deux jambes du compte, rien d'autre.
        let tree = try IntegrationCallClient.declaredInvocation(
            call: root, legs: legs, authorizer: .account(Self.account), shape: CardLifecycleShape(pocket: nil, account: Self.account)
        )
        let expected = try root.invocation(subInvocations: [Self.upgradeCall.invocation(), setFactory.invocation()])
        #expect(try XDREncoder.encode(tree) == XDREncoder.encode(expected))
    }

    @Test("Compte v2 sans factory : set_factory puis update(), un seul lot")
    func setFactoryThenUpdateCalls() throws {
        let (_, legs) = try Self.calls(.accountSetFactoryThenUpdate)
        #expect(legs?.map(\.function) == ["set_factory", "update"])
    }

    @Test("Compte v2 : update() sans argument ; wallet d'une carte : upgrade(hash) sur la Pocket")
    func singleCalls() throws {
        let update = try Self.calls(.accountUpdate)
        #expect(update.root == ContractCall(contract: Self.account, function: "update", arguments: []))
        #expect(update.legs == nil)
        let pocket = try Self.calls(.pocketUpgrade, kind: .pocket)
        #expect(pocket.root == ContractCall(contract: Self.pocket, function: "upgrade", arguments: [.bytes(Data(hex: Self.head)!)]))
    }

    @Test("La forme d'une carte ne réclame que ses propres contrats, par adresse ET fonction")
    func lifecycleShape() {
        let shape = CardLifecycleShape(pocket: Self.pocket, account: Self.account)
        #expect(shape.signer(of: ContractCall(contract: Self.account, function: "update", arguments: [])) == Self.account)
        #expect(shape.signer(of: ContractCall(contract: Self.pocket, function: "upgrade", arguments: [])) == Self.pocket)
        #expect(shape.signer(of: ContractCall(contract: Self.pocket, function: "update", arguments: [])) == nil)
        #expect(shape.signer(of: ContractCall(contract: Self.factory, function: "upgrade", arguments: [])) == nil)
        #expect(shape.signer(of: ContractCall(contract: Self.account, function: "transfer", arguments: [])) == nil)
    }
}
