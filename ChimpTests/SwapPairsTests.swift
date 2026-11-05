import Foundation
import Testing
@testable import ChimpDAO

/// Choisir un actif sans route vers l'autre côté met en face un partenaire qui en a une (retour de Barth, 2026-11-05).
/// Routes du testnet relevées le 2026-11-05 (un devis demandé pour chaque paire).
struct SwapPairsTests {
    @Test("Testnet : les paires qui ont une route, dans les deux sens")
    func testnetRoutes() {
        let routable: [(String, String)] = [
            ("XLM", "USDC"), ("XLM", "CETES"), ("USDC", "CETES"), ("USDC", "USDY"), ("USDC", "SolvBTC"), ("SolvBTC", "xSolvBTC"),
        ]
        for (first, second) in routable {
            #expect(SwapPairs.canSwap(first, second, on: .testnet), "\(first) ↔ \(second)")
            #expect(SwapPairs.canSwap(second, first, on: .testnet), "\(second) ↔ \(first)")
        }
        let none: [(String, String)] = [
            ("XLM", "USDY"), ("XLM", "SolvBTC"), ("XLM", "xSolvBTC"), ("USDC", "xSolvBTC"), ("CETES", "USDY"), ("USDY", "SolvBTC"),
        ]
        for (first, second) in none {
            #expect(!SwapPairs.canSwap(first, second, on: .testnet), "\(first) ↔ \(second)")
        }
    }

    @Test("Mainnet : rien n'est restreint tant que ses routes ne sont pas relevées")
    func mainnetOpen() {
        #expect(SwapPairs.canSwap("XLM", "USDY", on: .mainnet))
        #expect(SwapPairs.partner(for: "USDY", replacing: "XLM", on: .mainnet) == nil)
    }

    @Test("Le partenaire : l'USDC si possible, sinon le seul possible ; rien quand la paire a déjà une route")
    func partner() {
        #expect(SwapPairs.partner(for: "USDY", replacing: "XLM", on: .testnet) == "USDC")
        #expect(SwapPairs.partner(for: "SolvBTC", replacing: "CETES", on: .testnet) == "USDC")
        #expect(SwapPairs.partner(for: "xSolvBTC", replacing: "XLM", on: .testnet) == "SolvBTC")
        #expect(SwapPairs.partner(for: "xSolvBTC", replacing: "USDC", on: .testnet) == "SolvBTC")
        #expect(SwapPairs.partner(for: "XLM", replacing: "USDY", on: .testnet) == "USDC")
        #expect(SwapPairs.partner(for: "SolvBTC", replacing: "xSolvBTC", on: .testnet) == nil)
        #expect(SwapPairs.partner(for: "USDC", replacing: "XLM", on: .testnet) == nil)
    }

    @Test("Écran Swap : choisir USDY, SolvBTC ou xSolvBTC change l'autre côté tout seul")
    func choosing() async {
        let model = SwapFlowModel(service: MockSwapService(delay: .zero), quoteDebounce: .zero)
        await model.loadIfNeeded()
        #expect(model.given == .xlm && model.received == .usdc)

        model.choose(.usdy, for: .received)
        #expect(model.given == .usdc && model.received == .usdy)

        model.choose(.xsolvbtc, for: .received)
        #expect(model.given == .solvbtc && model.received == .xsolvbtc)

        model.choose(.usdc, for: .received)
        #expect(model.given == .solvbtc && model.received == .usdc, "SolvBTC → USDC a une route : rien ne change")

        model.choose(.xlm, for: .given)
        #expect(model.given == .xlm && model.received == .usdc)

        model.choose(.usdy, for: .given)
        #expect(model.given == .usdy && model.received == .usdc)

        model.choose(.cetes, for: .received)
        #expect(model.given == .usdc && model.received == .cetes, "USDY → CETES n'a pas de route : on donne de l'USDC")
    }
}
