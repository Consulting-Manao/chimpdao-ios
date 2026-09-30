import Foundation

/// Un tiroir du compte, nommé comme sur le téléphone (glossaire, DESIGN_NOTES §1.2).
struct ActivityDrawer: Equatable, Identifiable, Sendable {
    let address: String
    /// Nom court des pastilles et des lignes : « Main », « Jungle ».
    let name: String
    /// Nom complet du reçu : « Main account », « Jungle's wallet ».
    let title: String
    let isMain: Bool

    var id: String { address }

    static func main(_ address: String) -> ActivityDrawer {
        ActivityDrawer(address: address, name: String(localized: "Main"), title: String(localized: "Main account"), isMain: true)
    }

    static func card(_ pocket: String, name: String) -> ActivityDrawer {
        ActivityDrawer(address: pocket, name: name, title: String(localized: "\(name)'s wallet"), isMain: false)
    }
}

/// Source de l'onglet Activity : `ChainActivityDataSource` (testnet) dans l'app, `MockActivityDataSource` au catalogue.
protocol ActivityDataSource: AnyObject {
    var network: StellarNetwork { get }
    /// Tiroirs du compte ouvert : Main d'abord, puis le wallet de chaque carte (noms du téléphone).
    func drawers() -> [ActivityDrawer]
    /// Nom local d'une carte (clé publique en hexadécimal), `nil` si ce téléphone ne la connaît pas.
    func cardName(key: String) -> String?
    /// Ce que le téléphone a déjà gardé : affiché tout de suite, sans réseau.
    func storedActivity() -> AccountActivity
    /// Relit la chaîne et enregistre ; `onProgress` reçoit l'historique après chaque tranche.
    func sync(onProgress: @escaping (AccountActivity) -> Void) async throws -> AccountActivity
    /// Paiement signé dont l'issue n'est pas encore certaine (`LocalWallet.pendingSend`).
    var pendingSend: PendingSend? { get }
    /// « Check again » du paiement en attente. Envoyé : écrit dans l'historique ; envoyé ou rien n'est parti : effacé du
    /// téléphone, comme le fait l'écran d'état d'Envoyer (issue certaine).
    func checkPending(_ pending: PendingSend) async throws -> PaymentCheck
    func explorerURL(transactionHash: String) -> URL?
}

/// Le vrai historique : fichier du téléphone + RPC de testnet (`ChainActivityHistory`), tiroirs d'après le téléphone
/// et la dernière lecture du Wallet (une carte ajoutée ailleurs n'est connue que par `cards()`).
final class ChainActivityDataSource: ActivityDataSource {
    let session: AppSession
    let config: ChimpNetworkConfig
    /// Cartes lues par le Wallet (clé, nom, wallet) : complètent celles du téléphone.
    private let walletCards: () -> [CardBalance]

    init(session: AppSession, config: ChimpNetworkConfig = .testnet, walletCards: @escaping () -> [CardBalance] = { [] }) {
        self.session = session
        self.config = config
        self.walletCards = walletCards
    }

    var network: StellarNetwork { config.network }

    func drawers() -> [ActivityDrawer] {
        guard let account = session.wallet.account else { return [] }
        var drawers = [ActivityDrawer.main(account.address)]
        var seen: Set<String> = [account.address]
        let read = walletCards()
        // Ordre du compte (`cards()`) quand le Wallet l'a lu, sinon celui du téléphone.
        let keys = read.isEmpty ? account.cards.map(\.publicKey) : read.map(\.id) + account.cards.map(\.publicKey)
        for key in keys {
            let saved = account.cards.first { $0.publicKey == key }
            let fromWallet = read.first { $0.id == key }
            guard let pocket = saved?.pocket ?? fromWallet?.pocket, !seen.contains(pocket) else { continue }
            seen.insert(pocket)
            drawers.append(.card(pocket, name: saved?.name ?? fromWallet?.name ?? String(localized: "Card")))
        }
        return drawers
    }

    func cardName(key: String) -> String? {
        session.wallet.account?.cards.first { $0.publicKey == key }?.name ?? walletCards().first { $0.id == key }?.name
    }

    func storedActivity() -> AccountActivity {
        guard let account = session.wallet.account?.address else { return AccountActivity() }
        return session.activity.activity(of: account)
    }

    func sync(onProgress: @escaping (AccountActivity) -> Void) async throws -> AccountActivity {
        guard let account = session.wallet.account?.address else { return AccountActivity() }
        let history = ChainActivityHistory(source: SorobanClient(config: config), assets: try SACClient.stellarAssets(config: config))
        let pockets = drawers().filter { !$0.isMain }.map(\.address)
        let store = session.activity
        /// Ce que la lecture a trouvé, ajouté au fichier tel qu'il est **maintenant** : une ligne écrite pendant la lecture
        /// (un envoi confirmé) n'est pas perdue.
        func save(_ state: AccountActivity) throws -> AccountActivity {
            var saved = state
            try store.update(account) { stored in
                stored.records = ActivityLog.combining(stored.records, state.records)
                stored.coverage = state.coverage
                saved = stored
            }
            return saved
        }
        let result = try await history.sync(account: account, drawers: pockets, activity: storedActivity()) { state in
            onProgress(try save(state))
        }
        return try save(result)
    }

    var pendingSend: PendingSend? { session.wallet.pendingSend }

    func checkPending(_ pending: PendingSend) async throws -> PaymentCheck {
        let result = try await ChainSendService(session: session, config: config).check(pending.trace)
        switch result {
        case .sent, .nothingSent:
            try? session.setPendingSend(nil)
        case .pending, .waiting, .undetermined:
            break
        }
        return result
    }

    func explorerURL(transactionHash: String) -> URL? {
        config.explorerURL(transactionHash: transactionHash)
    }
}

extension ActivityLog {
    /// Deux historiques du même compte réunis : une ligne par identifiant, et la ligne du téléphone l'emporte sur celle de
    /// la chaîne pour la même transaction.
    static func combining(_ first: [ActivityRecord], _ second: [ActivityRecord]) -> [ActivityRecord] {
        let merged = merging(first, second)
        let local = Set(merged.filter(\.isLocal).map(\.hash))
        return merged.filter { $0.isLocal || !local.contains($0.hash) }
    }
}

// MARK: Données factices (catalogue, simulateur)

/// Historique factice, daté par rapport à maintenant. Adresses fausses mais au format valide (celles de
/// `MockReceiveDataSource` et de `MockSendService`).
final class MockActivityDataSource: ActivityDataSource {
    enum Scenario: String, CaseIterable, Identifiable {
        /// Maquette : aujourd'hui, hier, plus ancien ; envoyé, reçu, Move, carte ajoutée.
        case standard
        /// Un paiement en attente en haut.
        case pending
        /// Une journée qui mêle XLM et USDC (total par actif).
        case mixedAssets
        /// Aucun mouvement.
        case empty
        /// Première lecture qui ne se termine pas.
        case loadingForever
        /// Erreur réseau sans rien de gardé.
        case networkError
        /// Lignes gardées, relecture en échec.
        case staleAfterRefresh

        var id: String { rawValue }
    }

    static let main = MockReceiveDataSource.mainAddress
    static let jungle = MockReceiveDataSource.jungleAddress
    static let banana = MockReceiveDataSource.bananaAddress
    static let maya = MockSendService.mayaAddress
    static let shop = MockSendService.tomAddress
    static let leafKey = "04" + String(repeating: "1a", count: 64)
    static let bananaKey = "04" + String(repeating: "2b", count: 64)

    let scenario: Scenario
    let network = StellarNetwork.testnet
    private let now: Date
    private var syncCount = 0
    private(set) var pendingSend: PendingSend?

    init(scenario: Scenario, now: Date = .now) {
        self.scenario = scenario
        self.now = now
        if scenario == .pending {
            pendingSend = PendingSend(
                trace: PaymentTrace(
                    token: "mock", from: Self.main, destination: Self.maya, units: 250_000_000, nonce: 1,
                    preparedAtLedger: 1, expirationLedger: 121, transactionHash: "pending", transactionMaxTime: nil
                ),
                recipient: Self.maya, recipientName: nil, drawerTitle: String(localized: "Main account"), asset: SendAsset.usdc.rawValue,
                amount: 25, signedAt: now.addingTimeInterval(-120)
            )
        }
    }

    func drawers() -> [ActivityDrawer] {
        [.main(Self.main), .card(Self.jungle, name: "Jungle"), .card(Self.banana, name: "Banana")]
    }

    func cardName(key: String) -> String? {
        switch key {
        case Self.leafKey: "Leaf"
        case Self.bananaKey: "Banana"
        default: nil
        }
    }

    func storedActivity() -> AccountActivity {
        scenario == .staleAfterRefresh ? AccountActivity(records: records) : AccountActivity()
    }

    func sync(onProgress: @escaping (AccountActivity) -> Void) async throws -> AccountActivity {
        syncCount += 1
        switch scenario {
        case .loadingForever:
            try await Task.sleep(for: .seconds(3600))
            return AccountActivity()
        case .networkError, .staleAfterRefresh:
            try await Task.sleep(for: .milliseconds(600))
            throw StellarError.rpc("The Internet connection appears to be offline.")
        case .empty:
            try await Task.sleep(for: .milliseconds(600))
            return AccountActivity()
        case .standard, .pending, .mixedAssets:
            try await Task.sleep(for: .milliseconds(600))
            return AccountActivity(records: records)
        }
    }

    func checkPending(_ pending: PendingSend) async throws -> PaymentCheck {
        try await Task.sleep(for: .milliseconds(300))
        return .waiting(untilLedger: 121, estimatedEnd: now.addingTimeInterval(8 * 60))
    }

    func explorerURL(transactionHash: String) -> URL? {
        ChimpNetworkConfig.testnet.explorerURL(transactionHash: transactionHash)
    }

    /// Les lignes de la maquette (I1), sur nos tiroirs factices.
    private var records: [ActivityRecord] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func at(_ daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            return min(now, calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!)
        }
        func transfer(_ id: String, _ from: String, _ to: String, _ code: String, _ amount: String, _ date: Date, local: Bool = false) -> ActivityRecord {
            ActivityRecord(
                id: "stellar:\(id)", event: .transfer, hash: id, from: from, to: to, assetCode: code,
                amount: Decimal(string: amount)!, at: date, isLocal: local
            )
        }
        var rows = [
            transfer("t1", Self.jungle, Self.maya, "USDC", "25", at(0, 14, 2), local: true),
            transfer("t2", Self.main, Self.jungle, "USDC", "50", at(0, 11, 20), local: true),
            transfer("t3", Self.shop, Self.main, "USDC", "0.12", at(0, 9, 0)),
            transfer("y1", Self.shop, Self.main, "USDC", "12.5", at(1, 16, 5)),
            ActivityRecord(
                id: "stellar:y2", event: .cardAdded, hash: "y2", from: Self.main, to: "", cardKey: Self.leafKey,
                approvedBy: Self.bananaKey, at: at(1, 12, 15), isLocal: true
            ),
            transfer("o1", Self.maya, Self.banana, "XLM", "1000", at(3, 10, 30)),
        ]
        if scenario == .mixedAssets {
            rows.append(transfer("t4", Self.main, Self.shop, "XLM", "0.5", at(0, 8, 45)))
            rows.append(transfer("t5", Self.maya, Self.jungle, "XLM", "1757.5", at(0, 8, 10)))
        }
        return rows.sorted { $0.at > $1.at }
    }
}
