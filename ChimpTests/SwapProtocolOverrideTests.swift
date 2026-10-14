import Foundation
import Testing
@testable import ChimpDAO

#if DEBUG
/// Réglage caché du catalogue (Debug) : forcer Soroswap ou Aquarius pour prouver un swap Soroswap sur testnet (D2).
@MainActor
struct SwapProtocolOverrideTests {
    @Test("Réglage gardé sur le téléphone ; « automatique » efface la clé ; identifiant de l'adaptateur forcé")
    func persistence() {
        let saved = UserDefaults.standard.string(forKey: SwapProtocolOverride.defaultsKey)
        defer { UserDefaults.standard.set(saved, forKey: SwapProtocolOverride.defaultsKey) }

        SwapProtocolOverride.current = .soroswap
        #expect(SwapProtocolOverride.current == .soroswap)
        #expect(SwapProtocolOverride.current.protocolID == "soroswap")
        SwapProtocolOverride.current = .aquarius
        #expect(SwapProtocolOverride.current.protocolID == "aquarius")
        SwapProtocolOverride.current = .automatic
        #expect(UserDefaults.standard.string(forKey: SwapProtocolOverride.defaultsKey) == nil)
        #expect(SwapProtocolOverride.current.protocolID == nil)
        // Les identifiants sont ceux des vrais adaptateurs.
        #expect(SwapProtocolOverride.soroswap.protocolID == SoroswapAdapter(contracts: IntegrationConfig.testnet.soroswap, reader: SimulationReader(client: SorobanClient(config: .testnet), source: ChimpNetworkConfig.testnet.feePayer)).id)
    }

    @Test("Protocole forcé : E3 le dit (« Soroswap only »), même si l'autre a répondu")
    func forcedComparison() {
        var quote = SwapQuoteSummary(
            protocolID: "soroswap", protocolName: "Soroswap", given: .xlm, received: .usdc, amountIn: 10,
            expectedOutUnits: 10_619_368, route: [.xlm, .usdc], routeContracts: [], priceImpactBasisPoints: 30,
            comparedProtocols: ["Soroswap"]
        )
        #expect(quote.comparison == nil)
        quote.isForcedForDebug = true
        #expect(quote.comparison == .forced("Soroswap"))
    }
}
#endif
