import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 6, étape 1 : une arrivée d'USDC par Circle CCTP dans l'Activity (« ARRIVED », « from Ethereum · via
/// Circle CCTP », décision de Barth du 2026-10-15). Vecteur : le premier vrai transfert Sepolia → Stellar de
/// `CCTPMessageTests` (2 USDC vers `GBCQ…V5KK`).
struct ActivityArrivalTests {
    private let cctp = IntegrationConfig.testnet.cctp
    private let drawer = "GBCQATHVGEMQWIP3HANAMXICFDZRABAIJTGKLLJ2FX4L7VH6AXVDV5KK"

    private func transfer(from: String, to: String, amount: Decimal = 2) -> ActivityRecord {
        ActivityRecord(id: "stellar:h:1", event: .transfer, hash: CCTPMessageTests.vectors[0].stellarTx, from: from, to: to,
                       assetCode: "USDC", amount: amount, at: Date(timeIntervalSince1970: 1_791_000_000), isLocal: false, ledger: 5_100_000)
    }

    private final class Source: ActivityEventSource {
        let arguments: [SCValXDR]?
        init(arguments: [SCValXDR]?) { self.arguments = arguments }
        func latestLedger() async throws -> UInt32 { 0 }
        func contractEvents(filters: [EventFilter], startLedger: UInt32, endLedger: UInt32, pageLimit: Int) async throws -> ChimpDAO.SorobanClient.EventRange {
            throw StellarError.rpc("unused")
        }
        func invocationArguments(_ hash: String) async throws -> [SCValXDR]? { arguments }
    }

    @Test("Un transfert venu du CctpForwarder vers un tiroir est une arrivée ; d'ailleurs, un paiement reçu comme avant")
    func classification() {
        let rows = ActivityRecord.classifyingArrivals(
            [transfer(from: cctp.forwarder, to: drawer), transfer(from: "GDZE7UWGO3PS6R6RI6F3XIJLX7WGIEFD3X4YQO4AJH4LS3KDY6LLFXG2", to: drawer)],
            forwarder: cctp.forwarder, drawers: [drawer]
        )
        #expect(rows[0].event == .bridgeArrival)
        #expect(rows[0].kind(drawers: [drawer]) == .arrived)
        #expect(rows[0].protocolName == "Circle CCTP")
        #expect(rows[1].event == .transfer)
        #expect(rows[1].kind(drawers: [drawer]) == .received)
    }

    @Test("Détails lus dans le vrai message : Ethereum, 0x2226…d55c, frais 0 ; un message qui ne désigne pas ce tiroir : aucun détail")
    func details() async throws {
        let message = try #require(Data(hex: CCTPMessageTests.vectors[0].message))
        let arrival = ActivityRecord.classifyingArrivals([transfer(from: cctp.forwarder, to: drawer)], forwarder: cctp.forwarder, drawers: [drawer])
        let history = ChainActivityHistory(source: Source(arguments: [.bytes(message), .bytes(Data(count: 65))]), assets: [], cctp: cctp)
        let detailed = try #require(await history.detailingArrivals(arrival).first)
        #expect(detailed.sourceChain == "Ethereum")
        #expect(detailed.sourceAddress == "0x222650f98a19d45b1275842786d4319f5d39d55c")
        #expect(detailed.bridgeFee == 0)
        // Autre tiroir, autre montant, transaction illisible : la ligne reste une arrivée, sans détails inventés.
        let elsewhere = ActivityRecord.classifyingArrivals(
            [transfer(from: cctp.forwarder, to: "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB")],
            forwarder: cctp.forwarder, drawers: ["CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"]
        )
        #expect(try #require(await history.detailingArrivals(elsewhere).first).sourceChain == nil)
        let wrongAmount = ActivityRecord.classifyingArrivals([transfer(from: cctp.forwarder, to: drawer, amount: 3)], forwarder: cctp.forwarder, drawers: [drawer])
        #expect(try #require(await history.detailingArrivals(wrongAmount).first).sourceChain == nil)
        let unreadable = ChainActivityHistory(source: Source(arguments: nil), assets: [], cctp: cctp)
        let plain = try #require(await unreadable.detailingArrivals(arrival).first)
        #expect(plain.event == .bridgeArrival && plain.sourceChain == nil)
    }

    @Test("Ligne « Arrived in … », « from Ethereum · via Circle CCTP », tampon ARRIVED ; ni « Send back » ni « Pay again »")
    func row() throws {
        var arrival = try #require(ActivityRecord.classifyingArrivals([transfer(from: cctp.forwarder, to: drawer)], forwarder: cctp.forwarder, drawers: [drawer]).first)
        arrival.sourceChain = "Ethereum"
        let row = try #require(ActivityViewModel.row(for: arrival, drawers: [.main(drawer)], addresses: [drawer], cardName: { _ in nil }))
        #expect(row.stamp == .arrived)
        #expect(row.meta.hasSuffix("from Ethereum · via Circle CCTP"))
        #expect(row.tone == .positive)
        #expect(ActivityViewModel.prefill(for: arrival, kind: .arrived) == nil)
        arrival.sourceChain = nil
        #expect(ActivityViewModel.arrivalLine(arrival) == "from another chain · via Circle CCTP")
        let net = try #require(ActivityViewModel.net(of: [arrival], filter: .all, addresses: [drawer]))
        #expect(net.tone == .positive)
    }

    @Test("Reçu : From, Sent by (copiable), Into, Amount, Circle fee, Via ; partage « arrived from Ethereum »")
    @MainActor
    func receipt() async throws {
        let main = MockReceiveDataSource.mainAddress
        var arrival = try #require(ActivityRecord.classifyingArrivals([transfer(from: cctp.forwarder, to: main)], forwarder: cctp.forwarder, drawers: [main]).first)
        arrival.sourceChain = "Ethereum"
        arrival.sourceAddress = "0x222650f98a19d45b1275842786d4319f5d39d55c"
        arrival.bridgeFee = 0
        let model = ActivityViewModel(source: MockActivityDataSource(scenario: .standard))
        await model.refresh()
        let receipt = try #require(model.receipt(for: arrival))
        #expect(receipt.lines.map(\.id) == ["fromChain", "sender", "into", "amount", "bridgeFee", "via", "status"])
        #expect(receipt.counterparty?.address == "0x222650f98a19d45b1275842786d4319f5d39d55c")
        #expect(receipt.again == nil)
        #expect(receipt.shareText.contains("arrived from Ethereum"))
    }
}
