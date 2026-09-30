import Foundation

/// Une ligne de l'historique. Portage de `ActivityRecord` (`reference/terminal/src/chain/types.ts`), réduit à Stellar et
/// aux mouvements du wallet. **Aucun secret** : des adresses publiques, des montants et des hash, comme sur la chaîne.
struct ActivityRecord: Codable, Equatable, Identifiable, Sendable {
    enum Event: String, Codable, Sendable {
        /// `transfer` d'un SAC (XLM, USDC) : envoi, réception ou Move selon les tiroirs du compte.
        case transfer
        /// `card_added` du Main account : une carte est entrée dans le compte (`add_card`).
        case cardAdded
    }

    /// Lue sur la chaîne : `stellar:<hash>:<id de l'événement>` (comme le terminal). Écrite par ce téléphone :
    /// `stellar:<hash>` (`recordPayment`, `recordNft`).
    var id: String
    var event: Event
    var hash: String
    /// `transfer` : expéditeur et destinataire exacts (un destinataire M écrit par ce téléphone reste une adresse M).
    /// `cardAdded` : `from` est le Main account, `to` est vide.
    var from: String
    var to: String
    /// Code de l'actif (« XLM », « USDC ») et montant dans l'unité de l'actif ; `nil` pour une carte ajoutée.
    var assetCode: String?
    var amount: Decimal?
    /// `cardAdded` : clé publique de la carte entrée (hexadécimal) et, pour un ajout fait sur ce téléphone, celle de la
    /// carte du compte qui a dit oui.
    var cardKey: String?
    var approvedBy: String?
    /// Heure de fermeture du ledger (chaîne) ou heure de la confirmation (téléphone).
    var at: Date
    /// Écrite par ce téléphone : elle fait foi sur la ligne lue sur la chaîne pour la même transaction.
    var isLocal: Bool
    /// Ledger où la transaction a été incluse : « N° » du reçu (I1.1d). Une ligne écrite par ce téléphone le reçoit à
    /// la lecture suivante de la chaîne. Optionnel : les fichiers écrits avant restent lisibles.
    var ledger: UInt32? = nil

    /// Ce que la ligne représente pour ce compte. `classifyTransfer` du terminal (`lib/chain-history.ts`), sans les
    /// protocoles DeFi (hors V1), plus **Move** : les deux côtés sont des tiroirs du compte (DESIGN_NOTES §13).
    /// `nil` : aucun côté n'est un tiroir actuel du compte (par exemple le wallet d'une carte retirée).
    func kind(drawers: Set<String>) -> ActivityKind? {
        switch event {
        case .cardAdded:
            return .cardAdded
        case .transfer:
            let sent = drawers.contains(from)
            let received = drawers.contains(to)
            switch (sent, received) {
            case (true, true): return .moved
            case (true, false): return .sent
            case (false, true): return .received
            case (false, false): return nil
            }
        }
    }
}

extension ActivityRecord {
    /// `recordPayment` du terminal : un envoi ou un Move confirmé sur la chaîne, écrit par ce téléphone. `to` est
    /// l'adresse exacte payée (G, M ou C).
    static func payment(hash: String, from: String, to: String, assetCode: String, amount: Decimal, at: Date = .now) -> ActivityRecord {
        ActivityRecord(
            id: "stellar:\(hash)", event: .transfer, hash: hash, from: from, to: to, assetCode: assetCode, amount: amount,
            at: at, isLocal: true
        )
    }

    /// `recordNft` du terminal, pour une carte entrée dans le compte (`add_card` confirmé), avec la carte qui a dit oui.
    static func cardAdded(hash: String, account: String, cardKey: String, approvedBy: String?, at: Date = .now) -> ActivityRecord {
        ActivityRecord(
            id: "stellar:\(hash)", event: .cardAdded, hash: hash, from: account, to: "", cardKey: cardKey, approvedBy: approvedBy,
            at: at, isLocal: true
        )
    }
}

/// Nature d'une ligne pour le compte affiché.
enum ActivityKind: Equatable, Sendable {
    case sent
    case received
    case moved
    case cardAdded
}

/// Ce que le téléphone garde de l'historique d'un compte.
struct AccountActivity: Codable, Equatable, Sendable {
    /// Les plus récentes d'abord, `ActivityLog.maximum` au plus.
    var records: [ActivityRecord] = []
    /// Ledgers déjà relus sur la chaîne pour ces tiroirs (adaptation à l'iPhone, DESIGN_NOTES §13 : le RPC public met
    /// jusqu'à 2 minutes à relire 7 jours ; on ne relit que ce qui manque).
    var coverage: ActivityCoverage?
}

/// Fenêtre de ledgers déjà relue, d'un seul tenant, pour un ensemble de tiroirs. Vide quand `fromLedger > toLedger`.
struct ActivityCoverage: Codable, Equatable, Sendable {
    /// Adresses relues (Main account et wallets des cartes), triées : une carte de plus oblige à tout relire.
    var addresses: [String]
    var fromLedger: UInt32
    var toLedger: UInt32
}

/// Historique de tous les comptes ouverts un jour sur ce téléphone, rangé par adresse du Main account.
struct ActivityLog: Codable, Equatable, Sendable {
    static let currentVersion = 1
    /// `MAX` de `lib/history.ts` : au-delà, les lignes les plus anciennes sont oubliées.
    static let maximum = 200

    var version = ActivityLog.currentVersion
    var accounts: [String: AccountActivity] = [:]

    /// `mergeRecords` : une seule ligne par identifiant (la nouvelle remplace l'ancienne), les plus récentes d'abord,
    /// `maximum` au plus.
    static func merging(_ existing: [ActivityRecord], _ incoming: [ActivityRecord], maximum: Int = ActivityLog.maximum) -> [ActivityRecord] {
        var byID: [String: ActivityRecord] = [:]
        var order: [String] = []
        for record in existing + incoming {
            if byID[record.id] == nil { order.append(record.id) }
            byID[record.id] = record
        }
        let merged = order.compactMap { byID[$0] }
        return Array(merged.sorted { $0.at > $1.at }.prefix(maximum))
    }

    /// Ligne écrite par ce téléphone (envoi, Move ou carte ajoutée confirmés) : elle remplace toute ligne de la chaîne
    /// pour la même transaction (« locally recorded ops stay authoritative »).
    static func recordingLocal(_ record: ActivityRecord, into records: [ActivityRecord]) -> [ActivityRecord] {
        merging(records.filter { $0.hash != record.hash }, [record])
    }
}

/// Lecture et écriture de l'`ActivityLog`.
protocol ActivityStore: AnyObject {
    func load() throws -> ActivityLog
    func save(_ log: ActivityLog) throws
    /// « Erase everything on this phone » : l'historique de tous les comptes disparaît du téléphone.
    func erase() throws
}

extension ActivityStore {
    /// Historique d'un compte (vide s'il n'a jamais été lu). Un fichier illisible donne un historique vide : la chaîne
    /// redonne les 7 derniers jours.
    func activity(of account: String) -> AccountActivity {
        (try? load())?.accounts[account] ?? AccountActivity()
    }

    func update(_ account: String, _ change: (inout AccountActivity) -> Void) throws {
        var log = (try? load()) ?? ActivityLog()
        var activity = log.accounts[account] ?? AccountActivity()
        change(&activity)
        log.accounts[account] = activity
        try save(log)
    }

    /// Enregistre une ligne écrite par ce téléphone (`addActivity(recordPayment(…))`). Un échec d'écriture n'empêche rien :
    /// l'argent est parti, et la ligne reviendra de la chaîne (« a sale that can't be logged still went through »).
    func recordLocal(_ record: ActivityRecord, account: String) {
        try? update(account) { $0.records = ActivityLog.recordingLocal(record, into: $0.records) }
    }
}

/// Un fichier JSON dans Application Support (`activity-testnet.json`), à côté de celui du wallet, avec la même protection
/// (`NSFileProtectionComplete`). Séparé du `LocalWallet` comme dans le terminal (`chimp.activity.v1`), pour qu'une ligne
/// d'historique ne puisse jamais abîmer le compte.
final class FileActivityStore: ActivityStore {
    let fileURL: URL

    init(network: StellarNetwork, directory: URL? = nil) throws {
        let base = try directory ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let folder = base.appending(path: "ChimpDAO", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appending(path: "activity-\(network.rawValue).json")
    }

    /// Fichier absent ou illisible : un historique vide (un fichier illisible est mis de côté, comme celui du wallet).
    func load() throws -> ActivityLog {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return ActivityLog() }
        let data = try Data(contentsOf: fileURL)
        do {
            let log = try FileLocalWalletStore.decoder.decode(ActivityLog.self, from: data)
            guard log.version == ActivityLog.currentVersion else { throw CocoaError(.fileReadCorruptFile) }
            return log
        } catch {
            let aside = fileURL.appendingPathExtension("unreadable")
            try? FileManager.default.removeItem(at: aside)
            try FileManager.default.moveItem(at: fileURL, to: aside)
            return ActivityLog()
        }
    }

    func save(_ log: ActivityLog) throws {
        try FileLocalWalletStore.encoder.encode(log).write(to: fileURL, options: FileLocalWalletStore.writingOptions)
    }

    /// Supprime le fichier et sa copie mise de côté (`.unreadable`).
    func erase() throws {
        for url in [fileURL, fileURL.appendingPathExtension("unreadable")] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

/// Stockage en mémoire, pour les tests, le catalogue et le simulateur.
final class InMemoryActivityStore: ActivityStore, @unchecked Sendable {
    private(set) var log: ActivityLog
    private(set) var saveCount = 0

    init(_ log: ActivityLog = ActivityLog()) {
        self.log = log
    }

    func load() throws -> ActivityLog { log }

    func save(_ log: ActivityLog) throws {
        self.log = log
        saveCount += 1
    }

    func erase() throws {
        log = ActivityLog()
    }
}
