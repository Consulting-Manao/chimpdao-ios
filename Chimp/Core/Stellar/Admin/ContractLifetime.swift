#if CHIMP_ADMIN
import Foundation
import stellarsdk

/// Durée de vie (TTL) des contrats dont l'app dépend sur **testnet**, mode admin uniquement (Debug et Testing).
///
/// Sur Soroban, l'instance et le code d'un contrat expirent s'ils ne sont pas prolongés ; le vault DeFindex XLM et sa
/// stratégie Blend arrivent à échéance vers la mi-novembre 2026 (relevé du 2026-10-15 : instance du vault jusqu'au ledger
/// 5 705 704, stratégie et code jusqu'au ledger 5 722 646 ; pool Blend jusqu'au ledger 7 148 148, hors de cause).
/// N'importe qui peut prolonger : ici l'admin de testnet signe et paie une opération `extendFootprintTtl` sur l'instance
/// et le code de chaque contrat. Aucune autorisation de contrat, aucune carte, aucun argent du compte ne bouge.
///
/// Une transaction **par contrat** : le loyer se paie en frais, et les frais d'une transaction tiennent sur 32 bits
/// (≈ 429 XLM au plus ; le SDK lit aussi `minResourceFee` sur 32 bits). Coût mesuré le 2026-10-15 pour 1 555 200 ledgers :
/// vault ≈ 245 XLM, stratégie ≈ 109 XLM de testnet.
struct ContractLifetime {
    /// Un contrat suivi : son instance et son code, et jusqu'à quel ledger chacun vit.
    struct Entry: Equatable, Identifiable {
        let label: String
        let contract: String
        let wasmHash: Data
        let instanceLiveUntil: UInt32
        let codeLiveUntil: UInt32

        var id: String { contract }
        /// Le plus proche des deux.
        var liveUntil: UInt32 { min(instanceLiveUntil, codeLiveUntil) }
    }

    /// Durée de vie visée à partir de maintenant : 1 555 200 ledgers (≈ 90 jours à 5 s, ≈ 104 à 5,8 s).
    static let extensionLedgers: UInt32 = 1_555_200
    /// Moyenne observée sur testnet, pour une date indicative seulement.
    static let secondsPerLedger: Double = 5.8

    let config: ChimpNetworkConfig
    let keyStore: AdminKeyStore
    private let client: SorobanClient

    init(config: ChimpNetworkConfig, keyStore: AdminKeyStore) throws {
        try CardEnrolment.requireTestnet(config)
        self.config = config
        self.keyStore = keyStore
        client = SorobanClient(config: config)
    }

    /// Les contrats du vault à surveiller : le vault et sa stratégie (lue dans `Config/`).
    static func vaultTargets(_ config: ChimpNetworkConfig) -> [(label: String, contract: String)] {
        guard let vault = config.integrations?.defindexVaults.first else { return [] }
        var targets = [(label: "DeFindex XLM vault", contract: vault.vault)]
        if let strategy = vault.strategy { targets.append((label: "XLM Blend strategy", contract: strategy)) }
        return targets
    }

    static func instanceKey(_ contract: String) throws -> LedgerKeyXDR {
        .contractData(LedgerKeyContractDataXDR(contract: try SCAddressXDR(contractId: contract), key: .ledgerKeyContractInstance, durability: .persistent))
    }

    static func codeKey(_ wasmHash: Data) throws -> LedgerKeyXDR {
        .contractCode(try LedgerKeyContractCodeXDR(wasmId: wasmHash.map { String(format: "%02x", $0) }.joined()))
    }

    /// Jusqu'à quand vit chaque contrat, et le dernier ledger fermé.
    func read(_ targets: [(label: String, contract: String)]) async throws -> (latest: UInt32, entries: [Entry]) {
        let latest = try await client.latestLedger()
        var entries: [Entry] = []
        for target in targets {
            let instance = try await ledgerEntry(try Self.instanceKey(target.contract))
            guard case .contractData(let data) = try LedgerEntryDataXDR(fromBase64: instance.xdr),
                  let contractInstance = data.val.contractInstance, case .wasm(let hash) = contractInstance.executable else {
                throw StellarError.invalidResponse("\(target.label) has no Wasm instance")
            }
            let code = try await ledgerEntry(try Self.codeKey(hash.wrapped))
            entries.append(Entry(
                label: target.label, contract: target.contract, wasmHash: hash.wrapped,
                instanceLiveUntil: UInt32(instance.liveUntilLedgerSeq ?? 0), codeLiveUntil: UInt32(code.liveUntilLedgerSeq ?? 0)
            ))
        }
        return (latest, entries)
    }

    /// La transaction qui prolonge l'instance et le code d'un contrat, simulée et assemblée (frais = loyer), non signée.
    private func extensionTransaction(_ entry: Entry, source: String) async throws -> Transaction {
        let operation = ExtendFootprintTTLOperation(ledgersToExpire: Self.extensionLedgers)
        let now = UInt64(Date().timeIntervalSince1970)
        let transaction = try Transaction(
            sourceAccount: try await client.account(source), operations: [operation], memo: Memo.none,
            preconditions: TransactionPreconditions(timeBounds: TimeBounds(minTime: 0, maxTime: now + SorobanClient.transactionTimeout))
        )
        let footprint = LedgerFootprintXDR(readOnly: [try Self.instanceKey(entry.contract), try Self.codeKey(entry.wasmHash)], readWrite: [])
        transaction.setSorobanTransactionData(data: SorobanTransactionDataXDR(
            resources: SorobanResourcesXDR(footprint: footprint, instructions: 0, diskReadBytes: 0, writeBytes: 0)
        ))
        try client.assemble(transaction, with: try await client.simulate(transaction))
        return transaction
    }

    /// Ce que coûterait la prolongation de chaque contrat, en XLM (simulation, rien n'est envoyé). Source : le payeur de
    /// frais, un compte qui existe toujours (la simulation ne lit pas son solde).
    func estimate(_ entries: [Entry]) async throws -> [String: Decimal] {
        var costs: [String: Decimal] = [:]
        for entry in entries {
            let transaction = try await extensionTransaction(entry, source: config.feePayer)
            costs[entry.contract] = Decimal(transaction.fee) / 10_000_000
        }
        return costs
    }

    /// Prolonge chaque contrat jusqu'à `extensionLedgers` ledgers après maintenant : une transaction par contrat, signée
    /// et payée par l'admin. Renvoie les hash, dans l'ordre.
    func extend(_ entries: [Entry]) async throws -> [String] {
        guard let admin = try keyStore.keyPair() else { throw FundingError.noAdminKey }
        var hashes: [String] = []
        for entry in entries {
            let transaction = try await extensionTransaction(entry, source: admin.accountId)
            try transaction.sign(keyPair: admin, network: client.network)
            hashes.append(try await client.submitAndWait(transaction))
        }
        return hashes
    }

    private func ledgerEntry(_ key: LedgerKeyXDR) async throws -> LedgerEntry {
        guard let encoded = key.xdrEncoded else { throw StellarError.invalidResponse("could not encode ledger key") }
        let entries = try await client.ledgerEntries([encoded])
        guard let entry = entries.first else { throw StellarError.invalidResponse("ledger entry not found (expired?)") }
        return entry
    }

    /// Date indicative de fermeture d'un ledger.
    static func estimatedDate(of ledger: UInt32, latest: UInt32, now: Date = .now) -> Date {
        now.addingTimeInterval(Double(Int64(ledger) - Int64(latest)) * secondsPerLedger)
    }
}
#endif
