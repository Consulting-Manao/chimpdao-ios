import Foundation
import Observation
import SwiftUI

/// Tampon d'une ligne du ticket (textes validés par Barth le 2026-09-30).
enum ActivityStamp: Equatable, Sendable {
    case paid
    case gotIt
    case moved
    case newCard
    case pending
    /// Maquette I1s : « SWAPPED ».
    case swapped
}

/// Montant coloré (reçu) ou neutre.
enum ActivityTone: Equatable, Sendable {
    case positive
    case negative
    case neutral
}

/// Une ligne du ticket, prête à afficher.
struct ActivityRow: Identifiable, Equatable {
    let id: String
    let title: String
    /// « 14:02 · from Jungle ».
    let meta: String
    let stamp: ActivityStamp
    /// Montant signé (« −$25.00 », « +1,000 XLM », « 50 USDC » pour un Move) ; `nil` pour une carte ajoutée.
    let amount: String?
    let tone: ActivityTone
    /// La ligne d'origine (reçu) ; `nil` pour le paiement en attente (il ouvre l'écran d'état d'Envoyer).
    let record: ActivityRecord?
    /// Swap : ce qui est arrivé (« +99.71 USDC »), sous ce qui est parti.
    var secondaryAmount: String? = nil
}

/// Un ticket : une journée (ou le paiement en attente, en haut).
struct ActivityTicket: Identifiable, Equatable {
    let id: String
    /// « TODAY », « YESTERDAY », « MONDAY » (majuscules à l'affichage).
    let title: String
    /// « SEP 30 » selon la région du téléphone.
    let date: String
    let rows: [ActivityRow]
    /// Total du jour pour ce qui est affiché ; `nil` s'il n'y a eu aucun montant (carte ajoutée seulement, en attente).
    let net: String?
    let netTone: ActivityTone
    /// Le paiement en attente n'est pas encore « Chimpy-certified ».
    let isPending: Bool
}

/// ViewModel de l'onglet Activity (I1) : l'historique gardé sur le téléphone s'affiche tout de suite, la chaîne est relue
/// derrière (tirer pour rafraîchir). Ne fait aucune crypto et ne connaît que `ActivityDataSource`.
@Observable
final class ActivityViewModel {
    enum Phase: Equatable {
        /// Rien de gardé, première lecture en cours.
        case loading
        /// Lignes affichées (éventuellement anciennes si la dernière lecture a échoué).
        case loaded
        /// Rien de gardé et la lecture a échoué.
        case failed
    }

    /// Filtre du haut : tous les tiroirs, ou un seul (adresse).
    enum Filter: Hashable {
        case all
        case drawer(String)
    }

    /// Issue du paiement en attente, telle que la dernière vérification l'a vue.
    enum PendingStatus: Equatable {
        case checking
        case notConfirmed
        case waiting(until: Date)
        case unknown
    }

    private(set) var phase: Phase = .loading
    private(set) var records: [ActivityRecord] = []
    private(set) var drawers: [ActivityDrawer] = []
    /// Lecture de la chaîne en cours (les lignes déjà trouvées s'affichent au fur et à mesure).
    private(set) var isSyncing = false
    /// La dernière lecture a échoué alors que des lignes plus anciennes sont affichées.
    private(set) var isShowingStaleData = false
    private(set) var pending: PendingSend?
    private(set) var pendingStatus: PendingStatus = .checking
    var filter: Filter = .all
    /// Ligne touchée : son reçu est ouvert.
    var selectedRecord: ActivityRecord?

    let source: ActivityDataSource
    private let calendar: Calendar
    private let now: () -> Date

    init(source: ActivityDataSource, calendar: Calendar = .current, now: @escaping () -> Date = { .now }) {
        self.source = source
        self.calendar = calendar
        self.now = now
    }

    var network: StellarNetwork { source.network }

    /// Lecture en cours, détachée de l'écran : SwiftUI annule les tâches de `.task` et `.refreshable` (onglet quitté,
    /// pastille touchée pendant le rafraîchissement) ; la lecture, elle, va au bout et enregistre ce qu'elle trouve.
    private var syncTask: Task<Void, Never>?

    /// À chaque affichage de l'onglet et « tirer pour rafraîchir » : ce qui est gardé tout de suite, puis ce qui manque
    /// de la chaîne (en général une seule requête). Une lecture déjà en cours est attendue, jamais doublée.
    func refresh() async {
        if let syncTask {
            await syncTask.value
            return
        }
        let task = Task { await self.performRefresh() }
        syncTask = task
        await task.value
        syncTask = nil
    }

    private func performRefresh() async {
        drawers = source.drawers()
        if case .drawer(let address) = filter, !drawers.contains(where: { $0.address == address }) { filter = .all }
        let stored = source.storedActivity()
        if !stored.records.isEmpty || !records.isEmpty {
            records = ActivityLog.combining(records, stored.records)
            phase = .loaded
        } else if phase != .loaded {
            phase = .loading
        }
        isSyncing = true
        defer { isSyncing = false }
        async let pendingCheck: Void = checkPending()
        do {
            let result = try await source.sync { [weak self] progress in
                guard let self else { return }
                records = progress.records
                if !records.isEmpty { phase = .loaded }
            }
            records = result.records
            isShowingStaleData = false
            phase = .loaded
        } catch is CancellationError {
            // Onglet quitté : on garde l'état actuel.
        } catch {
            if records.isEmpty {
                phase = .failed
            } else {
                isShowingStaleData = true
                phase = .loaded
            }
        }
        await pendingCheck
    }

    /// Le paiement en attente : sa dernière issue connue. Envoyé ou rien n'est parti : il disparaît (et l'envoi apparaît
    /// dans l'historique).
    private func checkPending() async {
        pending = source.pendingSend
        guard let pending else { return }
        pendingStatus = .checking
        do {
            switch try await source.checkPending(pending) {
            case .sent:
                self.pending = nil
                records = ActivityLog.combining(records, source.storedActivity().records)
            case .nothingSent:
                self.pending = nil
            case .pending:
                pendingStatus = .notConfirmed
            case .waiting(_, let end):
                pendingStatus = .waiting(until: end)
            case .undetermined:
                pendingStatus = .unknown
            }
        } catch {
            pendingStatus = .unknown
        }
    }

    // MARK: Affichage

    /// Tickets affichés pour le filtre choisi : le paiement en attente d'abord, puis une journée par ticket.
    var tickets: [ActivityTicket] { tickets(for: filter) }

    /// Tickets d'un filtre donné, sans toucher au filtre de l'onglet (historique d'un tiroir, B2 et B3).
    func tickets(for filter: Filter) -> [ActivityTicket] {
        var tickets: [ActivityTicket] = []
        if let pendingTicket = pendingTicket(for: filter) { tickets.append(pendingTicket) }
        return tickets + Self.tickets(for: visibleRecords(for: filter), filter: filter, drawers: drawers, cardName: { [source] in source.cardName(key: $0) }, calendar: calendar, now: now())
    }

    /// Lignes du filtre choisi, parmi celles qui concernent un tiroir actuel du compte.
    var visibleRecords: [ActivityRecord] { visibleRecords(for: filter) }

    func visibleRecords(for filter: Filter) -> [ActivityRecord] {
        Self.filtered(records, filter: filter, drawers: drawers)
    }

    /// Rien à montrer pour ce filtre, lecture finie.
    var isEmpty: Bool { isEmpty(for: filter) }

    func isEmpty(for filter: Filter) -> Bool {
        phase == .loaded && !isSyncing && visibleRecords(for: filter).isEmpty && pendingTicket(for: filter) == nil
    }

    static func filtered(_ records: [ActivityRecord], filter: Filter, drawers: [ActivityDrawer]) -> [ActivityRecord] {
        let addresses = Set(drawers.map(\.address))
        return records.filter { record in
            guard record.kind(drawers: addresses) != nil else { return false }
            switch filter {
            case .all:
                return true
            case .drawer(let address):
                if record.event == .cardAdded { return drawers.first { $0.address == address }?.isMain == true }
                return record.from == address || record.to == address
            }
        }
    }

    private func pendingTicket(for filter: Filter) -> ActivityTicket? {
        guard let pending else { return nil }
        let addresses = Set(drawers.map(\.address))
        if case .drawer(let address) = filter, pending.trace.from != address, pending.trace.destination != address { return nil }
        let isMove = addresses.contains(pending.trace.destination)
        let to = drawers.first { $0.address == pending.trace.destination }
        let given = SendAsset(rawValue: pending.asset)?.code ?? pending.asset
        let title = if let swap = pending.swap {
            String(localized: "Swapping \(given) for \(SendAsset(rawValue: swap.receivedAsset)?.code ?? swap.receivedAsset)")
        } else if isMove {
            String(localized: "Moving to \(to?.title ?? StellarAddressParser.short(pending.recipient))")
        } else {
            String(localized: "Paying \(pending.recipientName ?? StellarAddressParser.short(pending.recipient))")
        }
        let time = pending.signedAt.formatted(date: .omitted, time: .shortened)
        let row = ActivityRow(
            id: "pending", title: title, meta: "\(time) · \(Self.statusText(pendingStatus))", stamp: .pending,
            amount: pending.swap != nil
                ? Self.quantityText(pending.amount, code: given, sign: .negative)
                : Self.amountText(pending.amount, code: given, sign: isMove ? nil : .negative),
            tone: .neutral, record: nil
        )
        return ActivityTicket(
            id: "pending", title: String(localized: "Waiting"), date: Self.dateText(pending.signedAt), rows: [row],
            net: nil, netTone: .neutral, isPending: true
        )
    }

    static func statusText(_ status: PendingStatus) -> String {
        switch status {
        case .checking: String(localized: "Checking…")
        case .notConfirmed: String(localized: "Not confirmed yet")
        case .waiting(let end): String(localized: "Wait until \(end.formatted(date: .omitted, time: .shortened))")
        case .unknown: String(localized: "Can't tell yet")
        }
    }

    // MARK: Tickets (fonctions pures, testées)

    static func tickets(
        for records: [ActivityRecord],
        filter: Filter,
        drawers: [ActivityDrawer],
        cardName: (String) -> String?,
        calendar: Calendar,
        now: Date
    ) -> [ActivityTicket] {
        let addresses = Set(drawers.map(\.address))
        var days: [(day: Date, records: [ActivityRecord])] = []
        for record in records.sorted(by: { $0.at > $1.at }) {
            let day = calendar.startOfDay(for: record.at)
            if days.last?.day == day {
                days[days.count - 1].records.append(record)
            } else {
                days.append((day, [record]))
            }
        }
        return days.map { day, records in
            let rows = records.compactMap { row(for: $0, drawers: drawers, addresses: addresses, cardName: cardName) }
            let net = net(of: records, filter: filter, addresses: addresses)
            return ActivityTicket(
                id: "\(day.timeIntervalSince1970)", title: dayTitle(day, calendar: calendar, now: now), date: dateText(day),
                rows: rows, net: net?.text, netTone: net?.tone ?? .neutral, isPending: false
            )
        }
    }

    static func row(for record: ActivityRecord, drawers: [ActivityDrawer], addresses: Set<String>, cardName: (String) -> String?) -> ActivityRow? {
        guard let kind = record.kind(drawers: addresses) else { return nil }
        func drawer(_ address: String) -> ActivityDrawer? { drawers.first { $0.address == address } }
        let time = record.at.formatted(date: .omitted, time: .shortened)
        let code = record.assetCode ?? ""
        switch kind {
        case .sent:
            return ActivityRow(
                id: record.id, title: String(localized: "You paid \(StellarAddressParser.short(record.to))"),
                meta: "\(time) · " + String(localized: "from \(drawer(record.from)?.name ?? "")"), stamp: .paid,
                amount: record.amount.map { amountText($0, code: code, sign: .negative) }, tone: .neutral, record: record
            )
        case .received:
            return ActivityRow(
                id: record.id, title: String(localized: "\(StellarAddressParser.short(record.from)) paid you"),
                meta: "\(time) · " + String(localized: "into \(drawer(record.to)?.name ?? "")"), stamp: .gotIt,
                amount: record.amount.map { amountText($0, code: code, sign: .positive) }, tone: .positive, record: record
            )
        case .moved:
            return ActivityRow(
                id: record.id, title: String(localized: "Moved to \(drawer(record.to)?.title ?? "")"),
                meta: "\(time) · \(drawer(record.from)?.name ?? "") → \(drawer(record.to)?.name ?? "")", stamp: .moved,
                amount: record.amount.map { amountText($0, code: code, sign: nil) }, tone: .neutral, record: record
            )
        case .swapped:
            let received = record.receivedAssetCode ?? "?"
            return ActivityRow(
                id: record.id, title: String(localized: "Swapped \(code) for \(received)"),
                meta: "\(time) · " + String(localized: "in \(drawer(record.from)?.name ?? "")"), stamp: .swapped,
                amount: record.amount.map { quantityText($0, code: code, sign: .negative) }, tone: .neutral, record: record,
                secondaryAmount: record.receivedAmount.map { quantityText($0, code: received, sign: .positive) }
            )
        case .cardAdded:
            let name = record.cardKey.flatMap(cardName) ?? String(localized: "A new card")
            let approver = record.approvedBy.flatMap(cardName)
            return ActivityRow(
                id: record.id, title: String(localized: "\(name) joined"),
                meta: "\(time) · " + (approver.map { String(localized: "approved by \($0)") } ?? String(localized: "Main account")),
                stamp: .newCard, amount: nil, tone: .neutral, record: record
            )
        }
    }

    /// Total du jour de ce qui est affiché : reçu moins envoyé ; un Move compte seulement quand un tiroir est choisi
    /// (il sort de ce tiroir, ou y entre). En dollars si la journée ne contient **que** de l'USDC, sinon par actif
    /// (décision de Barth du 2026-09-30 : ce qui a réellement bougé, sans conversion). `nil` : aucun montant ce jour-là.
    static func net(
        of records: [ActivityRecord], filter: Filter, addresses: Set<String>, locale: Locale = .autoupdatingCurrent
    ) -> (text: String, tone: ActivityTone)? {
        var codes: [String] = []
        var sums: [String: Decimal] = [:]
        for record in records {
            guard let kind = record.kind(drawers: addresses), let code = record.assetCode, let amount = record.amount else { continue }
            if sums[code] == nil { codes.append(code) }
            var signed: Decimal = 0
            switch kind {
            case .received: signed = amount
            case .sent: signed = -amount
            case .moved:
                if case .drawer(let address) = filter {
                    signed = record.from == address ? -amount : (record.to == address ? amount : 0)
                }
            case .swapped:
                // Les deux actifs du swap : ce qui est sorti du tiroir, ce qui y est entré.
                if let received = record.receivedAssetCode, let receivedAmount = record.receivedAmount {
                    if sums[received] == nil { codes.append(received) }
                    sums[received, default: 0] += receivedAmount
                }
                signed = -amount
            case .cardAdded: break
            }
            sums[code, default: 0] += signed
        }
        guard !codes.isEmpty else { return nil }
        let nonZero = codes.filter { sums[$0] != 0 }
        let shown = nonZero.isEmpty ? [codes[0]] : nonZero
        let text = shown.map { code in
            let sum = sums[code] ?? 0
            return amountText(abs(sum), code: code, sign: sum > 0 ? .positive : (sum < 0 ? .negative : nil), locale: locale)
        }.joined(separator: " · ")
        let total = shown.count == 1 ? sums[shown[0]] ?? 0 : 0
        let tone: ActivityTone = shown.count > 1 ? .neutral : (total > 0 ? .positive : (total < 0 ? .negative : .neutral))
        return (text, tone)
    }

    /// Montant de ce qui a bougé : USDC en dollars, tout autre actif dans son unité (« 1,757.5 XLM »). Aucune
    /// conversion au prix du jour (décision de Barth du 2026-09-30). Signe « + » ou « − » (moins typographique).
    /// Lignes de la liste : 2 décimales au plus, tronquées, « < 0.01 » (`SendAsset.displayed`, décision du 2026-10-01) ;
    /// reçu (`exact`) : le montant exact, 7 décimales au plus.
    static func amountText(_ amount: Decimal, code: String, sign: ActivityTone?, exact: Bool = false, locale: Locale = .autoupdatingCurrent) -> String {
        let prefix = switch sign {
        case .positive: "+"
        case .negative: "\u{2212}"
        default: ""
        }
        let isUSDC = code == SendAsset.usdc.code
        let body: String
        if exact {
            body = isUSDC
                ? amount.formatted(Decimal.FormatStyle.Currency(code: "USD", locale: locale).presentation(.narrow).precision(.fractionLength(2...7)))
                : "\(amount.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(0...7)))) \(code)"
        } else if isUSDC {
            let shown = SendAsset.displayed(amount, code: code, locale: locale)
            // « $< 0.01 » se lit mal : « < $0.01 ».
            body = shown.hasPrefix("<")
                ? "< " + SendAsset.smallestDisplayed.formatted(Decimal.FormatStyle.Currency(code: "USD", locale: locale).presentation(.narrow))
                : amount.truncated(to: 2).formatted(Decimal.FormatStyle.Currency(code: "USD", locale: locale).presentation(.narrow).precision(.fractionLength(2)))
        } else {
            body = "\(SendAsset.displayed(amount, code: code, locale: locale)) \(code)"
        }
        return prefix + body
    }

    /// Une quantité d'actif, jamais en dollars (swap, décision du 2026-10-14) : « −400 XLM », « +99.71 USDC », 2 décimales
    /// au plus, tronquées (`SendAsset.displayed`) ; `exact` : la quantité exacte (reçu).
    static func quantityText(_ amount: Decimal, code: String, sign: ActivityTone?, exact: Bool = false, locale: Locale = .autoupdatingCurrent) -> String {
        let prefix = switch sign {
        case .positive: "+"
        case .negative: "\u{2212}"
        default: ""
        }
        let body = exact ? exactAmount(amount, code: code, locale: locale) : "\(SendAsset.displayed(amount, code: code, locale: locale)) \(code)"
        return prefix + body
    }

    static func dayTitle(_ day: Date, calendar: Calendar, now: Date) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        return day.formatted(.dateTime.weekday(.wide))
    }

    static func dateText(_ day: Date) -> String {
        day.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: Reçu (I1.1d)

    /// Le reçu imprimé d'un mouvement (maquette I1.1d, décisions de Barth du 2026-09-30) : « N° » = ledger de la
    /// transaction ; frais « Paid by ChimpDAO » seulement pour ce que ce téléphone a envoyé ; statut « Confirmed » ;
    /// « Pay again » seulement pour un envoi.
    func receipt(for record: ActivityRecord, locale: Locale = .autoupdatingCurrent) -> ActivityReceipt? {
        let addresses = Set(drawers.map(\.address))
        guard let kind = record.kind(drawers: addresses),
              let row = Self.row(for: record, drawers: drawers, addresses: addresses, cardName: { [source] in source.cardName(key: $0) })
        else { return nil }
        func place(_ address: String) -> ActivityReceipt.Line.Value {
            if let drawer = drawers.first(where: { $0.address == address }) {
                return .drawer(drawer.title, swatch: drawer.isMain ? .main : .card(drawer.color ?? .jungle))
            }
            return .text(StellarAddressParser.short(address))
        }
        func card(_ key: String?) -> ActivityReceipt.Line.Value {
            let name = key.flatMap { source.cardName(key: $0) } ?? String(localized: "A new card")
            return .drawer(name, swatch: .card(key.flatMap { source.cardColor(key: $0) } ?? .jungle))
        }
        var lines: [ActivityReceipt.Line] = []
        switch kind {
        case .swapped:
            // Maquette I1s.1 : où, ce qui est parti, ce qui est arrivé, le minimum signé, la route, le protocole.
            let given = record.assetCode ?? "?"
            let received = record.receivedAssetCode ?? "?"
            lines.append(.init(id: "in", label: "In", value: place(record.from)))
            if let amount = record.amount {
                lines.append(.init(id: "gave", label: "Gave", value: .text(Self.exactAmount(amount, code: given, locale: locale))))
            }
            if let amount = record.receivedAmount {
                lines.append(.init(id: "got", label: "Got", value: .positive(Self.exactAmount(amount, code: received, locale: locale))))
            }
            if let minimum = record.minimumReceived {
                lines.append(.init(id: "minimum", label: "Min. guaranteed", value: .text(Self.exactAmount(minimum, code: received, locale: locale))))
            }
            lines.append(.init(id: "route", label: "Route", value: .text("\(given) → \(received)")))
            if let name = record.protocolName {
                lines.append(.init(id: "protocol", label: "Protocol", value: .text(name)))
            }
        case .cardAdded:
            lines.append(.init(id: "card", label: "Card", value: card(record.cardKey)))
            lines.append(.init(id: "added", label: "Added to", value: .drawer(String(localized: "Main account"), swatch: .main)))
            if record.approvedBy != nil {
                lines.append(.init(id: "approved", label: "Approved by", value: card(record.approvedBy)))
            }
        case .sent, .received, .moved:
            // Envoyé : à qui d'abord (maquette) ; reçu et Move : d'où d'abord.
            if kind == .sent {
                lines.append(.init(id: "to", label: "To", value: place(record.to)))
                lines.append(.init(id: "from", label: "From", value: place(record.from)))
            } else {
                lines.append(.init(id: "from", label: "From", value: place(record.from)))
                lines.append(.init(id: "to", label: "To", value: place(record.to)))
            }
            if let amount = record.amount, let code = record.assetCode {
                lines.append(.init(id: "amount", label: "Amount", value: .text(Self.exactAmount(amount, code: code, locale: locale))))
            }
        }
        if record.isLocal {
            if kind == .swapped {
                lines.append(.init(id: "fee", label: "Fees", value: .positive(String(localized: "On us"))))
            } else {
                lines.append(.init(id: "fee", label: "Fee", value: .text(String(localized: "Paid by ChimpDAO"))))
            }
        }
        lines.append(.init(id: "status", label: "Status", value: .positive(String(localized: "Confirmed"))))
        let date = record.at.formatted(Date.FormatStyle(locale: locale).weekday(.abbreviated).day().month(.abbreviated))
        let time = record.at.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale))
        let explorer = source.explorerURL(transactionHash: record.hash)
        func title(_ address: String) -> String {
            drawers.first { $0.address == address }?.title ?? StellarAddressParser.short(address)
        }
        let story: ShareMessage.Story = switch kind {
        case .sent: .sent(to: StellarAddressParser.short(record.to))
        case .received: .received(from: StellarAddressParser.short(record.from), into: title(record.to))
        case .moved: .moved(from: title(record.from), to: title(record.to))
        case .swapped: .swapped(
            received: record.receivedAmount.map { Self.exactAmount($0, code: record.receivedAssetCode ?? "", locale: locale) },
            in: title(record.from)
        )
        case .cardAdded: .cardAdded(
            card: record.cardKey.flatMap { source.cardName(key: $0) } ?? String(localized: "A new card"),
            approvedBy: record.approvedBy.flatMap { source.cardName(key: $0) }
        )
        }
        let share = ShareMessage.text(
            story,
            amount: record.amount.flatMap { amount in record.assetCode.map { Self.exactAmount(amount, code: $0, locale: locale) } },
            date: record.at.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale)),
            network: network, explorerURL: explorer, hash: record.hash
        )
        return ActivityReceipt(
            id: record.id,
            header: "\(date) · \(time)",
            number: record.ledger.map { "N° \($0)" },
            title: row.title,
            lines: lines,
            hash: record.hash,
            shortHash: record.hash.count > 12 ? "\(record.hash.prefix(4))…\(record.hash.suffix(4))" : record.hash,
            total: kind == .swapped ? nil : record.amount.flatMap { amount in
                record.assetCode.map { code in
                    Self.amountText(amount, code: code, sign: kind == .sent ? .negative : (kind == .received ? .positive : nil), exact: true, locale: locale)
                }
            },
            totalTone: row.tone == .positive ? .positive : .neutral,
            stamp: row.stamp,
            explorerURL: explorer,
            shareText: share,
            counterparty: Self.counterparty(of: record, kind: kind),
            send: Self.prefill(for: record, kind: kind),
            stampAmounts: kind == .swapped ? Self.swapAmounts(of: record, locale: locale) : [],
            swap: kind == .swapped ? Self.swapPrefill(for: record) : nil
        )
    }

    /// Reçu d'un envoi qui vient de partir (C9 « See the receipt ») : le même reçu que sa ligne de l'Activity. La ligne
    /// gardée par le téléphone fait foi (elle a son « N° » une fois la chaîne relue) ; les tiroirs sont lus sur le
    /// téléphone, sans réseau, si l'onglet ne les a pas encore chargés.
    func receipt(forSent record: ActivityRecord, locale: Locale = .autoupdatingCurrent) -> ActivityReceipt? {
        if drawers.isEmpty { drawers = source.drawers() }
        let stored = source.storedActivity().records.first { $0.id == record.id }
        return receipt(for: stored ?? record, locale: locale)
    }

    /// Montant exact dans l'actif, pour la ligne « Amount » : « 25.00 USDC », « 1,757.5 XLM ».
    static func exactAmount(_ amount: Decimal, code: String, locale: Locale = .autoupdatingCurrent) -> String {
        let digits = code == SendAsset.usdc.code ? 2...7 : 0...7
        return "\(amount.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(digits)))) \(code)"
    }

    /// L'autre partie d'un envoi (TO) ou d'un paiement reçu (FROM), pour « Copy » (retour du 2026-10-01). Rien pour un Move
    /// ou une carte ajoutée : ce sont ses propres tiroirs.
    static func counterparty(of record: ActivityRecord, kind: ActivityKind) -> ActivityReceipt.Counterparty? {
        switch kind {
        case .sent: ActivityReceipt.Counterparty(lineID: "to", address: record.to)
        case .received: ActivityReceipt.Counterparty(lineID: "from", address: record.from)
        case .moved, .cardAdded, .swapped: nil
        }
    }

    /// « Pay again » (envoi) ou « Send back » (paiement reçu) : adresse, actif et montant préremplis (décision de Barth du
    /// 2026-10-01). Seulement pour un actif qu'on sait envoyer (XLM, USDC).
    static func prefill(for record: ActivityRecord, kind: ActivityKind) -> SendPrefill? {
        let asset = record.assetCode.flatMap(SendAsset.init(code:))
        switch kind {
        case .sent:
            return SendPrefill(address: record.to, asset: asset, amount: asset == nil ? nil : record.amount, origin: .payAgain)
        case .received:
            guard asset != nil else { return nil }
            return SendPrefill(address: record.from, asset: asset, amount: record.amount, origin: .sendBack)
        case .moved, .cardAdded, .swapped:
            return nil
        }
    }

    /// Les deux quantités d'un swap, à côté du tampon (maquette I1s.1) : « −400 XLM », « +99.71 USDC ».
    static func swapAmounts(of record: ActivityRecord, locale: Locale = .autoupdatingCurrent) -> [ActivityReceipt.StampAmount] {
        var amounts: [ActivityReceipt.StampAmount] = []
        if let amount = record.amount, let code = record.assetCode {
            amounts.append(.init(text: quantityText(amount, code: code, sign: .negative, locale: locale), tone: .neutral))
        }
        if let amount = record.receivedAmount, let code = record.receivedAssetCode {
            amounts.append(.init(text: quantityText(amount, code: code, sign: .positive, locale: locale), tone: .positive))
        }
        return amounts
    }

    /// « Swap again » : même tiroir, mêmes actifs, même montant (XLM et USDC seulement), au prix du moment.
    static func swapPrefill(for record: ActivityRecord) -> SwapPrefill? {
        guard let given = record.assetCode.flatMap(SendAsset.init(code:)),
              let received = record.receivedAssetCode.flatMap(SendAsset.init(code:)) else { return nil }
        return SwapPrefill(drawerAddress: record.from, given: given, received: received, amount: record.amount)
    }

    // MARK: Copier (hash, adresse de l'autre partie)

    enum Copied: Equatable {
        case hash(String)
        case address(String)
    }

    private(set) var copied: Copied?
    private(set) var copyCount = 0
    private var copiedResetTask: Task<Void, Never>?
    var clipboard: AddressClipboard = SystemAddressClipboard()

    /// « Copy » du reçu : le hash **complet**, « Copied! » pendant 2 s (comme Recevoir).
    func copyHash(_ hash: String) {
        copy(.hash(hash), text: hash)
    }

    /// « Copy » de l'autre partie : l'adresse **complète** (la ligne n'en montre que le début et la fin).
    func copyAddress(_ address: String) {
        copy(.address(address), text: address)
    }

    private func copy(_ item: Copied, text: String) {
        clipboard.copy(text)
        copied = item
        copyCount += 1
        copiedResetTask?.cancel()
        copiedResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.copied = nil
        }
    }
}

/// Le reçu imprimé d'un mouvement, prêt à afficher (I1.1d).
struct ActivityReceipt: Identifiable, Equatable {
    struct Line: Identifiable, Equatable {
        enum Swatch: Equatable {
            case main
            case card(ChimpCardColor)
        }

        enum Value: Equatable {
            case text(String)
            case drawer(String, swatch: Swatch)
            case positive(String)
        }

        let id: String
        /// En capitales à l'affichage (« TO », « FROM »).
        let label: LocalizedStringKey
        let value: Value

        static func == (lhs: Line, rhs: Line) -> Bool { lhs.id == rhs.id && lhs.value == rhs.value }
    }

    let id: String
    /// « Tue 30 Sep · 14:02 » (capitales à l'affichage).
    let header: String
    /// « N° 4935984 » : ledger de la transaction, `nil` tant que le téléphone ne le connaît pas.
    let number: String?
    let title: String
    let lines: [Line]
    let hash: String
    let shortHash: String
    /// Même montant que la ligne de la liste ; `nil` pour une carte ajoutée (pas de TOTAL).
    let total: String?
    let totalTone: ActivityTone
    let stamp: ActivityStamp
    let explorerURL: URL?
    let shareText: String
    /// L'autre partie (adresse complète), copiable depuis sa ligne.
    let counterparty: Counterparty?
    /// « Pay again » (envoi) ou « Send back » (paiement reçu) : Envoyer prérempli.
    let send: SendPrefill?
    /// Swap : les deux quantités à côté du tampon (à la place du total), et « Swap again ».
    var stampAmounts: [StampAmount] = []
    var swap: SwapPrefill? = nil

    struct StampAmount: Equatable {
        let text: String
        let tone: ActivityTone
    }

    /// Le bouton « again » de ce reçu : « Swap again » pour un swap, « Send back » pour un paiement reçu, « Pay again »
    /// pour un envoi ; `nil` sinon (Move, carte ajoutée).
    var again: ReceiptAgain? {
        if let swap { return .swapAgain(swap) }
        guard let send else { return nil }
        return send.origin == .sendBack ? .sendBack(send) : .payAgain(send)
    }

    struct Counterparty: Equatable {
        /// Ligne qui l'affiche (« to », « from »).
        let lineID: String
        let address: String
    }
}

/// Ce que relance le bouton « again » d'un reçu. Une seule action typée (au lieu d'une fermeture par sorte) : chaque écran
/// dit explicitement ce qu'il fait de chacune, une fermeture ne peut plus être branchée sur la mauvaise (bug du
/// 2026-10-14 : « Pay again » d'un envoi lançait l'action du swap).
enum ReceiptAgain: Equatable {
    /// Envoi : payer de nouveau la même adresse.
    case payAgain(SendPrefill)
    /// Paiement reçu : renvoyer à l'expéditeur.
    case sendBack(SendPrefill)
    /// Swap : refaire le même swap au prix du moment.
    case swapAgain(SwapPrefill)

    /// Le texte du bouton.
    var title: LocalizedStringKey {
        switch self {
        case .payAgain: "Pay again"
        case .sendBack: "Send back"
        case .swapAgain: "Swap again"
        }
    }

    /// Envoyer prérempli (« Pay again », « Send back »), `nil` pour un swap.
    var sendPrefill: SendPrefill? {
        switch self {
        case .payAgain(let prefill), .sendBack(let prefill): prefill
        case .swapAgain: nil
        }
    }

    /// Swap prérempli (« Swap again »), `nil` pour un envoi.
    var swapPrefill: SwapPrefill? {
        if case .swapAgain(let prefill) = self { return prefill }
        return nil
    }
}
