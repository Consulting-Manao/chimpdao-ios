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

    let service: VaultService
    private var loadTask: Task<Void, Never>?

    init(service: VaultService) {
        self.service = service
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
        loadTask = task
        await task.value
        loadTask = nil
    }
}
