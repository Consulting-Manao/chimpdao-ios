import Foundation
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 4, étape 2 : dépôts et retraits du vault dans l'Activity (maquettes I1g, I1g.1, I1g.2) et
/// l'évolution d'une position depuis le dépôt (`VaultBasis`).
struct ActivityVaultTests {
    private let main = MockReceiveDataSource.mainAddress
    private let jungle = MockReceiveDataSource.jungleAddress
    private let vault = "CCLV4H7WTLJQ7ATLHBBQV2WW3OINF3FOY5XZ7VPHZO7NH3D2ZS4GFSF6"
    private let label = ActivityRecord.VaultLabel(name: "DeFindex XLM", protocols: "DeFindex → Blend")
    private var drawers: [ActivityDrawer] { [.main(main), .card(jungle, name: "Jungle", color: .jungle)] }
    private var addresses: Set<String> { Set(drawers.map(\.address)) }
    private let day: TimeInterval = 86_400
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func transfer(_ hash: String, _ from: String, _ to: String, _ amount: Decimal) -> ActivityRecord {
        ActivityRecord(id: "stellar:\(hash):1", event: .transfer, hash: hash, from: from, to: to, assetCode: "XLM", amount: amount, at: start, isLocal: false, ledger: 9)
    }

    private func deposit(_ amount: Decimal, shares: Decimal?, days: Double, drawer: String? = nil) -> ActivityRecord {
        .vaultDeposit(hash: "d\(days)", drawer: drawer ?? main, vault: vault, label: label, assetCode: "XLM", amount: amount, shares: shares, at: start + days * day)
    }

    private func withdrawal(_ received: Decimal, shares: Decimal?, days: Double) -> ActivityRecord {
        .vaultWithdraw(hash: "w\(days)", drawer: main, vault: vault, label: label, assetCode: "XLM", received: received, shares: shares, at: start + days * day)
    }

    // MARK: Classement

    @Test("Relu sur la chaîne : vers le vault, un dépôt ; depuis le vault, un retrait ; ailleurs, inchangé")
    func classification() {
        let records = [transfer("a", main, vault, 50), transfer("b", vault, jungle, Decimal(string: "10.02")!), transfer("c", main, "CBVFU7RVGHQQM2CXT4RQM6H276GSUZQB65RKTL6HR2GQIE4DYHITJIST", 1)]
        let classified = ActivityRecord.classifyingVaults(records, vaults: [vault: label], drawers: addresses)
        #expect(classified[0].event == .vaultDeposit)
        #expect(classified[0].kind(drawers: addresses) == .deposited)
        #expect(classified[0].vaultName == "DeFindex XLM" && classified[0].protocolName == "DeFindex → Blend")
        #expect(classified[0].shares == nil)
        #expect(classified[1].event == .vaultWithdraw)
        #expect(classified[1].kind(drawers: addresses) == .withdrawn)
        #expect(classified[2] == records[2])
        let local = deposit(50, shares: 1, days: 0)
        #expect(ActivityRecord.classifyingVaults([local], vaults: [vault: label], drawers: addresses) == [local])
    }

    @Test("Ligne de dépôt (I1g) : « Put money in », « Main → vault », DEPOSITED, −50 XLM en quantité")
    func depositRow() throws {
        let row = try #require(ActivityViewModel.row(for: deposit(50, shares: 0.03, days: 0), drawers: drawers, addresses: addresses, cardName: { _ in nil }))
        #expect(row.title == "Put money in")
        #expect(row.meta.hasSuffix("Main → vault"))
        #expect(row.stamp == .deposited)
        #expect(row.amount == "\u{2212}\(SendAsset.displayed(50, code: "XLM")) XLM")
        #expect(row.tone == .neutral)
    }

    @Test("Ligne de retrait (I1g) : « Took money out », « vault → Jungle », WITHDRAWN, +10.02 XLM")
    func withdrawalRow() throws {
        let record = ActivityRecord.vaultWithdraw(hash: "w", drawer: jungle, vault: vault, label: label, assetCode: "XLM", received: Decimal(string: "10.02")!, shares: nil, at: start)
        let row = try #require(ActivityViewModel.row(for: record, drawers: drawers, addresses: addresses, cardName: { _ in nil }))
        #expect(row.title == "Took money out")
        #expect(row.meta.hasSuffix("vault → Jungle"))
        #expect(row.stamp == .withdrawn)
        #expect(row.amount == "+\(SendAsset.displayed(Decimal(string: "10.02")!, code: "XLM")) XLM")
        #expect(row.tone == .positive)
    }

    @Test("Total du jour : un dépôt sort du tiroir, un retrait y entre")
    func dayNet() throws {
        let net = try #require(ActivityViewModel.net(of: [deposit(50, shares: nil, days: 0), withdrawal(20, shares: nil, days: 0)], filter: .all, addresses: addresses))
        #expect(net.text == "\u{2212}\(SendAsset.displayed(30, code: "XLM")) XLM")
    }

    @Test("Reçu d'un dépôt (I1g.1) : From, Put in, Shares, Vault, Protocols, Fees « On us » ; pas de total, la quantité au tampon")
    @MainActor
    func depositReceipt() async throws {
        let model = ActivityViewModel(source: MockActivityDataSource(scenario: .standard))
        await model.refresh()
        let receipt = try #require(model.receipt(for: deposit(50, shares: Decimal(string: "0.0299819")!, days: 0)))
        #expect(receipt.lines.map(\.id) == ["from", "putIn", "shares", "vault", "protocols", "fee", "status"])
        #expect(receipt.total == nil)
        #expect(receipt.stamp == .deposited)
        #expect(receipt.stampAmounts.map(\.text) == ["\u{2212}\(SendAsset.displayed(50, code: "XLM")) XLM"])
        #expect(receipt.again == .seePosition(drawerAddress: main), "« See my position » (validé le 2026-10-15)")
        #expect(receipt.vaultProtocols == ["DeFindex", "Blend"] && receipt.vaultAsset == "XLM", "L'avertissement sous le reçu")
        #expect(receipt.shareText.contains("Planted"))
        #expect(!receipt.shareText.contains("%"), "Aucun taux, même dans le partage")
    }

    @Test("Reçu d'un retrait (I1g.2) : Back to, Gave back (parts), Got, Vault, Protocols")
    @MainActor
    func withdrawalReceipt() async throws {
        let model = ActivityViewModel(source: MockActivityDataSource(scenario: .standard))
        await model.refresh()
        let receipt = try #require(model.receipt(for: withdrawal(Decimal(string: "10.02")!, shares: Decimal(string: "0.006")!, days: 0)))
        #expect(receipt.lines.map(\.id) == ["backTo", "gaveBack", "got", "vault", "protocols", "fee", "status"])
        #expect(receipt.stamp == .withdrawn)
        #expect(receipt.again == .seePosition(drawerAddress: main), "La position du tiroir où l'argent est revenu")
        #expect(receipt.again?.sendPrefill == nil && receipt.again?.swapPrefill == nil, "Ni Envoyer ni Swap")
    }

    @Test("Ticket du jour (I1g) : « via DeFindex → Blend » et l'avertissement à la place du sceau, seulement les jours du vault")
    func vaultDayTicket() {
        let earlier = ActivityRecord(id: "stellar:t:1", event: .transfer, hash: "t", from: main, to: jungle, assetCode: "XLM", amount: 5, at: start - day, isLocal: false, ledger: 8)
        let records = [deposit(50, shares: nil, days: 0), earlier]
        let tickets = ActivityViewModel.tickets(
            for: records, filter: .all, drawers: drawers, cardName: { _ in nil }, calendar: .current, now: start + day
        )
        #expect(tickets.count == 2)
        #expect(tickets[0].vaultProtocols == "DeFindex → Blend" && tickets[0].vaultAsset == "XLM")
        #expect(tickets[1].vaultProtocols == nil, "Un jour sans ligne du vault garde son sceau")
    }

    // MARK: Évolution depuis le dépôt

    @Test("Base : un dépôt, puis un autre ; date du premier ; évolution = valeur − mis")
    func basisDeposits() throws {
        let basis = try #require(VaultBasis.from(records: [deposit(50, shares: 3, days: 0), deposit(30, shares: 2, days: 5)], drawer: main, vault: vault))
        #expect(basis.putIn == 80)
        #expect(basis.since == start)
        #expect(basis.change(value: Decimal(string: "80.12")!) == Decimal(string: "0.12"))
        #expect(basis.change(value: 79) == -1, "Une perte se montre aussi")
    }

    @Test("Retrait partiel aux parts connues : la base baisse au prorata des parts (le gain reste visible)")
    func basisProportional() throws {
        // 100 XLM pour 10 parts ; la moitié des parts rend 55 XLM : il reste 50 « mis », pas 45.
        let basis = try #require(VaultBasis.from(records: [deposit(100, shares: 10, days: 0), withdrawal(55, shares: 5, days: 3)], drawer: main, vault: vault))
        #expect(basis.putIn == 50)
        #expect(basis.since == start)
    }

    @Test("Retrait sans parts connues : la base baisse de ce qui est revenu ; retrait total : nouvelle position, nouvelle date")
    func basisWithoutShares() throws {
        let partial = try #require(VaultBasis.from(records: [deposit(100, shares: nil, days: 0), withdrawal(40, shares: nil, days: 2)], drawer: main, vault: vault))
        #expect(partial.putIn == 60)
        let restarted = try #require(VaultBasis.from(records: [
            deposit(100, shares: 10, days: 0), withdrawal(101, shares: 10, days: 2), deposit(20, shares: 2, days: 4),
        ], drawer: main, vault: vault))
        #expect(restarted.putIn == 20)
        #expect(restarted.since == start + 4 * day)
    }

    @Test("Pas de base : aucun dépôt connu, ou tout retiré ; un autre tiroir ne compte pas")
    func noBasis() {
        #expect(VaultBasis.from(records: [], drawer: main, vault: vault) == nil)
        #expect(VaultBasis.from(records: [deposit(10, shares: 1, days: 0), withdrawal(10, shares: 1, days: 1)], drawer: main, vault: vault) == nil)
        #expect(VaultBasis.from(records: [deposit(10, shares: 1, days: 0, drawer: jungle)], drawer: main, vault: vault) == nil)
    }
}
