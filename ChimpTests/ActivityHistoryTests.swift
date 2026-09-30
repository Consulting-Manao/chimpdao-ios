import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Session « Activity », étape 1 : historique lu sur la chaîne (`backfillChainHistory`, `lib/chain-history.ts`) et gardé
/// sur le téléphone (`lib/history.ts`). Vecteurs XDR calculés avec `@stellar/stellar-sdk` 17.0.1 (fonctions `symTopic` et
/// `addrTopic` du terminal) ; événements réels lus sur testnet le 2026-09-30 ; `card_added` : événement rendu par la
/// simulation de `add_card` sur le Main account `CCDO6J…DDYB` (rien d'envoyé).
struct ActivityHistoryTests {
    static let account = "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"
    static let pocket = "CCGYGX2HBP464WZWXHHFOMS25CMIBKH3PUKOKRESOM3Z2W4UJRLLJ72Q"
    static let admin = "GBLWPGXVH47YGMODIUHZJ7FETRISFU3TB7JGADTRIMU36OLWJ7PYEZ6M"
    static let xlmSAC = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
    static let usdcSAC = "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA"
    static let assets: [(code: String, contract: String)] = [("XLM", xlmSAC), ("USDC", usdcSAC)]
    static let assetMap = ["CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC": "XLM", "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA": "USDC"]

    static let transferTopic = "AAAADwAAAAh0cmFuc2Zlcg=="
    static let accountTopic = "AAAAEgAAAAGG7yf2cZ81ZB/ZbEEJCf9nNzDsFZZDPxZBRNkhrPbokQ=="
    static let pocketTopic = "AAAAEgAAAAGNg19HC/nuWza5zlcyWuiYgKj7fRTlRJJzN51blExWtA=="
    static let adminTopic = "AAAAEgAAAAAAAAAAV2ea9T8/gzHDRQ+U/KScUSLTcw/SYA5xQym/OXZP34I="
    static let nativeTopic = "AAAADgAAAAZuYXRpdmUAAA=="
    static let usdcAssetTopic = "AAAADgAAAD1VU0RDOkdCQkQ0N0lGNkxXSzdQN01ERVZTQ1dSN0RQVVdWM05ZM0RUUUVWRkw0TkFUNEFRSDNaTExGTEE1AAAA"
    /// 10 000 000 000 stroops = 1000 XLM (financement du 2026-09-29).
    static let thousandXLM = "AAAACgAAAAAAAAAAAAAAAlQL5AA="
    /// 25 000 000 unités = 2,5.
    static let twoAndAHalf = "AAAACgAAAAAAAAAAAAAAAAF9eEA="
    /// Valeur d'un `transfer` vers une adresse M (CAP-67) : `{ amount: 12345678, to_muxed_id: 42 }`.
    static let muxedValue = "AAAAEQAAAAEAAAACAAAADwAAAAZhbW91bnQAAAAAAAoAAAAAAAAAAAAAAAAAvGFOAAAADwAAAAt0b19tdXhlZF9pZAAAAAAFAAAAAAAAACo="
    static let cardAddedTopic = "AAAADwAAAApjYXJkX2FkZGVkAAA="
    /// `CardAdded { key: 04 07…07 }` tel que rendu par la simulation.
    static let cardAddedValue = "AAAAEQAAAAEAAAABAAAADwAAAANrZXkAAAAADQAAAEEEBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwAAAA=="
    static let cardAddedKey = "04" + String(repeating: "07", count: 64)

    /// L'événement réel du financement de testnet (ledger 4934237).
    static let funding = ChimpDAO.SorobanClient.ContractEvent(
        id: "0021192386545745920-0000000000", contractID: xlmSAC, ledger: 4_934_237, ledgerClosedAt: "2026-09-29T15:12:52Z",
        transactionHash: "d7b6b89580935e7617855d7d5136ae603603c9b19080c4c0d70075869ec7e425",
        topics: [transferTopic, adminTopic, accountTopic, nativeTopic], value: thousandXLM
    )

    static func transfer(
        id: String = "1-0", contract: String = xlmSAC, ledger: UInt32 = 100, hash: String = "h1",
        from: String = accountTopic, to: String = adminTopic, value: String = twoAndAHalf
    ) -> ChimpDAO.SorobanClient.ContractEvent {
        ChimpDAO.SorobanClient.ContractEvent(
            id: id, contractID: contract, ledger: ledger, ledgerClosedAt: "2026-09-30T10:00:00Z", transactionHash: hash,
            topics: [transferTopic, from, to, nativeTopic], value: value
        )
    }

    static func record(
        _ id: String, hash: String? = nil, from: String = account, to: String = admin, at: TimeInterval = 0, isLocal: Bool = false
    ) -> ActivityRecord {
        ActivityRecord(
            id: id, event: .transfer, hash: hash ?? id, from: from, to: to, assetCode: "XLM", amount: 1,
            at: Date(timeIntervalSince1970: 1_790_000_000 + at), isLocal: isLocal
        )
    }

    private func records(_ events: [ChimpDAO.SorobanClient.ContractEvent], known: Set<String> = []) -> [ActivityRecord] {
        ChainActivityHistory.records(
            from: events, account: Self.account, drawers: [Self.account, Self.pocket], assets: Self.assetMap, known: known
        )
    }

    // MARK: Classement (classifyTransfer, chain-history.test.ts)

    @Test("classifyTransfer : « falls back to plain payments » (envoyé, reçu), plus Move et carte ajoutée")
    func classification() {
        let drawers: Set<String> = [Self.account, Self.pocket]
        #expect(Self.record("a", from: Self.account, to: Self.admin).kind(drawers: drawers) == .sent)
        #expect(Self.record("b", from: Self.admin, to: Self.account).kind(drawers: drawers) == .received)
        #expect(Self.record("c", from: Self.account, to: Self.pocket).kind(drawers: drawers) == .moved)
        #expect(Self.record("d", from: Self.pocket, to: Self.account).kind(drawers: drawers) == .moved)
        #expect(Self.record("e", from: Self.admin, to: "GOTHER").kind(drawers: drawers) == nil)
        var card = Self.record("f")
        card.event = .cardAdded
        #expect(card.kind(drawers: drawers) == .cardAdded)
    }

    // MARK: Requête

    @Test("Sujets identiques à symTopic et addrTopic du terminal (SDK JS 17.0.1)")
    func topics() throws {
        #expect(ChainActivityHistory.transferTopic == Self.transferTopic)
        #expect(ChainActivityHistory.cardAddedTopic == Self.cardAddedTopic)
        #expect(try ChainActivityHistory.addressTopic(Self.account) == Self.accountTopic)
        #expect(try ChainActivityHistory.addressTopic(Self.pocket) == Self.pocketTopic)
        #expect(try ChainActivityHistory.addressTopic(Self.admin) == Self.adminTopic)
    }

    @Test("Filtres : expéditeur et destinataire par tiroir, 5 motifs par filtre, card_added, 5 filtres par requête")
    func filterGroups() throws {
        let two = try ChainActivityHistory.filterGroups(drawers: [Self.account, Self.pocket])
        #expect(two.count == 1)
        #expect(two[0].count == 2)
        let matchers = two[0][0].topics!.map(\.segmentMatchers)
        #expect(matchers == [
            [Self.transferTopic, Self.accountTopic, "*", "*"], [Self.transferTopic, "*", Self.accountTopic, "*"],
            [Self.transferTopic, Self.pocketTopic, "*", "*"], [Self.transferTopic, "*", Self.pocketTopic, "*"],
        ])
        #expect(two[0][0].contractIds == nil)
        #expect(two[0][1].topics!.map(\.segmentMatchers) == [[Self.cardAddedTopic]])

        // Main + 9 cartes : 20 motifs = 4 filtres, + card_added = 5 filtres, une requête. Une carte de plus : deux requêtes.
        let ten = try ChainActivityHistory.filterGroups(drawers: [Self.account] + Array(repeating: Self.pocket, count: 9))
        #expect(ten.map(\.count) == [5])
        let eleven = try ChainActivityHistory.filterGroups(drawers: [Self.account] + Array(repeating: Self.pocket, count: 10))
        #expect(eleven.map(\.count) == [5, 1])
        #expect(eleven.flatMap { $0 }.allSatisfy { ($0.topics?.count ?? 0) <= 5 })
    }

    @Test("Fenêtre du RPC dépassée : le plus ancien ledger gardé est lu dans le message réel")
    func retentionMessage() {
        let error = StellarError.rpc("-32600: startLedger must be within the ledger range: 4826245 - 4947204")
        #expect(ChainActivityHistory.oldestRetainedLedger(in: error) == 4_826_245)
        #expect(ChainActivityHistory.oldestRetainedLedger(in: StellarError.rpc("-32001: request exceeded processing limit threshold")) == nil)
        #expect(ChainActivityHistory.oldestRetainedLedger(in: CancellationError()) == nil)
    }

    // MARK: Lecture des événements

    @Test("Événement réel : 1000 XLM de l'admin vers le Main account, ledger fermé le 2026-09-29 à 15:12:52 UTC")
    func realFunding() throws {
        let rows = records([Self.funding])
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.id == "stellar:d7b6b89580935e7617855d7d5136ae603603c9b19080c4c0d70075869ec7e425:0021192386545745920-0000000000")
        #expect(row.hash == Self.funding.transactionHash)
        #expect(row.event == .transfer)
        #expect(row.from == Self.admin)
        #expect(row.to == Self.account)
        #expect(row.assetCode == "XLM")
        #expect(row.amount == 1000)
        #expect(row.at == Date(timeIntervalSince1970: 1_790_694_772))
        #expect(!row.isLocal)
        #expect(row.kind(drawers: [Self.account, Self.pocket]) == .received)
    }

    @Test("Montant exact en unités de l'actif, actif d'après le contrat émetteur (USDC)")
    func usdcAmount() throws {
        var event = Self.transfer(contract: Self.usdcSAC)
        event = ChimpDAO.SorobanClient.ContractEvent(
            id: event.id, contractID: event.contractID, ledger: event.ledger, ledgerClosedAt: event.ledgerClosedAt,
            transactionHash: event.transactionHash, topics: [Self.transferTopic, Self.pocketTopic, Self.adminTopic, Self.usdcAssetTopic],
            value: event.value
        )
        let row = try #require(records([event]).first)
        #expect(row.assetCode == "USDC")
        #expect(row.amount == Decimal(string: "2.5"))
        #expect(row.from == Self.pocket)
    }

    @Test("Faux paiement : un « transfer » émis par un autre contrat que les SAC XLM et USDC est ignoré")
    func unknownContractIgnored() {
        let fake = Self.transfer(contract: "CAOL3K7VQTDZELQMKTAJB3WUQGL5JLXJKZ2Y44F77NH4CZNLW5I755XI", from: Self.adminTopic, to: Self.accountTopic)
        #expect(records([fake]).isEmpty)
    }

    @Test("Ignorés : valeur en map (adresse M, comme le terminal), transaction déjà connue, aucun tiroir du compte")
    func ignoredEvents() {
        #expect(records([Self.transfer(value: Self.muxedValue)]).isEmpty)
        #expect(records([Self.funding], known: [Self.funding.transactionHash]).isEmpty)
        #expect(records([Self.transfer(from: Self.adminTopic, to: Self.adminTopic)]).isEmpty)
    }

    @Test("card_added du Main account : clé de la carte ; émis par un autre contrat : ignoré")
    func cardAdded() throws {
        let event = ChimpDAO.SorobanClient.ContractEvent(
            id: "2-0", contractID: Self.account, ledger: 200, ledgerClosedAt: "2026-09-30T11:00:00Z", transactionHash: "hc",
            topics: [Self.cardAddedTopic], value: Self.cardAddedValue
        )
        let row = try #require(records([event]).first)
        #expect(row.event == .cardAdded)
        #expect(row.cardKey == Self.cardAddedKey)
        #expect(row.from == Self.account)
        #expect(row.amount == nil)
        let elsewhere = ChimpDAO.SorobanClient.ContractEvent(
            id: "3-0", contractID: Self.pocket, ledger: 200, ledgerClosedAt: "2026-09-30T11:00:00Z", transactionHash: "hd",
            topics: [Self.cardAddedTopic], value: Self.cardAddedValue
        )
        #expect(records([elsewhere]).isEmpty)
    }

    @Test("N° du reçu : le ledger ; une ligne du téléphone le reçoit quand la chaîne montre sa transaction")
    func ledgers() throws {
        let row = try #require(records([Self.funding]).first)
        #expect(row.ledger == 4_934_237)
        let local = Self.record("stellar:\(Self.funding.transactionHash)", hash: Self.funding.transactionHash, isLocal: true)
        #expect(local.ledger == nil)
        let filled = ChainActivityHistory.withLedgers([local, Self.record("other")], from: [Self.funding])
        #expect(filled.map(\.ledger) == [4_934_237, nil])
    }

    // MARK: Stockage (lib/history.ts)

    @Test("mergeRecords : une ligne par identifiant, la plus récente d'abord, 200 au plus")
    func merging() {
        let merged = ActivityLog.merging([Self.record("a", at: 1)], [Self.record("a", at: 9), Self.record("b", at: 5)])
        #expect(merged.map(\.id) == ["a", "b"])
        #expect(merged.first?.at == Date(timeIntervalSince1970: 1_790_000_009))
        let many = (0..<250).map { Self.record("r\($0)", at: TimeInterval($0)) }
        let capped = ActivityLog.merging([], many)
        #expect(capped.count == 200)
        #expect(capped.first?.id == "r249")
        #expect(capped.last?.id == "r50")
    }

    @Test("Une ligne écrite par le téléphone remplace celle de la chaîne pour la même transaction")
    func localIsAuthoritative() {
        let chain = Self.record("stellar:h1:1-0", hash: "h1", to: Self.admin)
        let local = Self.record("stellar:h1", hash: "h1", to: "MAQAA5L65LSYH7CQ3VTJ7F3HHLGCL3DSLAR2Y47263D56MNNGHSQSAAAAAAAAAAE2LP26", isLocal: true)
        let rows = ActivityLog.recordingLocal(local, into: [chain, Self.record("other")])
        #expect(rows.map(\.id).sorted() == ["other", "stellar:h1"])
        #expect(rows.first { $0.hash == "h1" }?.isLocal == true)
    }

    @Test("recordPayment : envoi confirmé écrit par le téléphone, rangé avec son compte, adresse exacte gardée (M)")
    func recordedPayment() {
        let session = AppSession(store: InMemoryLocalWalletStore(), network: .testnet)
        let m = "MAQAA5L65LSYH7CQ3VTJ7F3HHLGCL3DSLAR2Y47263D56MNNGHSQSAAAAAAAAAAE2LP26"
        session.recordActivity(.payment(
            hash: "abc", from: Self.pocket, to: m, assetCode: "USDC", amount: Decimal(string: "2.5")!, at: Date(timeIntervalSince1970: 5)
        ), account: Self.account)
        let rows = session.activity.activity(of: Self.account).records
        #expect(rows == [ActivityRecord(
            id: "stellar:abc", event: .transfer, hash: "abc", from: Self.pocket, to: m, assetCode: "USDC",
            amount: Decimal(string: "2.5")!, at: Date(timeIntervalSince1970: 5), isLocal: true
        )])
        #expect(rows.first?.kind(drawers: [Self.account, Self.pocket]) == .sent)
        #expect(session.activity.activity(of: Self.pocket).records.isEmpty)
    }

    @Test("Fichier : relu à l'identique, rangé par compte ; fichier illisible mis de côté")
    func fileStore() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try FileActivityStore(network: .testnet, directory: directory)
        #expect(store.fileURL.lastPathComponent == "activity-testnet.json")
        #expect(try store.load() == ActivityLog())
        let row = try #require(records([Self.funding]).first)
        try store.update(Self.account) {
            $0.records = [row]
            $0.coverage = ActivityCoverage(addresses: [Self.account], fromLedger: 1, toLedger: 2)
        }
        let reread = try FileActivityStore(network: .testnet, directory: directory)
        #expect(reread.activity(of: Self.account).records == [row])
        #expect(reread.activity(of: Self.pocket) == AccountActivity())

        try Data("pas du JSON".utf8).write(to: store.fileURL)
        #expect(try store.load() == ActivityLog())
        #expect(FileManager.default.fileExists(atPath: store.fileURL.appendingPathExtension("unreadable").path))
    }

    @Test("Garde-fou : aucun champ secret dans le fichier de l'historique")
    func noSecretFields() throws {
        var log = ActivityLog()
        var card = try #require(records([Self.funding]).first)
        card.event = .cardAdded
        card.cardKey = Self.cardAddedKey
        card.approvedBy = Self.cardAddedKey
        log.accounts[Self.account] = AccountActivity(records: [card], coverage: ActivityCoverage(addresses: [Self.account], fromLedger: 1, toLedger: 2))
        let json = String(decoding: try FileLocalWalletStore.encoder.encode(log), as: UTF8.self).lowercased()
        for word in ["secret", "seed", "private", "pin", "puk", "mnemonic"] {
            #expect(!json.contains("\"\(word)"), "champ « \(word) »")
        }
    }

    // MARK: Relecture de la fenêtre (sync)

    @Test("Première lecture : 12 tranches de 10 000 ledgers, la plus récente d'abord, progrès enregistré à chaque tranche")
    func firstSync() async throws {
        let source = FakeEventSource(latest: 200_000, events: [
            Self.transfer(id: "a", ledger: 199_990, hash: "ha"),
            Self.transfer(id: "b", ledger: 85_000, hash: "hb", from: Self.adminTopic, to: Self.pocketTopic),
            Self.transfer(id: "c", ledger: 70_000, hash: "hc"),
        ])
        var progress: [AccountActivity] = []
        let result = try await ChainActivityHistory(source: source, assets: Self.assets).sync(
            account: Self.account, drawers: [Self.pocket], activity: AccountActivity()
        ) { progress.append($0) }
        #expect(source.requests.map(\.start) == stride(from: 190_001, through: 80_001, by: -10_000).map { UInt32($0) })
        #expect(source.requests.first?.end == 200_000)
        #expect(source.requests.allSatisfy { $0.end - $0.start == 9_999 })
        #expect(progress.count == 12)
        #expect(progress.first?.records.map(\.hash) == ["ha"])
        #expect(result.records.map(\.hash).sorted() == ["ha", "hb"])
        #expect(result.coverage == ActivityCoverage(addresses: [Self.account, Self.pocket].sorted(), fromLedger: 80_001, toLedger: 200_000))
    }

    @Test("Lecture suivante : seulement les ledgers nouveaux ; une transaction déjà connue n'est pas relue")
    func incrementalSync() async throws {
        let source = FakeEventSource(latest: 200_050, events: [
            Self.transfer(id: "a", ledger: 200_010, hash: "ha"),
            Self.transfer(id: "b", ledger: 200_020, hash: "hb"),
        ])
        let known = Self.record("stellar:ha", hash: "ha", isLocal: true)
        let before = AccountActivity(
            records: [known],
            coverage: ActivityCoverage(addresses: [Self.account, Self.pocket].sorted(), fromLedger: 80_001, toLedger: 200_000)
        )
        let result = try await ChainActivityHistory(source: source, assets: Self.assets).sync(
            account: Self.account, drawers: [Self.pocket], activity: before
        ) { _ in }
        #expect(source.requests.map { [$0.start, $0.end] } == [[200_001, 200_050]])
        #expect(result.records.map(\.id).sorted() == ["stellar:ha", "stellar:hb:b"])
        #expect(result.coverage?.fromLedger == 80_001)
        #expect(result.coverage?.toLedger == 200_050)
    }

    @Test("Une carte de plus sur le compte : toute la fenêtre est relue")
    func newDrawerResets() async throws {
        let source = FakeEventSource(latest: 200_050, events: [])
        let before = AccountActivity(records: [], coverage: ActivityCoverage(addresses: [Self.account], fromLedger: 80_001, toLedger: 200_000))
        _ = try await ChainActivityHistory(source: source, assets: Self.assets).sync(
            account: Self.account, drawers: [Self.pocket], activity: before
        ) { _ in }
        #expect(source.requests.count == 12)
        #expect(source.requests.first?.end == 200_050)
    }

    @Test("Lignes gardées sans ledger (avant le N° du reçu) : toute la fenêtre est relue une fois et les complète")
    func missingLedgersRescan() async throws {
        let source = FakeEventSource(latest: 200_050, events: [Self.transfer(id: "a", ledger: 150_000, hash: "ha")])
        let old = Self.record("stellar:ha:a", hash: "ha")
        let before = AccountActivity(
            records: [old],
            coverage: ActivityCoverage(addresses: [Self.account, Self.pocket].sorted(), fromLedger: 80_001, toLedger: 200_000)
        )
        let result = try await ChainActivityHistory(source: source, assets: Self.assets).sync(
            account: Self.account, drawers: [Self.pocket], activity: before
        ) { _ in }
        #expect(source.requests.count == 12)
        #expect(result.records.map(\.ledger) == [150_000])
    }

    @Test("Requête refusée par le RPC : retentée (pauses de 1 s puis 2 s), puis la lecture continue")
    func retries() async throws {
        let source = FakeEventSource(latest: 20_000, events: [])
        source.failures = 2
        var history = ChainActivityHistory(source: source, assets: Self.assets)
        var pauses: [Duration] = []
        history.pause = { pauses.append($0) }
        let result = try await history.sync(account: Self.account, drawers: [], activity: AccountActivity()) { _ in }
        #expect(pauses == [.seconds(1), .seconds(2)])
        #expect(result.coverage?.fromLedger == 2)
    }

    @Test("Trois refus de suite : erreur, le progrès est gardé et la lecture suivante reprend là où elle s'était arrêtée")
    func failureKeepsProgress() async throws {
        let source = FakeEventSource(latest: 200_000, events: [Self.transfer(id: "a", ledger: 199_000, hash: "ha")])
        source.failAfter = 3
        var history = ChainActivityHistory(source: source, assets: Self.assets)
        history.pause = { _ in }
        var saved = AccountActivity()
        await #expect(throws: StellarError.self) {
            _ = try await history.sync(account: Self.account, drawers: [], activity: AccountActivity()) { saved = $0 }
        }
        #expect(saved.records.map(\.hash) == ["ha"])
        #expect(saved.coverage?.fromLedger == 170_001)
        #expect(saved.coverage?.toLedger == 200_000)

        source.failAfter = nil
        source.requests = []
        let resumed = try await history.sync(account: Self.account, drawers: [], activity: saved) { _ in }
        #expect(source.requests.first?.end == 170_000)
        #expect(source.requests.count == 9)
        #expect(resumed.coverage?.fromLedger == 80_001)
    }

    @Test("Fenêtre du RPC plus courte que 7 jours : on repart du plus ancien ledger gardé, sans erreur")
    func retentionMoved() async throws {
        let source = FakeEventSource(latest: 200_000, events: [])
        source.oldest = 175_000
        let result = try await ChainActivityHistory(source: source, assets: Self.assets).sync(
            account: Self.account, drawers: [], activity: AccountActivity()
        ) { _ in }
        #expect(result.coverage?.fromLedger == 175_001)
        #expect(source.requests.allSatisfy { $0.start >= 175_001 })
        #expect(source.requests.last?.start == 175_001)
    }
}

/// Faux RPC : rend les événements de sa liste compris dans la fenêtre demandée.
final class FakeEventSource: ActivityEventSource, @unchecked Sendable {
    struct Request: Equatable {
        let start: UInt32
        let end: UInt32
    }

    var latest: UInt32
    var events: [ChimpDAO.SorobanClient.ContractEvent]
    /// Plus ancien ledger gardé par le RPC.
    var oldest: UInt32 = 1
    /// Nombre de refus « processing limit » avant de répondre.
    var failures = 0
    /// Toutes les requêtes échouent après ce nombre de réponses réussies.
    var failAfter: Int?
    var requests: [Request] = []
    private var answered = 0

    init(latest: UInt32, events: [ChimpDAO.SorobanClient.ContractEvent]) {
        self.latest = latest
        self.events = events
    }

    func latestLedger() async throws -> UInt32 { latest }

    func contractEvents(filters: [EventFilter], startLedger: UInt32, endLedger: UInt32, pageLimit: Int) async throws -> ChimpDAO.SorobanClient.EventRange {
        if startLedger < oldest {
            throw StellarError.rpc("-32600: startLedger must be within the ledger range: \(oldest) - \(latest)")
        }
        if failures > 0 {
            failures -= 1
            throw StellarError.rpc("-32001: request exceeded processing limit threshold")
        }
        if let failAfter, answered >= failAfter {
            throw StellarError.rpc("-32001: request exceeded processing limit threshold")
        }
        answered += 1
        requests.append(Request(start: startLedger, end: endLedger))
        return ChimpDAO.SorobanClient.EventRange(
            events: events.filter { $0.ledger >= startLedger && $0.ledger <= endLedger }, oldestLedger: oldest, latestLedger: latest
        )
    }
}
