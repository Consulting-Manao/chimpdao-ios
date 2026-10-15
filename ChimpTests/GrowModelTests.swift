import Foundation
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 4, étape 5 : l'onglet Grow (F1) et les tuiles « GROWING » des tiroirs lisent les positions une fois,
/// une ligne par tiroir (jamais fusionnées), et n'affichent l'évolution que si la base est connue.
struct GrowModelTests {
    private func loaded(_ scenario: MockVaultService.Scenario) async -> GrowModel {
        let model = GrowModel(service: MockVaultService(scenario: scenario, delay: .zero))
        await model.refresh()
        return model
    }

    @Test("Une position dans Main : valeur, évolution réelle depuis le dépôt, la position retrouvée par l'adresse du tiroir")
    func position() async throws {
        let model = await loaded(.normal)
        #expect(model.phase == .loaded)
        #expect(model.holdings.count == 1)
        #expect(model.totalValue == Decimal(string: "50.12"))
        #expect(model.totalChange == Decimal(string: "0.12"))
        let holding = try #require(model.holdings.first)
        #expect(model.holding(drawerAddress: holding.drawerAddress) == holding)
        #expect(model.drawer(address: holding.drawerAddress)?.id == holding.drawerID)
        #expect(model.vault?.protocols == ["DeFindex", "Blend"])
    }

    @Test("Rien qui pousse : aucune ligne, ni valeur ni évolution")
    func empty() async {
        let model = await loaded(.noPosition)
        #expect(model.phase == .loaded)
        #expect(model.holdings.isEmpty)
        #expect(model.totalValue == 0)
        #expect(model.totalChange == nil)
    }

    @Test("Vault muet : « DeFindex isn't answering right now », rien n'est inventé")
    func unavailable() async {
        let model = await loaded(.vaultUnavailable)
        #expect(model.phase == .unavailable)
        #expect(model.context == nil)
        #expect(model.holdings.isEmpty)
    }

    @Test("Évolution inconnue (décision 2) : une base manque, la valeur seule")
    func unknownChange() {
        let known = VaultHolding(
            drawerID: "main", drawerAddress: "GMAIN", shares: 1, value: 10, basis: VaultBasis(putIn: 9, since: .now), readAt: .now
        )
        let unknown = VaultHolding(drawerID: "banana", drawerAddress: "GBANANA", shares: 1, value: 5, basis: nil, readAt: .now)
        #expect(known.change == 1)
        #expect(unknown.change == nil)
        #expect(GrowView.changeText(Decimal(string: "0.12")!, asset: .xlm, locale: Locale(identifier: "en_US")) == "+0.12 XLM")
        #expect(GrowView.changeText(Decimal(string: "-0.03")!, asset: .xlm, locale: Locale(identifier: "en_US")) == "\u{2212}0.03 XLM")
    }
}
