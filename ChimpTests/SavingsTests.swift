import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 5, étape 5 : les CETES par tiroir (F9, F10), l'évolution du prix depuis le swap (prix d'Etherfuse noté
/// sur le téléphone), et la ligne « TAKEN BACK » d'un clawback.
struct SavingsTests {
    private let main = ActivityHistoryTests.account
    private let pool = "CD2TAYCQZEY7U5CTUOV5QSGWHJNN4ZRPRUSMN2KRM2ZE6ZGX5TNU76H2"
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func bought(_ amount: Decimal, price: Decimal?, minutes: Double, hash: String? = nil) -> ActivityRecord {
        .swap(hash: hash ?? "b\(minutes)", drawer: main, venue: pool, givenCode: "USDC", given: 1, receivedCode: "CETES", received: amount,
              minimum: nil, protocolName: "Soroswap", at: start + minutes * 60, receivedPriceUSD: price)
    }

    private func sold(_ amount: Decimal, minutes: Double) -> ActivityRecord {
        .swap(hash: "s\(minutes)", drawer: main, venue: pool, givenCode: "CETES", given: amount, receivedCode: "USDC", received: 1,
              minimum: nil, protocolName: "Soroswap", at: start + minutes * 60)
    }

    // MARK: Base (« Price +0.62% since you got them »)

    @Test("Un swap vers le CETES : le prix d'Etherfuse du moment ; deux swaps : la moyenne pondérée ; date du premier")
    func weighted() throws {
        let records = [bought(100, price: Decimal(string: "0.06")!, minutes: 0), bought(300, price: Decimal(string: "0.062")!, minutes: 10)]
        let basis = try #require(SavingsBasis.from(records: records, drawer: main, code: "CETES", balance: 400))
        #expect(basis.unitPriceUSD == Decimal(string: "0.0615"))
        #expect(basis.since == start)
        #expect(basis.priceChange(now: Decimal(string: "0.0615")!) == 0)
        #expect(basis.priceChange(now: Decimal(string: "0.06273")!) == Decimal(string: "0.02"))
    }

    @Test("Rendre une partie ne change pas le prix moyen ; tout rendre puis racheter : nouvelle position, nouvelle date")
    func disposals() throws {
        var records = [bought(100, price: Decimal(string: "0.06")!, minutes: 0), sold(40, minutes: 5)]
        let partial = try #require(SavingsBasis.from(records: records, drawer: main, code: "CETES", balance: 60))
        #expect(partial.unitPriceUSD == Decimal(string: "0.06"))
        records += [sold(60, minutes: 6), bought(50, price: Decimal(string: "0.07")!, minutes: 20)]
        let fresh = try #require(SavingsBasis.from(records: records, drawer: main, code: "CETES", balance: 50))
        #expect(fresh.unitPriceUSD == Decimal(string: "0.07"))
        #expect(fresh.since == start + 20 * 60)
    }

    @Test("Sans prix noté (swap relu sur la chaîne, prix indisponible), ou solde que l'historique ne retrouve pas : la valeur seule")
    func unknown() {
        #expect(SavingsBasis.from(records: [bought(100, price: nil, minutes: 0)], drawer: main, code: "CETES", balance: 100) == nil)
        let mixed = [bought(100, price: Decimal(string: "0.06")!, minutes: 0), bought(10, price: nil, minutes: 1)]
        #expect(SavingsBasis.from(records: mixed, drawer: main, code: "CETES", balance: 110) == nil)
        #expect(SavingsBasis.from(records: [bought(100, price: Decimal(string: "0.06")!, minutes: 0)], drawer: main, code: "CETES", balance: 120) == nil,
                "20 CETES arrivés hors de l'historique : prix inconnu")
        #expect(SavingsBasis.from(records: [], drawer: main, code: "CETES", balance: 0) == nil)
    }

    @Test("Un clawback retire des jetons sans changer le prix moyen de ceux qui restent")
    func clawbackKeepsPrice() throws {
        let clawback = ActivityRecord(id: "c", event: .clawback, hash: "c", from: main, to: "", assetCode: "CETES", amount: 30,
                                      at: start + 60, isLocal: false)
        let basis = try #require(SavingsBasis.from(
            records: [bought(100, price: Decimal(string: "0.06")!, minutes: 0), clawback], drawer: main, code: "CETES", balance: 70
        ))
        #expect(basis.unitPriceUSD == Decimal(string: "0.06"))
    }

    @Test("La ligne d'un swap garde le prix noté ; un fichier écrit avant (sans ce champ) reste lisible")
    func codable() throws {
        let record = bought(131, price: Decimal(string: "0.061937")!, minutes: 0)
        let decoded = try JSONDecoder().decode(ActivityRecord.self, from: try JSONEncoder().encode(record))
        #expect(decoded.receivedPriceUSD == Decimal(string: "0.061937"))
        var old = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(record)) as! [String: Any]
        old.removeValue(forKey: "receivedPriceUSD")
        let legacy = try JSONDecoder().decode(ActivityRecord.self, from: try JSONSerialization.data(withJSONObject: old))
        #expect(legacy.receivedPriceUSD == nil)
    }

    // MARK: Clawback (« TAKEN BACK »)

    /// Un vrai clawback de testnet (ledger 5 099 650, 2026-10-15) : `[clawback, détenteur, actif]`, 1 000 000 de jetons.
    static let clawbackTopics = [
        "AAAADwAAAAhjbGF3YmFjaw==",
        "AAAAEgAAAAAAAAAAbt6fDJO9l9K/sMgP1NpYPxZY7WmWJ05xoLAHjAK4tMg=",
        "AAAADgAAAENQSDE0MzYwOTAwOkdEVFdRWlY2QkRHNVFUNlhBSjVQRlVOUFBKRDdGSlRNTDRZWFlGS1c3RzNDQzVCSU4zQ1ZKU1JTAA==",
    ]
    static let clawbackValue = "AAAACgAAAAAAAAAAAAAJGE5yoAA="
    static let clawbackContract = "CA4DOJL63YDCNLGQXZDRSAE3NBGHSQJQIRGNY5DATCAUYGDDKT3PXGTC"

    @Test("Clawback relu sur la chaîne : une ligne « TAKEN BACK », seulement pour un actif de la liste blanche et un tiroir")
    func clawbackEvent() throws {
        let holder = try #require(try SCValXDR.fromXdr(base64: Self.clawbackTopics[1]).address?.toStrKey())
        let event = ChimpDAO.SorobanClient.ContractEvent(
            id: "9-0", contractID: Self.clawbackContract, ledger: 5_099_650, ledgerClosedAt: "2026-10-15T10:00:00Z", transactionHash: "hc",
            topics: Self.clawbackTopics, value: Self.clawbackValue
        )
        func records(_ assets: [String: String], drawers: Set<String>) -> [ActivityRecord] {
            ChainActivityHistory.records(from: [event], account: main, drawers: drawers, assets: assets, known: [])
        }
        let row = try #require(records([Self.clawbackContract: "CETES"], drawers: [holder]).first)
        #expect(row.event == .clawback)
        #expect(row.from == holder)
        #expect(row.amount == 1_000_000)
        #expect(row.assetCode == "CETES")
        #expect(row.kind(drawers: [holder]) == .takenBack)
        #expect(records([:], drawers: [holder]).isEmpty, "Un actif hors liste blanche est ignoré")
        #expect(records([Self.clawbackContract: "CETES"], drawers: [main]).isEmpty, "Pas un de nos tiroirs")
        #expect(try ChainActivityHistory.filterGroups(drawers: [holder], clawbackContracts: [Self.clawbackContract]).flatMap { $0 }.contains { filter in
            filter.contractIds == [Self.clawbackContract] && filter.topics?.first?.segmentMatchers == [ChainActivityHistory.clawbackTopic, "*", "*"]
        })
    }

    @Test("Ligne « Etherfuse took back 30 CETES », tampon TAKEN BACK, −30 CETES ; le total du jour baisse ; reçu sans « again »")
    @MainActor
    func clawbackRow() async throws {
        let main = MockReceiveDataSource.mainAddress
        let clawback = ActivityRecord(id: "c", event: .clawback, hash: "c", from: main, to: "", assetCode: "CETES", amount: 30,
                                      at: start, isLocal: false)
        let drawers: [ActivityDrawer] = [.main(main)]
        let row = try #require(ActivityViewModel.row(for: clawback, drawers: drawers, addresses: [main], cardName: { _ in nil }))
        #expect(row.title == "Etherfuse took back 30 CETES")
        #expect(row.stamp == .takenBack)
        #expect(row.amount == "\u{2212}30 CETES")
        let net = try #require(ActivityViewModel.net(of: [clawback], filter: .all, addresses: [main]))
        #expect(net.text.hasPrefix("\u{2212}"))
        let model = ActivityViewModel(source: MockActivityDataSource(scenario: .standard))
        await model.refresh()
        let receipt = try #require(model.receipt(for: clawback))
        #expect(receipt.lines.map(\.id) == ["by", "from", "amount", "status"])
        #expect(receipt.again == nil)
        #expect(receipt.shareText.contains("Etherfuse took back"))
    }

    // MARK: Grow

    @Test("Grow : CETES du Main (1 820,40), prix +0,62 % depuis le swap ; une ligne par tiroir ; gel ; prix indisponible")
    func growModel() async throws {
        func load(_ scenario: MockSavingsService.Scenario) async -> GrowModel {
            let model = GrowModel(service: MockVaultService(delay: .zero), savingsService: MockSavingsService(scenario: scenario, delay: .zero))
            await model.refresh()
            return model
        }
        let normal = await load(.normal)
        let holding = try #require(normal.savings(.etherfuse)?.holdings.first)
        #expect(holding.amount == Decimal(string: "1820.4"))
        let change = try #require(holding.priceChange(normal.savingsPrice("CETES")))
        #expect((change * 10_000).truncated(to: 0) == 62)
        #expect(normal.savingsHolding(drawerAddress: holding.drawerAddress, code: "CETES") == holding)
        #expect((await load(.twoDrawers)).savings(.etherfuse)?.holdings.count == 2)
        #expect((await load(.frozen)).savings(.etherfuse)?.holdings.first?.frozen == true)
        let unavailable = await load(.priceUnavailable)
        #expect(unavailable.savingsPrice("CETES") == nil)
        #expect(unavailable.savings(.etherfuse)?.holdings.first?.priceChange(unavailable.savingsPrice("CETES")) == nil)
        #expect((await load(.unknownBasis)).savings(.etherfuse)?.holdings.first?.priceChange(MockSavingsService.price) == nil)
        #expect((await load(.none)).savings(.etherfuse)?.holdings.isEmpty == true)
    }
}
