import Foundation
import stellarsdk

/// Ce dont l'historique a besoin du RPC Stellar (implémenté par `SorobanClient`, remplacé dans les tests).
protocol ActivityEventSource {
    func latestLedger() async throws -> UInt32
    func contractEvents(filters: [EventFilter], startLedger: UInt32, endLedger: UInt32, pageLimit: Int) async throws -> SorobanClient.EventRange
    /// Arguments du premier appel de contrat d'une transaction (message CCTP d'une arrivée).
    func invocationArguments(_ hash: String) async throws -> [SCValXDR]?
}

extension ActivityEventSource {
    func invocationArguments(_ hash: String) async throws -> [SCValXDR]? { nil }
}

extension SorobanClient: ActivityEventSource {}

/// Historique lu sur la chaîne. Portage de `backfillChainHistory` (`reference/terminal/src/lib/chain-history.ts`) :
/// les événements `transfer` des SAC où un tiroir du compte est l'expéditeur ou le destinataire, sur les ~7 jours que le
/// RPC garde (`getEvents`, **aucun autre service**), ajoutés à l'historique du téléphone ; une transaction déjà connue
/// n'est pas relue (la ligne du téléphone fait foi).
///
/// Écarts (DESIGN_NOTES §13) :
/// - seuls les événements des SAC **XLM et USDC** sont gardés (décision de Barth du 2026-09-30) : le terminal accepte un
///   `transfer` émis par n'importe quel contrat, donc un faux paiement reçu. Le filtre est fait ici, sur l'adresse du
///   contrat émetteur (fixée par Stellar), et non dans la requête : mesuré sur testnet, la requête filtrée par contrat est
///   2 à 10 fois plus lente et échoue plus souvent (« request exceeded processing limit threshold ») ;
/// - l'événement `card_added` du Main account est lu en plus (décision du 2026-09-30, format vérifié par simulation) ;
/// - la fenêtre est relue **par tranches, la plus récente d'abord**, et le téléphone retient ce qu'il a déjà relu
///   (`ActivityCoverage`) : le RPC public met de 1 à 3 minutes à relire 7 jours d'un coup ;
/// - une requête refusée par le RPC est retentée (`attempts` fois) avant d'abandonner.
struct ChainActivityHistory {
    /// `LOOKBACK_LEDGERS` : ~7 jours à ~5 s par ledger, la mémoire des événements du RPC testnet.
    static let lookbackLedgers: UInt32 = 120_000
    /// Ce que le RPC parcourt en une requête (~10 000 ledgers, vérifié le 2026-09-29) : une tranche = une requête.
    static let chunkLedgers: UInt32 = 10_000
    /// `PAGE_LIMIT`.
    static let pageLimit = 1000
    /// Essais par tranche avant d'abandonner (le RPC public refuse souvent une requête qui passe au second essai).
    static let attempts = 3

    let source: ActivityEventSource
    /// Adresse du SAC → code de l'actif (XLM, USDC).
    let assets: [String: String]
    /// Vaults connus (Grow) : un transfert vers l'un d'eux est un dépôt, depuis l'un d'eux un retrait.
    let vaults: [String: ActivityRecord.VaultLabel]
    /// Circle CCTP (D4) : un transfert venu de son `CctpForwarder` est une arrivée d'une autre blockchain.
    let cctp: IntegrationConfig.CCTP?
    /// Qui livre les arrivées d'une autre blockchain (Circle CCTP, ROZO).
    let arrivalSources: [String: ActivityRecord.ArrivalSource]
    var pause: (Duration) async -> Void = { try? await Task.sleep(for: $0) }

    init(
        source: ActivityEventSource, assets: [(code: String, contract: String)], vaults: [String: ActivityRecord.VaultLabel] = [:],
        cctp: IntegrationConfig.CCTP? = nil, rozo: IntegrationConfig.Rozo? = nil
    ) {
        self.source = source
        self.assets = Dictionary(uniqueKeysWithValues: assets.map { ($0.contract, $0.code) })
        self.vaults = vaults
        self.cctp = cctp
        arrivalSources = ActivityRecord.arrivalSources(cctp: cctp, rozo: rozo)
    }

    /// Les arrivées CCTP nouvellement lues reçoivent leurs détails (chaîne et adresse d'origine, frais de Circle), lus dans
    /// le message de leur transaction. Une relecture ratée laisse la ligne sans détails, jamais fausse.
    func detailingArrivals(_ rows: [ActivityRecord]) async -> [ActivityRecord] {
        guard let cctp else { return rows }
        var result: [ActivityRecord] = []
        for row in rows {
            // Seules les arrivées CCTP ont un message à relire (ROZO paie par un simple `transfer`).
            guard row.event == .bridgeArrival, row.from == cctp.forwarder,
                  let arguments = try? await source.invocationArguments(row.hash),
                  let first = arguments.first, case .bytes(let data) = first,
                  let message = try? CCTPMessage(data) else {
                result.append(row)
                continue
            }
            result.append(row.withArrivalDetails(from: message, cctp: cctp))
        }
        return result
    }

    /// Relit ce qui manque de la fenêtre du RPC pour ces tiroirs et l'ajoute à `activity`. `onProgress` reçoit l'historique
    /// après chaque tranche (à enregistrer, et à afficher tout de suite) : une panne en cours de route ne perd rien, et la
    /// prochaine lecture reprend là où celle-ci s'est arrêtée.
    func sync(
        account: String,
        drawers: [String],
        activity: AccountActivity,
        onProgress: (AccountActivity) throws -> Void
    ) async throws -> AccountActivity {
        let addresses = Array(Set(drawers + [account])).sorted()
        let groups = try Self.filterGroups(drawers: addresses, clawbackContracts: assets.keys.sorted())
        let latest = try await source.latestLedger()
        // `latest - LOOKBACK_LEDGERS` : ici `lookbackLedgers` ledgers exactement (12 tranches), jamais avant le ledger 2.
        var floor = latest > Self.lookbackLedgers + 1 ? latest - Self.lookbackLedgers + 1 : 2
        var state = activity
        // Tout relire si les tiroirs ont changé, si la fenêtre relue est sortie de la mémoire du RPC, ou si une ligne lue
        // sur la chaîne n'a pas encore son ledger (lignes gardées avant le « N° » du reçu : relue une seule fois).
        if let coverage = state.coverage,
           coverage.addresses != addresses || coverage.toLedger < floor || state.records.contains(where: { !$0.isLocal && $0.ledger == nil }) {
            state.coverage = nil
        }
        var coverage = state.coverage ?? ActivityCoverage(addresses: addresses, fromLedger: latest + 1, toLedger: latest)

        /// Une tranche relue : ses lignes ajoutées, la fenêtre relue étendue, le tout remis à `onProgress`.
        func read(_ start: UInt32, _ end: UInt32) async throws -> Bool {
            guard let events = try await scan(groups, start: start, end: end, floor: &floor) else { return false }
            let known = Set(state.records.map(\.hash))
            let rows = await detailingArrivals(ActivityRecord.classifyingArrivals(
                ActivityRecord.groupingSwaps(
                    ActivityRecord.classifyingVaults(
                        Self.records(from: events, account: account, drawers: Set(addresses), assets: assets, known: known),
                        vaults: vaults, drawers: Set(addresses)
                    ),
                    drawers: Set(addresses)
                ),
                sources: arrivalSources, drawers: Set(addresses)
            ))
            state.records = ActivityLog.merging(Self.withLedgers(state.records, from: events), rows)
            return true
        }

        // Ce qui s'est passé depuis la dernière lecture, dans l'ordre (en général une seule tranche).
        var start = coverage.toLedger + 1
        while start <= latest {
            let end = min(latest, start + Self.chunkLedgers - 1)
            if try await read(start, end) { coverage.toLedger = end }
            state.coverage = coverage
            try onProgress(state)
            start = end + 1
        }
        // Puis le reste de la fenêtre, du plus récent au plus ancien (première lecture, ou lecture interrompue).
        while coverage.fromLedger > floor {
            let end = coverage.fromLedger - 1
            let start = max(floor, end >= Self.chunkLedgers ? end - Self.chunkLedgers + 1 : floor)
            if try await read(start, end) { coverage.fromLedger = max(floor, start) } else { coverage.fromLedger = floor }
            state.coverage = coverage
            try onProgress(state)
        }
        return state
    }

    /// Événements d'une tranche, pour tous les groupes de filtres. `nil` : la tranche est entièrement sortie de la mémoire
    /// du RPC. Si le RPC répond que le début est trop ancien, on repart du plus ancien ledger qu'il garde, comme le
    /// terminal (« Retention window moved past our start »).
    private func scan(_ groups: [[EventFilter]], start: UInt32, end: UInt32, floor: inout UInt32) async throws -> [SorobanClient.ContractEvent]? {
        var from = max(start, floor)
        var events: [SorobanClient.ContractEvent] = []
        for group in groups {
            var attempt = 0
            while true {
                guard from <= end else { return nil }
                do {
                    let range = try await source.contractEvents(filters: group, startLedger: from, endLedger: end, pageLimit: Self.pageLimit)
                    events += range.events
                    break
                } catch {
                    if let oldest = Self.oldestRetainedLedger(in: error), from <= oldest {
                        floor = oldest + 1
                        from = floor
                        continue
                    }
                    attempt += 1
                    guard attempt < Self.attempts else { throw error }
                    await pause(.seconds(attempt))
                }
            }
        }
        return events.sorted { ($0.ledger, $0.id) < ($1.ledger, $1.id) }
    }

    // MARK: Requête

    /// `symTopic("transfer")`, `symTopic("card_added")`.
    static let transferTopic = symbolTopic("transfer")
    static let clawbackTopic = symbolTopic("clawback")
    static let cardAddedTopic = symbolTopic("card_added")

    /// Filtres de la requête : pour chaque tiroir, un motif « expéditeur » et un motif « destinataire »
    /// (`[transfer, adresse, *, *]`, `[transfer, *, adresse, *]`), 5 motifs au plus par filtre ; plus un filtre `card_added`.
    /// Le RPC accepte 5 filtres au plus par requête : au-delà (plus de 9 cartes), plusieurs requêtes par tranche.
    static func filterGroups(drawers: [String], clawbackContracts: [String] = []) throws -> [[EventFilter]] {
        var matchers: [[String]] = []
        for address in drawers {
            let topic = try addressTopic(address)
            matchers.append([transferTopic, topic, "*", "*"])
            matchers.append([transferTopic, "*", topic, "*"])
        }
        var filters: [EventFilter] = stride(from: 0, to: matchers.count, by: 5).map { index in
            EventFilter(type: "contract", topics: matchers[index..<min(index + 5, matchers.count)].map { TopicFilter(segmentMatchers: $0) })
        }
        filters.append(EventFilter(type: "contract", topics: [TopicFilter(segmentMatchers: [cardAddedTopic])]))
        // `clawback` d'un SAC depuis le protocole 23 (CAP-67) : `[clawback, détenteur, actif]`, montant `i128`. Un seul
        // filtre, limité aux contrats de la liste blanche (5 au plus) ; le détenteur est trié à la lecture.
        if !clawbackContracts.isEmpty {
            filters.append(EventFilter(
                type: "contract", contractIds: Array(clawbackContracts.prefix(5)),
                topics: [TopicFilter(segmentMatchers: [clawbackTopic, "*", "*"])]
            ))
        }
        return stride(from: 0, to: filters.count, by: 5).map { Array(filters[$0..<min($0 + 5, filters.count)]) }
    }

    /// `addrTopic` : l'adresse en `ScVal`, XDR base64.
    static func addressTopic(_ address: String) throws -> String {
        Data(try XDREncoder.encode(SCValXDR.address(try SACClient.address(address)))).base64EncodedString()
    }

    private static func symbolTopic(_ symbol: String) -> String {
        Data(try! XDREncoder.encode(SCValXDR.symbol(symbol))).base64EncodedString()
    }

    /// « startLedger must be within the ledger range: 4826245 - 4947204 » → 4826245 (`/within the ledger range:? (\d+)/`).
    static func oldestRetainedLedger(in error: Error) -> UInt32? {
        guard case StellarError.rpc(let message) = error,
              let match = message.firstMatch(of: #/within the ledger range:? (\d+)/#) else { return nil }
        return UInt32(match.1)
    }

    // MARK: Lecture des événements

    /// Les lignes de l'historique : `transfer` d'un SAC connu entre des adresses dont au moins une est un tiroir du compte,
    /// `card_added` du Main account. Tout le reste est ignoré, comme une transaction déjà connue.
    static func records(
        from events: [SorobanClient.ContractEvent],
        account: String,
        drawers: Set<String>,
        assets: [String: String],
        known: Set<String>
    ) -> [ActivityRecord] {
        events.compactMap { event in
            guard !known.contains(event.transactionHash), let at = closeDate(event.ledgerClosedAt) else { return nil }
            let topics = event.topics.compactMap { decode($0) }
            guard topics.count == event.topics.count, case .symbol(let name) = topics.first else { return nil }
            let id = "stellar:\(event.transactionHash):\(event.id)"
            switch (name, topics.count) {
            case ("transfer", 4):
                guard let code = assets[event.contractID],
                      let from = strkey(topics[1]), let to = strkey(topics[2]),
                      drawers.contains(from) || drawers.contains(to),
                      // Comme le terminal, seule une valeur `i128` est un montant (une adresse M donne une map : ignorée).
                      case .i128(let parts)? = decode(event.value) else { return nil }
                return ActivityRecord(
                    id: id, event: .transfer, hash: event.transactionHash, from: from, to: to, assetCode: code,
                    amount: SACClient.amount(fromUnits: SACClient.decimal(parts)), at: at, isLocal: false, ledger: event.ledger
                )
            case ("clawback", 3):
                // Seulement un actif de la liste blanche (par l'adresse de son contrat), repris dans l'un des tiroirs.
                guard let code = assets[event.contractID], let from = strkey(topics[1]), drawers.contains(from),
                      case .i128(let parts)? = decode(event.value) else { return nil }
                return ActivityRecord(
                    id: id, event: .clawback, hash: event.transactionHash, from: from, to: "", assetCode: code,
                    amount: SACClient.amount(fromUnits: SACClient.decimal(parts)), at: at, isLocal: false, ledger: event.ledger
                )
            case ("card_added", 1):
                guard event.contractID == account, let key = cardKey(decode(event.value)) else { return nil }
                return ActivityRecord(
                    id: id, event: .cardAdded, hash: event.transactionHash, from: account, to: "", cardKey: key, at: at, isLocal: false,
                    ledger: event.ledger
                )
            default:
                return nil
            }
        }
    }

    /// Les lignes déjà gardées dont la transaction apparaît dans ces événements reçoivent son ledger (une ligne écrite
    /// par le téléphone ne le connaît pas encore).
    static func withLedgers(_ records: [ActivityRecord], from events: [SorobanClient.ContractEvent]) -> [ActivityRecord] {
        let ledgers = Dictionary(events.map { ($0.transactionHash, $0.ledger) }, uniquingKeysWith: { first, _ in first })
        return records.map { record in
            guard record.ledger == nil, let ledger = ledgers[record.hash] else { return record }
            var filled = record
            filled.ledger = ledger
            return filled
        }
    }

    private static func decode(_ base64: String) -> SCValXDR? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? SCValXDR(from: XDRDecoder(data: data))
    }

    private static func strkey(_ value: SCValXDR) -> String? {
        guard case .address(let address) = value else { return nil }
        return try? address.toStrKey()
    }

    /// Données de `CardAdded { key }` : une map `{ key: BytesN<65> }` (vérifié en simulant `add_card` sur testnet le
    /// 2026-09-30 ; la doc du contrat écrit `[key]`).
    private static func cardKey(_ value: SCValXDR?) -> String? {
        guard case .map(let entries)? = value,
              let entry = entries?.first(where: { if case .symbol("key") = $0.key { true } else { false } }),
              case .bytes(let bytes) = entry.val, bytes.count == 65 else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func closeDate(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601)
    }
}
