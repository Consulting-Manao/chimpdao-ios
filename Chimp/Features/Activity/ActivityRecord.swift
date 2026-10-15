import Foundation

/// Une ligne de l'historique. Portage de `ActivityRecord` (`reference/terminal/src/chain/types.ts`), réduit à Stellar et
/// aux mouvements du wallet. **Aucun secret** : des adresses publiques, des montants et des hash, comme sur la chaîne.
struct ActivityRecord: Codable, Equatable, Identifiable, Sendable {
    enum Event: String, Codable, Sendable {
        /// `transfer` d'un SAC (XLM, USDC) : envoi, réception ou Move selon les tiroirs du compte.
        case transfer
        /// `card_added` du Main account : une carte est entrée dans le compte (`add_card`).
        case cardAdded
        /// Swap dans un tiroir (tranche 2) : `from` est le tiroir, `to` le contrat qui a reçu ce qui est parti (paire),
        /// `assetCode`/`amount` ce qui est parti, `receivedAssetCode`/`receivedAmount` ce qui est arrivé.
        case swap
        /// Dépôt dans un vault (tranche 2, D1) : `from` est le tiroir, `to` le vault, `assetCode`/`amount` ce qui est entré
        /// dans le vault, `shares` les parts reçues (si connues).
        case vaultDeposit
        /// Retrait d'un vault : `from` est le vault, `to` le tiroir, `assetCode`/`amount` ce qui est revenu, `shares` les
        /// parts rendues (si connues).
        case vaultWithdraw
        /// `clawback` d'un SAC (stablebond, tranche 2, D3) : l'émetteur a repris des jetons. `from` est le tiroir, `to`
        /// est vide, `assetCode`/`amount` ce qui a été repris.
        case clawback
        /// Arrivée d'USDC depuis une autre blockchain par Circle CCTP (tranche 2, D4) : `from` est le `CctpForwarder`,
        /// `to` le tiroir, `assetCode`/`amount` ce qui est arrivé ; `sourceChain`, `sourceAddress`, `bridgeFee` lus dans
        /// le message attesté, s'il a pu être relu et qu'il désigne bien ce tiroir.
        case bridgeArrival
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
    /// Swap : ce qui est arrivé (code et quantité exacte), le minimum que la carte avait signé et le protocole, connus
    /// seulement pour un swap fait sur ce téléphone (un swap relu sur la chaîne n'a que les deux transferts).
    /// Optionnels : les fichiers écrits avant restent lisibles.
    var receivedAssetCode: String? = nil
    var receivedAmount: Decimal? = nil
    var minimumReceived: Decimal? = nil
    var protocolName: String? = nil
    /// Vault (dépôt, retrait) : parts reçues ou rendues, et nom du vault (« DeFindex XLM »). `protocolName` porte alors
    /// la chaîne des protocoles (« DeFindex → Blend »). Optionnels : les fichiers écrits avant restent lisibles.
    var shares: Decimal? = nil
    var vaultName: String? = nil
    /// Swap vers un stablebond (CETES) fait sur ce téléphone : prix indicatif d'Etherfuse d'un jeton reçu, en dollars,
    /// au moment du swap (décision de Barth du 2026-10-15 : base de « Price +0.62% since you got them »). Jamais signé,
    /// jamais tiré d'un pool ; `nil` si le prix n'était pas disponible. Optionnel : les fichiers écrits avant restent lisibles.
    var receivedPriceUSD: Decimal? = nil
    /// Arrivée CCTP : chaîne d'origine (« Ethereum »), adresse qui a envoyé (« 0x… »), frais pris par Circle (USDC).
    /// Optionnels : les fichiers écrits avant restent lisibles.
    var sourceChain: String? = nil
    var sourceAddress: String? = nil
    var bridgeFee: Decimal? = nil

    /// Ce que la ligne représente pour ce compte. `classifyTransfer` du terminal (`lib/chain-history.ts`), sans les
    /// protocoles DeFi (hors V1), plus **Move** : les deux côtés sont des tiroirs du compte (DESIGN_NOTES §13).
    /// `nil` : aucun côté n'est un tiroir actuel du compte (par exemple le wallet d'une carte retirée).
    func kind(drawers: Set<String>) -> ActivityKind? {
        switch event {
        case .cardAdded:
            return .cardAdded
        case .swap:
            return drawers.contains(from) ? .swapped : nil
        case .vaultDeposit:
            return drawers.contains(from) ? .deposited : nil
        case .vaultWithdraw:
            return drawers.contains(to) ? .withdrawn : nil
        case .clawback:
            return drawers.contains(from) ? .takenBack : nil
        case .bridgeArrival:
            return drawers.contains(to) ? .arrived : nil
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

    /// Un swap confirmé, écrit par ce téléphone : ce qui est parti, ce qui est arrivé (quantité rendue par le router), le
    /// minimum signé et le protocole.
    static func swap(
        hash: String, drawer: String, venue: String, givenCode: String, given: Decimal, receivedCode: String, received: Decimal?,
        minimum: Decimal?, protocolName: String?, at: Date = .now, receivedPriceUSD: Decimal? = nil
    ) -> ActivityRecord {
        ActivityRecord(
            id: "stellar:\(hash)", event: .swap, hash: hash, from: drawer, to: venue, assetCode: givenCode, amount: given,
            at: at, isLocal: true, receivedAssetCode: receivedCode, receivedAmount: received, minimumReceived: minimum,
            protocolName: protocolName, receivedPriceUSD: receivedPriceUSD
        )
    }

    /// Un transfert relu sur la chaîne, du `CctpForwarder` vers un tiroir, est une arrivée CCTP (« ARRIVED ») et non un
    /// paiement reçu : on ne « renvoie » pas à un contrat de Circle.
    static func classifyingArrivals(_ records: [ActivityRecord], forwarder: String?, drawers: Set<String>) -> [ActivityRecord] {
        guard let forwarder else { return records }
        return records.map { record in
            guard record.event == .transfer, !record.isLocal, record.from == forwarder, drawers.contains(record.to) else { return record }
            var arrival = record
            arrival.event = .bridgeArrival
            arrival.protocolName = "Circle CCTP"
            return arrival
        }
    }

    /// Les détails d'une arrivée, tirés du message attesté que la transaction a passé à `mint_and_forward` — seulement si
    /// ce message désigne bien cette arrivée : arrivée sur Stellar, `mintRecipient` et `destinationCaller` = le forwarder,
    /// destinataire du hook data = ce tiroir, même montant. Sinon, la ligne reste sans détails.
    func withArrivalDetails(from message: CCTPMessage, cctp: IntegrationConfig.CCTP) -> ActivityRecord {
        guard event == .bridgeArrival, message.destinationDomain == cctp.localDomain,
              let forwarder = try? CCTPMessage.bytes32(contract: cctp.forwarder),
              message.burn.mintRecipient == forwarder, message.destinationCaller == forwarder,
              (try? CCTPMessage.forwardRecipient(in: message.burn.hookData)) == to,
              amount == CCTPMessage.stellarAmount(message.burn.amount - message.burn.feeExecuted) else { return self }
        var detailed = self
        detailed.sourceChain = cctp.sourceChains[message.sourceDomain]
        detailed.sourceAddress = CCTPMessage.evmAddress(message.burn.messageSender)
        detailed.bridgeFee = CCTPMessage.stellarAmount(message.burn.feeExecuted)
        return detailed
    }

    /// Les deux transferts d'un swap relus sur la chaîne deviennent une seule ligne : dans une même transaction, un actif
    /// **sort** d'un tiroir et un autre actif **y entre**, et l'autre partie n'est pas un tiroir (ce n'est pas un Move).
    /// Toute autre transaction reste telle quelle. Le protocole et le minimum ne sont pas connus.
    static func groupingSwaps(_ records: [ActivityRecord], drawers: Set<String>) -> [ActivityRecord] {
        var byHash: [String: [ActivityRecord]] = [:]
        for record in records where record.event == .transfer && !record.isLocal {
            byHash[record.hash, default: []].append(record)
        }
        var merged: [String: ActivityRecord] = [:]
        for (hash, group) in byHash where group.count == 2 {
            guard let out = group.first(where: { drawers.contains($0.from) && !drawers.contains($0.to) }),
                  let into = group.first(where: { drawers.contains($0.to) && !drawers.contains($0.from) }),
                  out.from == into.to, out.assetCode != into.assetCode else { continue }
            var swap = ActivityRecord(
                id: "stellar:\(hash):swap", event: .swap, hash: hash, from: out.from, to: out.to, assetCode: out.assetCode,
                amount: out.amount, at: out.at, isLocal: false, ledger: out.ledger
            )
            swap.receivedAssetCode = into.assetCode
            swap.receivedAmount = into.amount
            merged[hash] = swap
        }
        guard !merged.isEmpty else { return records }
        var result: [ActivityRecord] = []
        var emitted: Set<String> = []
        for record in records {
            if let swap = merged[record.hash], record.event == .transfer {
                if emitted.insert(record.hash).inserted { result.append(swap) }
            } else {
                result.append(record)
            }
        }
        return result
    }

    /// Un vault connu de l'app : son nom affiché et la chaîne de ses protocoles (« DeFindex → Blend »).
    struct VaultLabel: Equatable, Sendable {
        let name: String
        let protocols: String
    }

    /// Un dépôt confirmé dans un vault, écrit par ce téléphone.
    static func vaultDeposit(
        hash: String, drawer: String, vault: String, label: VaultLabel, assetCode: String, amount: Decimal, shares: Decimal?, at: Date = .now
    ) -> ActivityRecord {
        var record = ActivityRecord(
            id: "stellar:\(hash)", event: .vaultDeposit, hash: hash, from: drawer, to: vault, assetCode: assetCode, amount: amount,
            at: at, isLocal: true
        )
        record.protocolName = label.protocols
        record.vaultName = label.name
        record.shares = shares
        return record
    }

    /// Un retrait confirmé d'un vault, écrit par ce téléphone : ce qui est revenu (`nil` si illisible) et les parts rendues.
    static func vaultWithdraw(
        hash: String, drawer: String, vault: String, label: VaultLabel, assetCode: String, received: Decimal?, shares: Decimal?, at: Date = .now
    ) -> ActivityRecord {
        var record = ActivityRecord(
            id: "stellar:\(hash)", event: .vaultWithdraw, hash: hash, from: vault, to: drawer, assetCode: assetCode, amount: received,
            at: at, isLocal: true
        )
        record.protocolName = label.protocols
        record.vaultName = label.name
        record.shares = shares
        return record
    }

    /// Les transferts relus sur la chaîne entre un tiroir et un vault connu deviennent des dépôts et des retraits : vers le
    /// vault, un dépôt ; depuis le vault, un retrait. Les parts ne sont pas connues (seul le transfert de l'actif est lu).
    static func classifyingVaults(_ records: [ActivityRecord], vaults: [String: VaultLabel], drawers: Set<String>) -> [ActivityRecord] {
        guard !vaults.isEmpty else { return records }
        return records.map { record in
            guard record.event == .transfer, !record.isLocal else { return record }
            var classified = record
            if drawers.contains(record.from), let label = vaults[record.to] {
                classified.event = .vaultDeposit
                classified.protocolName = label.protocols
                classified.vaultName = label.name
            } else if drawers.contains(record.to), let label = vaults[record.from] {
                classified.event = .vaultWithdraw
                classified.protocolName = label.protocols
                classified.vaultName = label.name
            }
            return classified
        }
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
    /// Un actif échangé contre un autre dans le même tiroir.
    case swapped
    /// Mis dans un vault (Grow), retiré d'un vault.
    case deposited
    case withdrawn
    /// L'émetteur d'un stablebond a repris des jetons (clawback).
    case takenBack
    /// De l'USDC arrivé d'une autre blockchain (Circle CCTP).
    case arrived
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
