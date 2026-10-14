import Foundation
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 2 : un swap dans l'Activity (maquettes I1s et I1s.1) : une seule ligne « SWAPPED », deux quantités
/// (jamais de dollars), le reçu avec le minimum signé, « Swap again ».
struct ActivitySwapTests {
    private let main = MockReceiveDataSource.mainAddress
    private let jungle = MockReceiveDataSource.jungleAddress
    private let pair = "CCBX3NZTCQLQFSPG7HBOKL4P2RVPOPVFHDNRTOSCCJWBTPL2GHEH7RQS"
    private let english = Locale(identifier: "en_US")
    private var drawers: [ActivityDrawer] { [.main(main), .card(jungle, name: "Jungle", color: .jungle)] }
    private var addresses: Set<String> { Set(drawers.map(\.address)) }

    private func transfer(_ id: String, hash: String, _ from: String, _ to: String, _ code: String, _ amount: Decimal) -> ActivityRecord {
        ActivityRecord(id: "stellar:\(hash):\(id)", event: .transfer, hash: hash, from: from, to: to, assetCode: code, amount: amount, at: .now, isLocal: false, ledger: 7)
    }

    private let localSwap = ActivityRecord.swap(
        hash: "abc", drawer: MockReceiveDataSource.mainAddress, venue: "CCBX3NZTCQLQFSPG7HBOKL4P2RVPOPVFHDNRTOSCCJWBTPL2GHEH7RQS",
        givenCode: "XLM", given: 400, receivedCode: "USDC", received: Decimal(string: "99.7123456")!,
        minimum: Decimal(string: "99.1816")!, protocolName: "Soroswap", at: Date(timeIntervalSince1970: 1_791_000_000)
    )

    // MARK: Regroupement des transferts relus sur la chaîne

    @Test("Deux transferts d'une même transaction (XLM sort de Main, USDC y entre) : une seule ligne de swap")
    func groupsChainSwap() throws {
        let records = [
            transfer("1", hash: "h", main, pair, "XLM", 400),
            transfer("2", hash: "h", pair, main, "USDC", Decimal(string: "99.71")!),
        ]
        let grouped = ActivityRecord.groupingSwaps(records, drawers: addresses)
        #expect(grouped.count == 1)
        let swap = try #require(grouped.first)
        #expect(swap.event == .swap)
        #expect(swap.from == main)
        #expect(swap.assetCode == "XLM" && swap.amount == 400)
        #expect(swap.receivedAssetCode == "USDC" && swap.receivedAmount == Decimal(string: "99.71"))
        #expect(swap.ledger == 7)
        #expect(swap.protocolName == nil && swap.minimumReceived == nil)
        #expect(swap.kind(drawers: addresses) == .swapped)
    }

    @Test("Pas un swap : un Move entre deux tiroirs, un même actif, un transfert seul, trois transferts")
    func leavesOthersAlone() {
        let move = [transfer("1", hash: "m", main, jungle, "XLM", 1), transfer("2", hash: "m", jungle, main, "USDC", 1)]
        #expect(ActivityRecord.groupingSwaps(move, drawers: addresses) == move)
        let sameAsset = [transfer("1", hash: "s", main, pair, "XLM", 1), transfer("2", hash: "s", pair, main, "XLM", 1)]
        #expect(ActivityRecord.groupingSwaps(sameAsset, drawers: addresses) == sameAsset)
        let single = [transfer("1", hash: "x", main, pair, "XLM", 1)]
        #expect(ActivityRecord.groupingSwaps(single, drawers: addresses) == single)
        let three = sameAsset + [transfer("3", hash: "s", pair, main, "USDC", 1)]
        #expect(ActivityRecord.groupingSwaps(three, drawers: addresses) == three)
    }

    @Test("Une ligne écrite par le téléphone n'est jamais regroupée (elle fait déjà foi)")
    func localRecordsUntouched() {
        #expect(ActivityRecord.groupingSwaps([localSwap], drawers: addresses) == [localSwap])
    }

    // MARK: Ligne (I1s)

    @Test("Ligne : « Swapped XLM for USDC », « in Main », tampon SWAPPED, −400 XLM et +99.71 USDC en quantités (fond normal, retour de Barth du 2026-10-14)")
    func row() throws {
        let row = try #require(ActivityViewModel.row(for: localSwap, drawers: drawers, addresses: addresses, cardName: { _ in nil }))
        #expect(row.title == "Swapped XLM for USDC")
        #expect(row.meta.hasSuffix("in Main"))
        #expect(row.stamp == .swapped)
        #expect(row.amount == "\u{2212}\(SendAsset.displayed(400, code: "XLM")) XLM")
        #expect(row.secondaryAmount == "+\(SendAsset.displayed(Decimal(string: "99.71")!, code: "USDC")) USDC", "Tronqué à 2 décimales, jamais en dollars")
    }

    @Test("Total du jour : les deux actifs du swap (ce qui sort, ce qui entre), par actif")
    func dayNet() throws {
        let net = try #require(ActivityViewModel.net(of: [localSwap], filter: .all, addresses: addresses, locale: english))
        #expect(net.text.contains("\u{2212}400 XLM"))
        #expect(net.text.contains("$99.71"))
    }

    // MARK: Reçu (I1s.1)

    @Test("Reçu : In, Gave, Got (exact), Min. guaranteed (exact), Route, Protocol, Fees « On us » ; quantités près du tampon")
    func receipt() async throws {
        let source = MockActivityDataSource(scenario: .standard)
        let model = ActivityViewModel(source: source)
        await model.refresh()
        let record = try #require(model.records.first { $0.event == .swap })
        let receipt = try #require(model.receipt(for: record, locale: english))
        #expect(receipt.title == "Swapped XLM for USDC")
        #expect(receipt.lines.map(\.id) == ["in", "gave", "got", "minimum", "route", "protocol", "fee", "status"])
        #expect(receipt.lines.first { $0.id == "got" }?.value == .positive("99.71 USDC"))
        #expect(receipt.lines.first { $0.id == "minimum" }?.value == .text("99.1816 USDC"))
        #expect(receipt.lines.first { $0.id == "route" }?.value == .text("XLM → USDC"))
        #expect(receipt.lines.first { $0.id == "fee" }?.value == .positive("On us"))
        #expect(receipt.total == nil)
        #expect(receipt.stampAmounts.map(\.text) == ["\u{2212}400 XLM", "+99.71 USDC"])
        #expect(receipt.stamp == .swapped)
        #expect(receipt.send == nil)
        #expect(receipt.swap == SwapPrefill(drawerAddress: MockActivityDataSource.main, given: .xlm, received: .usdc, amount: 400))
        #expect(receipt.shareText.contains("Swapped 400 XLM for 99.71 USDC"))
    }

    // MARK: En attente

    @Test("Swap en attente : en haut de l'Activity, « Swapping XLM for USDC », quantité donnée")
    func pendingSwap() async {
        let source = PendingSwapSource()
        let model = ActivityViewModel(source: source)
        await model.refresh()
        let row = model.tickets.first?.rows.first
        #expect(row?.title == "Swapping XLM for USDC")
        #expect(row?.amount == "\u{2212}400 XLM")
        #expect(row?.stamp == .pending)
    }
}

/// Historique vide avec un swap en attente.
private final class PendingSwapSource: ActivityDataSource {
    let network = StellarNetwork.testnet
    let pendingSend: PendingSend? = PendingSend(
        trace: PaymentTrace(token: "xlm", from: MockReceiveDataSource.mainAddress, destination: "pair", units: 1, nonce: 1, preparedAtLedger: 1, expirationLedger: 121),
        recipient: "router", recipientName: "Soroswap", drawerTitle: "Main account", asset: "xlm", amount: 400, signedAt: .now,
        swap: PendingSwap(receivedAsset: "usdc", expectedReceived: Decimal(string: "99.68")!, minimumReceived: Decimal(string: "99.1816")!, protocolName: "Soroswap")
    )

    func drawers() -> [ActivityDrawer] { [.main(MockReceiveDataSource.mainAddress)] }
    func cardName(key: String) -> String? { nil }
    func cardColor(key: String) -> ChimpCardColor? { nil }
    func storedActivity() -> AccountActivity { AccountActivity() }
    func sync(onProgress: @escaping (AccountActivity) -> Void) async throws -> AccountActivity { AccountActivity() }
    func checkPending(_ pending: PendingSend) async throws -> PaymentCheck { .pending }
    func explorerURL(transactionHash: String) -> URL? { nil }
}
