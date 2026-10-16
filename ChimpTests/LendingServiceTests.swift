import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Phase 7, étape 2 : le service XOXNO derrière les écrans du vault (positions par tiroir, retirable, blocages, Activity).
struct LendingServiceTests {
    private let market = IntegrationConfig.testnet.xoxno
    private let usdc = "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA"
    private let main = "CASBWZTE3GU4VVBC2Q3V6VXCHTG7VLHG45AJXEJ64IVNQSDLEDRBD3RP"


    private func adapter() -> XoxnoAdapter {
        XoxnoAdapter(market: market, asset: IntegrationAsset(code: "USDC", contract: usdc), reader: SimulationReader(client: SorobanClient(config: .testnet), source: ChimpNetworkConfig.testnet.feePayer), ledger: SorobanXoxnoLedger(client: SorobanClient(config: .testnet)))
    }

    private func state(cash: Int128 = 16_316_920_593, paused: Bool = false, frozen: Bool = false, capLeft: Int128 = 70_000_000_000) -> XoxnoMarketState {
        XoxnoMarketState(
            supplied: 24_778_939_190, borrowed: 8_462_018_598, cash: cash, maxUtilization: 950_000_000_000_000_000_000_000_000,
            paused: paused, frozen: frozen, supplyCap: 100_000_000_000, suppliedInSpoke: 100_000_000_000 - capLeft
        )
    }

    @Test("Le marché devient un « vault » de prêt : retirable maintenant, réserve comme adresse, dépôts bloqués par le gel, la pause ou le plafond")
    func info() {
        let info = ChainLendingService.info(adapter: adapter(), asset: .usdc, state: state())
        #expect(info.kind == .lending)
        #expect(info.id == market.pool)
        #expect(info.name == "XOXNO USDC")
        #expect(info.protocols == ["XOXNO"])
        #expect(info.availableNow == SwapUnits.amount(fromUnits: state().marketWithdrawable))
        #expect(!info.depositsBlocked && !info.withdrawalsBlocked)
        #expect(ChainLendingService.info(adapter: adapter(), asset: .usdc, state: state(frozen: true)).depositsBlocked)
        #expect(!ChainLendingService.info(adapter: adapter(), asset: .usdc, state: state(frozen: true)).withdrawalsBlocked)
        let paused = ChainLendingService.info(adapter: adapter(), asset: .usdc, state: state(paused: true))
        #expect(paused.depositsBlocked && paused.withdrawalsBlocked)
        #expect(ChainLendingService.info(adapter: adapter(), asset: .usdc, state: state(capLeft: 0)).depositsBlocked)
    }

    @Test("Positions d'un tiroir : la déplaçable d'abord ; à renouveler et avec dette gardées, jamais disparues")
    func holdings() async throws {
        let drawer = try await MockSendService(delay: .zero, nfcDelay: .zero).fetchContext().drawers[0]
        let positions = [
            XoxnoPosition(accountID: 5, holder: drawer.address, status: .needsRenewal),
            XoxnoPosition(accountID: 7, holder: drawer.address, status: .live(value: 30, spokeID: 1, hasDebt: true)),
            XoxnoPosition(accountID: 54, holder: drawer.address, status: .live(value: 10_000_000, spokeID: 1, hasDebt: false)),
        ]
        let holdings = ChainLendingService.holdings(positions, drawer: drawer, records: [], pool: market.pool)
        #expect(holdings.map(\.condition) == [.movable, .hasDebt, .needsRenewal])
        #expect(holdings[0].value == 1)
        let context = VaultContext(network: .testnet, drawers: [drawer], vault: MockVaultService.vault, holdings: holdings.reversed())
        #expect(context.holding(drawerID: drawer.id)?.condition == .movable)
        let onlyExpired = VaultContext(network: .testnet, drawers: [drawer], vault: MockVaultService.vault, holdings: holdings.filter { $0.condition == .needsRenewal })
        #expect(onlyExpired.holding(drawerID: drawer.id)?.condition == .needsRenewal)
    }

    @Test("Montant revenu lu dans la valeur rendue par withdraw")
    func withdrawn() throws {
        let key = try XoxnoCalls.hubAssetKey(asset: usdc, hubID: 1)
        #expect(ChainLendingService.withdrawn(.vec([.vec([key, ContractArgument.i128(200_169_268)])])) == 200_169_268)
        #expect(ChainLendingService.withdrawn(.vec([])) == nil)
    }

    @Test("Activity : un transfert vers la réserve XOXNO est un dépôt « XOXNO USDC », via XOXNO")
    func activityLabel() {
        let labels = ChimpNetworkConfig.testnet.vaultLabels
        #expect(labels[market.pool] == ActivityRecord.VaultLabel(name: "XOXNO USDC", protocols: "XOXNO"))
        let rows = ActivityRecord.classifyingVaults(
            [ActivityRecord(id: "stellar:h:1", event: .transfer, hash: "h", from: main, to: market.pool, assetCode: "USDC", amount: 1, at: .now, isLocal: false)],
            vaults: labels, drawers: [main]
        )
        #expect(rows.first?.event == .vaultDeposit)
        #expect(rows.first?.vaultName == "XOXNO USDC")
    }

    @Test("F4 : plusieurs positions d'un tiroir, regroupées ; un retrait vise la plus grosse")
    func groupedPositions() async throws {
        let drawer = try await MockSendService(delay: .zero, nfcDelay: .zero).fetchContext().drawers[0]
        let positions = [
            XoxnoPosition(accountID: 54, holder: drawer.address, status: .live(value: 10_000_000, spokeID: 1, hasDebt: false)),
            XoxnoPosition(accountID: 60, holder: drawer.address, status: .live(value: 150_000_000, spokeID: 1, hasDebt: false)),
            XoxnoPosition(accountID: 5, holder: drawer.address, status: .needsRenewal),
        ]
        let holdings = ChainLendingService.holdings(positions, drawer: drawer, records: [], pool: market.pool)
        #expect(holdings.map(\.value) == [15, 1, 0], "La plus grosse position déplaçable d'abord")
        let groups = LendingDrawerGroup.grouped(holdings)
        #expect(groups.count == 1)
        #expect(groups[0].value == 16, "Une position à renouveler n'est jamais comptée (ni à zéro)")
        #expect(groups[0].needsRenewal && !groups[0].hasDebt)
        let context = VaultContext(network: .testnet, drawers: [drawer], vault: MockLendingService().market, holdings: holdings)
        #expect(context.holding(drawerID: drawer.id)?.value == 15)
    }
}
