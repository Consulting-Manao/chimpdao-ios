import Foundation
import Testing
@testable import ChimpDAO

/// Session « Activity », étape 3 : l'onglet I1 (tickets par jour, montants, total du jour, filtres, paiement en attente,
/// états). Règles de Barth du 2026-09-30 : ce qui a réellement bougé, USDC en dollars, XLM en XLM, sans conversion ;
/// total du jour en dollars seulement si la journée ne contient que de l'USDC.
struct ActivityViewModelTests {
    static let main = "CMAIN"
    static let jungle = "CJUNGLE"
    static let banana = "CBANANA"
    static let maya = "GCQF355RQFN77CHM5DHEGK75FWVF26PUES6J6EMQ4U7BAD3E7ORDGXPO"
    static let drawers: [ActivityDrawer] = [.main(main), .card(jungle, name: "Jungle", color: .jungle), .card(banana, name: "Banana", color: .banana)]
    static let addresses = Set(drawers.map(\.address))
    static let us = Locale(identifier: "en_US")

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    /// Mardi 30 septembre 2026, 15:00 à Paris.
    static let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 15))!

    static func at(_ daysAgo: Int, _ hour: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)!)!
    }

    static func transfer(_ id: String, _ from: String, _ to: String, _ code: String, _ amount: String, _ date: Date, local: Bool = false) -> ActivityRecord {
        ActivityRecord(id: "stellar:\(id)", event: .transfer, hash: id, from: from, to: to, assetCode: code, amount: Decimal(string: amount)!, at: date, isLocal: local)
    }

    static func card(_ id: String, _ date: Date) -> ActivityRecord {
        ActivityRecord(id: "stellar:\(id)", event: .cardAdded, hash: id, from: main, to: "", cardKey: "04aa", approvedBy: "04bb", at: date, isLocal: true)
    }

    // MARK: Montants

    @Test("Lignes : USDC en dollars, XLM en XLM, 2 décimales au plus (tronquées), « + » et « − » typographique")
    func amounts() {
        #expect(ActivityViewModel.amountText(25, code: "USDC", sign: .negative, locale: Self.us) == "\u{2212}$25.00")
        #expect(ActivityViewModel.amountText(Decimal(string: "0.12")!, code: "USDC", sign: .positive, locale: Self.us) == "+$0.12")
        #expect(ActivityViewModel.amountText(Decimal(string: "0.1299999")!, code: "USDC", sign: nil, locale: Self.us) == "$0.12")
        #expect(ActivityViewModel.amountText(Decimal(string: "0.0012")!, code: "USDC", sign: .positive, locale: Self.us) == "+< $0.01")
        #expect(ActivityViewModel.amountText(Decimal(string: "1757.5")!, code: "XLM", sign: .positive, locale: Self.us) == "+1,757.5 XLM")
        #expect(ActivityViewModel.amountText(Decimal(string: "994.6196784")!, code: "XLM", sign: .negative, locale: Self.us) == "\u{2212}994.61 XLM")
        #expect(ActivityViewModel.amountText(Decimal(string: "0.0000001")!, code: "XLM", sign: nil, locale: Self.us) == "< 0.01 XLM")
        #expect(ActivityViewModel.amountText(1000, code: "XLM", sign: nil, locale: Self.us) == "1,000 XLM")
    }

    @Test("Reçu : montant exact (7 décimales au plus)")
    func exactAmounts() {
        #expect(ActivityViewModel.amountText(Decimal(string: "0.1234567")!, code: "USDC", sign: nil, exact: true, locale: Self.us) == "$0.1234567")
        #expect(ActivityViewModel.amountText(Decimal(string: "0.0000001")!, code: "XLM", sign: nil, exact: true, locale: Self.us) == "0.0000001 XLM")
        #expect(ActivityViewModel.amountText(Decimal(string: "994.6196784")!, code: "XLM", sign: .negative, exact: true, locale: Self.us) == "\u{2212}994.6196784 XLM")
    }

    @Test("Total du jour : que de l'USDC → en dollars ; sinon par actif ; un Move ne compte pas pour tous les tiroirs")
    func dayTotals() {
        let onlyUSDC = [
            Self.transfer("a", Self.jungle, Self.maya, "USDC", "25", Self.at(0, 14)),
            Self.transfer("b", Self.maya, Self.main, "USDC", "0.12", Self.at(0, 9)),
            Self.transfer("c", Self.main, Self.jungle, "USDC", "50", Self.at(0, 11)),
        ]
        let usdc = ActivityViewModel.net(of: onlyUSDC, filter: .all, addresses: Self.addresses, locale: Self.us)
        #expect(usdc?.text == "\u{2212}$24.88")
        #expect(usdc?.tone == .negative)

        let mixed = onlyUSDC + [Self.transfer("d", Self.maya, Self.jungle, "XLM", "1757.5", Self.at(0, 8))]
        let perAsset = ActivityViewModel.net(of: mixed, filter: .all, addresses: Self.addresses, locale: Self.us)
        #expect(perAsset?.text == "\u{2212}$24.88 · +1,757.5 XLM")
        #expect(perAsset?.tone == .neutral)

        let onlyMove = [Self.transfer("e", Self.main, Self.banana, "XLM", "2000", Self.at(0, 10))]
        #expect(ActivityViewModel.net(of: onlyMove, filter: .all, addresses: Self.addresses, locale: Self.us)?.text == "0 XLM")
        #expect(ActivityViewModel.net(of: [Self.card("f", Self.at(0, 12))], filter: .all, addresses: Self.addresses) == nil)
    }

    @Test("Tiroir choisi : un Move sort de ce tiroir (−) ou y entre (+)")
    func dayTotalForADrawer() {
        let move = [Self.transfer("e", Self.main, Self.banana, "XLM", "2000", Self.at(0, 10))]
        #expect(ActivityViewModel.net(of: move, filter: .drawer(Self.banana), addresses: Self.addresses, locale: Self.us)?.text == "+2,000 XLM")
        #expect(ActivityViewModel.net(of: move, filter: .drawer(Self.main), addresses: Self.addresses, locale: Self.us)?.text == "\u{2212}2,000 XLM")
    }

    // MARK: Tickets et lignes

    @Test("Un ticket par journée, les plus récentes d'abord : Today, Yesterday, puis le jour de la semaine")
    func tickets() {
        let records = [
            Self.transfer("old", Self.maya, Self.banana, "XLM", "1000", Self.at(3, 10)),
            Self.transfer("t1", Self.jungle, Self.maya, "USDC", "25", Self.at(0, 14)),
            Self.card("y1", Self.at(1, 12)),
            Self.transfer("t2", Self.main, Self.jungle, "USDC", "50", Self.at(0, 11)),
        ]
        let tickets = ActivityViewModel.tickets(
            for: records, filter: .all, drawers: Self.drawers, cardName: { $0 == "04aa" ? "Leaf" : ($0 == "04bb" ? "Banana" : nil) },
            calendar: Self.calendar, now: Self.now
        )
        #expect(tickets.map(\.title) == ["Today", "Yesterday", ActivityViewModel.dayTitle(Self.at(3, 10), calendar: Self.calendar, now: Self.now)])
        #expect(tickets[2].title == Self.at(3, 10).formatted(.dateTime.weekday(.wide)))
        #expect(tickets[0].rows.map(\.id) == ["stellar:t1", "stellar:t2"])
        #expect(tickets[1].rows.first?.title == "Leaf joined")
        #expect(tickets[1].rows.first?.stamp == .newCard)
        #expect(tickets[1].rows.first?.amount == nil)
        #expect(tickets[1].net == nil, "Une carte ajoutée seule : pas de total")
    }

    @Test("Titres, tampons et tiroirs (textes validés) : envoyé, reçu, Move, carte ajoutée")
    func rows() {
        func row(_ record: ActivityRecord) -> ActivityRow? {
            ActivityViewModel.row(for: record, drawers: Self.drawers, addresses: Self.addresses) { $0 == "04aa" ? "Leaf" : ($0 == "04bb" ? "Banana" : nil) }
        }
        let sent = row(Self.transfer("a", Self.jungle, Self.maya, "USDC", "25", Self.at(0, 14)))
        #expect(sent?.title == "You paid GCQF…GXPO")
        #expect(sent?.meta.hasSuffix(" · from Jungle") == true)
        #expect(sent?.stamp == .paid)
        #expect(sent?.tone == .neutral)
        #expect(sent?.amount?.hasPrefix("\u{2212}") == true)

        let received = row(Self.transfer("b", Self.maya, Self.main, "XLM", "1000", Self.at(0, 9)))
        #expect(received?.title == "GCQF…GXPO paid you")
        #expect(received?.meta.hasSuffix(" · into Main") == true)
        #expect(received?.stamp == .gotIt)
        #expect(received?.tone == .positive)
        #expect(received?.amount?.hasPrefix("+") == true)

        let moved = row(Self.transfer("c", Self.main, Self.jungle, "USDC", "50", Self.at(0, 11)))
        #expect(moved?.title == "Moved to Jungle's wallet")
        #expect(moved?.meta.hasSuffix(" · Main → Jungle") == true)
        #expect(moved?.stamp == .moved)
        #expect(moved?.amount?.hasPrefix("+") == false)
        #expect(moved?.amount?.hasPrefix("\u{2212}") == false)

        let joined = row(Self.card("d", Self.at(1, 12)))
        #expect(joined?.title == "Leaf joined")
        #expect(joined?.meta.hasSuffix(" · approved by Banana") == true)

        #expect(row(Self.transfer("e", "COLDPOCKET", Self.maya, "XLM", "1", Self.at(0, 1))) == nil, "Wallet d'une carte retirée : rien")
    }

    @Test("Filtre par tiroir : ses mouvements (dans les deux sens) ; les cartes ajoutées sous Main seulement")
    func filters() {
        let records = [
            Self.transfer("a", Self.jungle, Self.maya, "USDC", "25", Self.at(0, 14)),
            Self.transfer("b", Self.main, Self.jungle, "USDC", "50", Self.at(0, 11)),
            Self.transfer("c", Self.maya, Self.banana, "XLM", "1", Self.at(0, 10)),
            Self.card("d", Self.at(1, 12)),
        ]
        func ids(_ filter: ActivityViewModel.Filter) -> [String] {
            ActivityViewModel.filtered(records, filter: filter, drawers: Self.drawers).map(\.hash)
        }
        #expect(ids(.all) == ["a", "b", "c", "d"])
        #expect(ids(.drawer(Self.jungle)) == ["a", "b"])
        #expect(ids(.drawer(Self.main)) == ["b", "d"])
        #expect(ids(.drawer(Self.banana)) == ["c"])
    }

    // MARK: États

    @Test("Ce qui est gardé s'affiche tout de suite ; la chaîne complète ; la ligne du téléphone l'emporte")
    func storedThenSynced() async {
        let source = FakeActivitySource()
        source.stored = AccountActivity(records: [Self.transfer("a", Self.jungle, Self.maya, "USDC", "25", Self.at(0, 14), local: true)])
        source.synced = AccountActivity(records: [
            ActivityRecord(id: "stellar:a:1", event: .transfer, hash: "a", from: Self.jungle, to: Self.maya, assetCode: "USDC", amount: 25, at: Self.at(0, 14), isLocal: false),
            Self.transfer("b", Self.maya, Self.main, "USDC", "1", Self.at(0, 9)),
        ])
        let model = ActivityViewModel(source: source, calendar: Self.calendar, now: { Self.now })
        source.onSync = { #expect(model.phase == .loaded && model.records.map(\.id) == ["stellar:a"], "Affiché avant la lecture") }
        await model.refresh()
        #expect(model.phase == .loaded)
        #expect(!model.isShowingStaleData)
        #expect(model.records.map(\.id).sorted() == ["stellar:a:1", "stellar:b"], "La source rend déjà l'historique fusionné")
        #expect(!model.isEmpty)
    }

    @Test("Erreur réseau : rien de gardé → échec ; des lignes gardées → bandeau « données anciennes »")
    func networkErrors() async {
        let empty = FakeActivitySource()
        empty.error = StellarError.rpc("offline")
        let first = ActivityViewModel(source: empty)
        await first.refresh()
        #expect(first.phase == .failed)

        let kept = FakeActivitySource()
        kept.stored = AccountActivity(records: [Self.transfer("a", Self.jungle, Self.maya, "USDC", "25", Self.at(0, 14))])
        kept.error = StellarError.rpc("offline")
        let second = ActivityViewModel(source: kept)
        await second.refresh()
        #expect(second.phase == .loaded)
        #expect(second.isShowingStaleData)
        #expect(second.records.count == 1)
    }

    @Test("Aucun mouvement : état vide, après la lecture seulement")
    func emptyState() async {
        let source = FakeActivitySource()
        let model = ActivityViewModel(source: source)
        #expect(!model.isEmpty)
        await model.refresh()
        #expect(model.isEmpty)
    }

    @Test("Deux rafraîchissements en même temps : une seule lecture de la chaîne")
    func singleSync() async {
        let source = FakeActivitySource()
        source.delay = .milliseconds(50)
        let model = ActivityViewModel(source: source)
        async let a: Void = model.refresh()
        async let b: Void = model.refresh()
        _ = await (a, b)
        #expect(source.syncCount == 1)
    }

    // MARK: Paiement en attente

    @Test("Paiement en attente : en haut avec son statut (« Wait until… ») ; parti : il disparaît, l'envoi est dans l'historique")
    func pendingPayment() async throws {
        let source = FakeActivitySource()
        source.pendingSend = PendingSend(
            trace: PaymentTrace(token: "t", from: Self.main, destination: Self.maya, units: 250_000_000, nonce: 1, preparedAtLedger: 1, expirationLedger: 121),
            recipient: Self.maya, recipientName: nil, drawerTitle: "Main account", asset: "usdc", amount: 25, signedAt: Self.at(0, 14)
        )
        let end = Self.at(0, 15)
        source.check = .waiting(untilLedger: 121, estimatedEnd: end)
        let model = ActivityViewModel(source: source, calendar: Self.calendar, now: { Self.now })
        await model.refresh()
        let ticket = try #require(model.tickets.first)
        #expect(ticket.isPending)
        #expect(ticket.rows.first?.stamp == .pending)
        #expect(ticket.rows.first?.title == "Paying GCQF…GXPO")
        #expect(ticket.rows.first?.meta.hasSuffix("Wait until \(end.formatted(date: .omitted, time: .shortened))") == true)
        #expect(ticket.rows.first?.record == nil, "Il ouvre l'écran d'état d'Envoyer, pas un reçu")
        #expect(!model.isEmpty)

        model.filter = .drawer(Self.jungle)
        #expect(model.tickets.first?.isPending != true, "Pas sous un autre tiroir")
        model.filter = .all

        // Parti : la vraie source l'a écrit dans l'historique et effacé du téléphone.
        source.check = .sent(hash: "h")
        source.stored = AccountActivity(records: [Self.transfer("h", Self.main, Self.maya, "USDC", "25", Self.at(0, 14), local: true)])
        await model.refresh()
        #expect(model.pending == nil)
        #expect(model.records.map(\.hash).contains("h"))
    }
}

extension ActivityViewModelTests {
    // MARK: Reçu imprimé (I1.1d)

    static let hash = "7b3e" + String(repeating: "0", count: 56) + "a91f"

    private func receiptModel() async -> ActivityViewModel {
        let source = FakeActivitySource()
        source.names = ["04aa": ("Leaf", .leaf), "04bb": ("Banana", .banana)]
        let model = ActivityViewModel(source: source, calendar: Self.calendar, now: { Self.now })
        await model.refresh()
        return model
    }

    @Test("Reçu d'un envoi (maquette I1.1d) : TO, FROM avec la couleur de la carte, montant exact, frais offerts, Confirmed, N° = ledger, Pay again")
    func sentReceipt() async throws {
        let model = await receiptModel()
        var record = Self.transfer("s", Self.jungle, Self.maya, "USDC", "25", Self.at(0, 14), local: true)
        record.hash = Self.hash
        record.ledger = 4_935_984
        let receipt = try #require(model.receipt(for: record, locale: Self.us))
        #expect(receipt.title == "You paid GCQF…GXPO")
        #expect(receipt.number == "N° 4935984")
        #expect(receipt.lines.map(\.id) == ["to", "from", "amount", "fee", "status"])
        #expect(receipt.lines[0].value == .text("GCQF…GXPO"))
        #expect(receipt.lines[1].value == .drawer("Jungle's wallet", swatch: .card(.jungle)))
        #expect(receipt.lines[2].value == .text("25.00 USDC"))
        #expect(receipt.lines[3].value == .text("Paid by ChimpDAO"))
        #expect(receipt.lines[4].value == .positive("Confirmed"))
        #expect(receipt.shortHash == "7b3e…a91f")
        #expect(receipt.total == "\u{2212}$25.00")
        #expect(receipt.stamp == .paid)
        #expect(receipt.send == SendPrefill(address: Self.maya, asset: .usdc, amount: 25, origin: .payAgain), "Pay again : adresse, actif et montant")
        #expect(receipt.counterparty == ActivityReceipt.Counterparty(lineID: "to", address: Self.maya))
        #expect(receipt.explorerURL?.absoluteString.hasSuffix(Self.hash) == true)
        #expect(receipt.shareText.contains("You paid GCQF…GXPO"))
        #expect(receipt.shareText.hasSuffix(Self.hash))
        #expect(receipt.header.contains(" · "))
    }

    @Test("C9 « See the receipt » : la ligne d'historique de l'envoi, et le même reçu imprimé que dans l'Activity")
    func sentPaymentReceipt() async throws {
        let sent = SendReceipt(
            summary: SendSummary(
                recipientAddress: Self.maya, recipientName: nil, drawerTitle: "Jungle's wallet", fromAddress: Self.jungle,
                asset: .usdc, amount: 25, network: .testnet
            ),
            transactionHash: Self.hash, sentAt: Self.at(0, 14), explorerURL: nil
        )
        let record = sent.activityRecord
        #expect(record == .payment(hash: Self.hash, from: Self.jungle, to: Self.maya, assetCode: "USDC", amount: 25, at: Self.at(0, 14)))

        // Onglet jamais ouvert : les tiroirs sont lus sur le téléphone, sans réseau.
        let source = FakeActivitySource()
        let fresh = ActivityViewModel(source: source, calendar: Self.calendar, now: { Self.now })
        let printed = try #require(fresh.receipt(forSent: record, locale: Self.us))
        #expect(source.syncCount == 0)
        let fromActivity = try #require(await receiptModel().receipt(for: record, locale: Self.us))
        #expect(printed == fromActivity)
        #expect(printed.stamp == .paid)
        #expect(printed.send == SendPrefill(address: Self.maya, asset: .usdc, amount: 25, origin: .payAgain))

        // La ligne gardée par le téléphone fait foi : elle a son N° une fois la chaîne relue.
        var stored = record
        stored.ledger = 4_935_984
        source.stored = AccountActivity(records: [stored])
        #expect(fresh.receipt(forSent: record, locale: Self.us)?.number == "N° 4935984")

        // Move : le même reçu que l'Activity, sans « Pay again ».
        let move = SendReceipt(
            summary: SendSummary(
                recipientAddress: Self.jungle, recipientName: nil, drawerTitle: "Main account", fromAddress: Self.main,
                asset: .xlm, amount: 5, network: .testnet
            ),
            transactionHash: "m0ve" + String(repeating: "0", count: 60), sentAt: Self.at(0, 15), explorerURL: nil
        )
        #expect(try #require(fresh.receipt(forSent: move.activityRecord, locale: Self.us)).send == nil)
    }

    @Test("Reçu d'un montant reçu : FROM puis TO (Main), pas de frais (pas envoyé par ce téléphone), « Send back »")
    func receivedReceipt() async throws {
        let model = await receiptModel()
        let receipt = try #require(model.receipt(for: Self.transfer("r", Self.maya, Self.main, "XLM", "1757.5", Self.at(0, 9)), locale: Self.us))
        #expect(receipt.lines.map(\.id) == ["from", "to", "amount", "status"])
        #expect(receipt.lines[1].value == .drawer("Main account", swatch: .main))
        #expect(receipt.lines[2].value == .text("1,757.5 XLM"))
        #expect(receipt.total == "+1,757.5 XLM")
        #expect(receipt.totalTone == .positive)
        #expect(receipt.stamp == .gotIt)
        #expect(receipt.send == SendPrefill(address: Self.maya, asset: .xlm, amount: Decimal(string: "1757.5")!, origin: .sendBack),
                "Send back : renvoyer à l'expéditeur, même actif et même montant")
        #expect(receipt.counterparty == ActivityReceipt.Counterparty(lineID: "from", address: Self.maya))
        #expect(receipt.number == nil, "Ledger encore inconnu : pas de N°")
    }

    @Test("Reçu d'un Move : deux tiroirs, pas de « Pay again » ; carte ajoutée : CARD, ADDED TO, APPROVED BY, pas de TOTAL")
    func moveAndCardReceipts() async throws {
        let model = await receiptModel()
        let move = try #require(model.receipt(for: Self.transfer("m", Self.main, Self.banana, "XLM", "2000", Self.at(0, 10)), locale: Self.us))
        #expect(move.lines[0].value == .drawer("Main account", swatch: .main))
        #expect(move.lines[1].value == .drawer("Banana's wallet", swatch: .card(.banana)))
        #expect(move.stamp == .moved)
        #expect(move.send == nil)
        #expect(move.counterparty == nil, "Un Move ne va que vers ses propres tiroirs")

        let card = try #require(model.receipt(for: Self.card("c", Self.at(1, 12)), locale: Self.us))
        #expect(card.title == "Leaf joined")
        #expect(card.lines.map(\.id) == ["card", "added", "approved", "fee", "status"])
        #expect(card.lines[0].value == .drawer("Leaf", swatch: .card(.leaf)))
        #expect(card.lines[2].value == .drawer("Banana", swatch: .card(.banana)))
        #expect(card.total == nil)
        #expect(card.stamp == .newCard)
    }

    @Test("« Copy » : le hash complet, « Copied! » pour ce reçu")
    func copyHash() async {
        let model = await receiptModel()
        let clipboard = RecordingClipboard()
        model.clipboard = clipboard
        model.copyHash(Self.hash)
        #expect(clipboard.copied == [Self.hash])
        #expect(model.copied == .hash(Self.hash))
        #expect(model.copyCount == 1)
        model.copyAddress(Self.maya)
        #expect(clipboard.copied.last == Self.maya, "L'adresse complète, pas « GCQF…GXPO »")
        #expect(model.copied == .address(Self.maya))
        #expect(model.copyCount == 2)
    }

    @Test("Send back d'un actif qu'on ne sait pas envoyer : pas de bouton ; Pay again : adresse seule")
    func unknownAssetPrefill() async throws {
        let model = await receiptModel()
        let received = try #require(model.receipt(for: Self.transfer("e", Self.maya, Self.main, "EURC", "3", Self.at(0, 9)), locale: Self.us))
        #expect(received.send == nil)
        let sent = try #require(model.receipt(for: Self.transfer("f", Self.main, Self.maya, "EURC", "3", Self.at(0, 9)), locale: Self.us))
        #expect(sent.send == SendPrefill(address: Self.maya, origin: .payAgain))
    }
}

final class RecordingClipboard: AddressClipboard, @unchecked Sendable {
    private(set) var copied: [String] = []
    func copy(_ text: String) { copied.append(text) }
}

/// Fausse source de l'Activity.
final class FakeActivitySource: ActivityDataSource, @unchecked Sendable {
    let network = StellarNetwork.testnet
    var stored = AccountActivity()
    var synced: AccountActivity?
    var error: Error?
    var delay: Duration = .zero
    var onSync: () -> Void = {}
    var pendingSend: PendingSend?
    var check: PaymentCheck = .pending
    private(set) var syncCount = 0

    func drawers() -> [ActivityDrawer] { ActivityViewModelTests.drawers }
    var names: [String: (String, ChimpCardColor)] = [:]
    func cardName(key: String) -> String? { names[key]?.0 }
    func cardColor(key: String) -> ChimpCardColor? { names[key]?.1 }
    func storedActivity() -> AccountActivity { stored }

    func sync(onProgress: @escaping (AccountActivity) -> Void) async throws -> AccountActivity {
        syncCount += 1
        onSync()
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return synced ?? stored
    }

    func checkPending(_ pending: PendingSend) async throws -> PaymentCheck { check }
    func explorerURL(transactionHash: String) -> URL? { URL(string: "https://stellar.expert/explorer/testnet/tx/\(transactionHash)") }
}
