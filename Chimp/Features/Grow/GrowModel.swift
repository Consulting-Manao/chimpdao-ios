import Foundation
import Observation

/// Les positions du compte dans le vault, lues une fois et partagées par l'onglet Grow (F1, F6) et les pages des
/// tiroirs (tuiles « GROWING » de B2 et B3). Une ligne par tiroir, jamais de fusion (décision de Barth du 2026-10-15).
@Observable
final class GrowModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// « DeFindex isn't answering right now. Your money stays in the vault. » + « Try again ».
        case unavailable
    }

    private(set) var phase: Phase = .loading
    private(set) var context: VaultContext?
    private(set) var technicalDetails: String?

    /// Économies (CETES et USDY, F9 et F10) : lues à part, une panne du vault ne les cache pas (et inversement).
    private(set) var savingsPhase: Phase = .loading
    /// Un contexte par actif dont le prix pousse, dans l'ordre du service (CETES, USDY).
    private(set) var savings: [SavingsContext] = []
    private(set) var savingsDetails: String?

    let service: VaultService
    let savingsService: SavingsService?
    /// Prêt XOXNO (phase 7) : le même modèle, sur le service de prêt ; lu à part, une panne de l'un ne cache pas l'autre.
    let lending: GrowModel?
    /// Vault Sentora (2026-11-05) : le même modèle, sur son service ; lu à part lui aussi.
    let sentora: GrowModel?
    /// Vault xSolvBTC de Solv (2026-11-05) : le même modèle, sur son service.
    let solv: GrowModel?
    /// Prix du SolvBTC en dollars (RedStone) : seulement pour le total de l'en-tête, quand un pot Solv existe.
    private let solvPricing: StablebondWalletPrices?
    private(set) var btcUSD: Decimal?
    /// Prix du XLM en dollars (oracle Reflector, lecture seule) : seulement pour le total « grown in total » (G1).
    private let priceOracle: PriceOracle?
    private(set) var xlmUSD: Decimal?
    /// Les valeurs relevées une fois par jour (courbe et « THIS WEEK » de G2).
    let history: PotHistoryStore?
    private var loadTask: Task<Void, Never>?

    init(
        service: VaultService, savingsService: SavingsService? = nil, lendingService: VaultService? = nil,
        sentoraService: VaultService? = nil, solvService: VaultService? = nil, solvPricing: StablebondWalletPrices? = nil,
        priceOracle: PriceOracle? = nil, history: PotHistoryStore? = nil
    ) {
        self.service = service
        self.savingsService = savingsService
        lending = lendingService.map { GrowModel(service: $0) }
        sentora = sentoraService.map { GrowModel(service: $0) }
        solv = solvService.map { GrowModel(service: $0) }
        self.solvPricing = solvPricing
        self.priceOracle = priceOracle
        self.history = history
    }

    // MARK: Pots (maquette « Chimp Grow Final »)

    /// Un pot par protocole et par tiroir.
    var pots: [GrowPot] {
        GrowPots.build(vault: context, lending: lending?.context, savings: savings, sentora: sentora?.context, solv: solv?.context)
    }

    /// Le contexte d'un pot d'actif d'émetteur (`.etherfuse`, `.ondo`).
    func savings(_ mark: ChimpPotProtocol) -> SavingsContext? {
        savings.first { $0.mark == mark }
    }

    /// Les tiroirs, Main d'abord.
    var potDrawers: [SendDrawer] {
        GrowPots.drawers(vault: context, lending: lending?.context, savings: savings, sentora: sentora?.context, solv: solv?.context)
    }

    func pot(_ mark: ChimpPotProtocol, drawerAddress: String) -> GrowPot? {
        pots.first { $0.mark == mark && $0.drawerAddress == drawerAddress }
    }

    func readings(of pot: GrowPot) -> [PotReading] {
        // Le magasin n'est pas observé : ce compteur redessine la courbe après le relevé du jour.
        _ = historyVersion
        return history?.readings(pot.historyKey) ?? []
    }

    private var historyVersion = 0

    /// Les protocoles qu'on peut planter : ceux dont le service a répondu.
    var plantable: [ChimpPotProtocol] {
        var marks: [ChimpPotProtocol] = []
        if context != nil { marks.append(.defindex) }
        if lending?.context != nil, lending?.vault?.depositsBlocked != true { marks.append(.xoxno) }
        if sentora?.context != nil, sentora?.vault?.depositsBlocked != true { marks.append(.sentora) }
        if solv?.context != nil { marks.append(.solv) }
        marks += savings.map(\.mark)
        return marks
    }

    /// Les relevés du jour, après une lecture.
    private func recordHistory(now: Date = .now) {
        guard let history else { return }
        for pot in pots {
            if let reading = PotHistory.reading(of: pot, day: now) { history.record(reading, potID: pot.historyKey) }
        }
        historyVersion += 1
    }

    private func loadPrice() async {
        guard let priceOracle else { return }
        if let price = await priceOracle.usdPrices(for: ["XLM"])["XLM"] { xlmUSD = price }
        if let solvPricing, let price = await solvPricing.price(of: SendAsset.solvbtc.code).price { btcUSD = price.usd }
    }

    /// Les jetons d'un actif d'émetteur (code) d'un tiroir (adresse), s'il en détient (ou s'ils sont gelés).
    func savingsHolding(drawerAddress: String, code: String) -> SavingsHolding? {
        savings.first { $0.asset.code == code }?.holding(drawerAddress: drawerAddress)
    }

    /// Le prix indicatif du moment de cet actif, s'il est disponible.
    func savingsPrice(_ code: String) -> StablebondPrice? {
        savings.first { $0.asset.code == code }?.price.price
    }

    var vault: VaultInfo? { context?.vault }
    var holdings: [VaultHolding] { context?.holdings ?? [] }

    func holding(drawerAddress: String) -> VaultHolding? {
        holdings.first { $0.drawerAddress == drawerAddress }
    }

    func holding(drawerID: String) -> VaultHolding? {
        context?.holding(drawerID: drawerID)
    }

    func drawer(id: String) -> SendDrawer? {
        context?.drawers.first { $0.id == id }
    }

    func drawer(address: String) -> SendDrawer? {
        context?.drawers.first { $0.address == address }
    }

    /// Valeur de toutes les positions (F1 « GROWING NOW »).
    var totalValue: Decimal { holdings.map(\.value).reduce(0, +) }

    /// Évolution de toutes les positions, seulement si chacune a sa base (sinon la valeur seule, décision 2).
    var totalChange: Decimal? {
        guard !holdings.isEmpty else { return nil }
        let changes = holdings.map(\.change)
        guard changes.allSatisfy({ $0 != nil }) else { return nil }
        return changes.compactMap { $0 }.reduce(0, +)
    }

    /// Lit (ou relit) les positions. Une lecture à la fois ; la précédente reste affichée pendant la suivante.
    func refresh() async {
        if let loadTask { return await loadTask.value }
        let task = Task { [weak self] in
            guard let self else { return }
            async let vault: Void = loadVault()
            async let bonds: Void = loadSavings()
            async let lent: Void = lending?.refresh() ?? ()
            async let escrowed: Void = sentora?.refresh() ?? ()
            async let bitcoin: Void = solv?.refresh() ?? ()
            async let price: Void = loadPrice()
            _ = await (vault, bonds, lent, escrowed, bitcoin, price)
            recordHistory()
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func loadVault() async {
        if context == nil { phase = .loading }
        do {
            context = try await service.fetchContext()
            technicalDetails = nil
            phase = .loaded
        } catch is CancellationError {
        } catch {
            technicalDetails = SendFlowModel.details(error)
            phase = .unavailable
        }
    }

    private func loadSavings() async {
        guard let savingsService else { return }
        if savings.isEmpty { savingsPhase = .loading }
        do {
            savings = try await savingsService.fetchSavings()
            savingsDetails = nil
            savingsPhase = .loaded
        } catch is CancellationError {
        } catch {
            savingsDetails = SendFlowModel.details(error)
            savingsPhase = .unavailable
        }
    }
}
