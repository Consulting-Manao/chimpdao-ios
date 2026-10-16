import Foundation
import Observation

/// N2 · « From Base · via ROZO » (tranche 2, D4 ; construit sans maquette avec le design system, décision de Barth du
/// 2026-10-16) : montant, devis à blanc, puis une commande ROZO vérifiée champ par champ, son adresse de dépôt, sa durée de
/// validité, et le suivi de **cette** commande seulement. L'app n'envoie rien sur Base : l'utilisateur paie depuis son
/// propre wallet. Ne connaît que `RozoPaying`.
@Observable
final class RozoTransferModel {
    enum QuoteState: Equatable {
        case idle
        case loading
        case quoted(RozoQuote)
        case failed(Issue)
    }

    enum Issue: Equatable {
        case tooLow
        case tooHigh
        /// ROZO refuse l'adresse du tiroir.
        case addressRefused
        /// La commande rendue ne correspond pas à la demande : rien n'est montré.
        case mismatch
        /// Réseau, API.
        case unavailable
    }

    enum Phase: Equatable {
        case entry
        case creating
        case order(RozoOrder)
        case failed(Issue)
    }

    private(set) var amount = AmountEntry()
    private(set) var quoteState: QuoteState = .idle
    private(set) var phase: Phase = .entry
    private(set) var rejectedKeyCount = 0
    private(set) var technicalDetails: String?
    /// La dernière lecture de la commande a échoué (réseau) : on réessaie, l'état affiché reste le dernier connu.
    private(set) var isTrackingStale = false

    let config: IntegrationConfig.Rozo
    /// L'adresse du tiroir qui reçoit (le Main).
    let recipient: String
    private let client: RozoPaying
    private let debounce: Duration
    private let pollInterval: Duration
    private var quoteTask: Task<Void, Never>?

    static let fractionDigits = 2

    init(client: RozoPaying, config: IntegrationConfig.Rozo, recipient: String, debounce: Duration = .milliseconds(500), pollInterval: Duration = .seconds(5)) {
        self.client = client
        self.config = config
        self.recipient = recipient
        self.debounce = debounce
        self.pollInterval = pollInterval
    }

    var order: RozoOrder? {
        if case .order(let order) = phase { order } else { nil }
    }

    /// « Get a deposit address » : seulement avec un devis valable, et dans les bornes.
    var canCreateOrder: Bool {
        if case .quoted = quoteState { return isWithinBounds } else { return false }
    }

    var isWithinBounds: Bool { amount.value >= config.minimumAmount && amount.value <= config.maximumAmount }

    // MARK: Montant et devis

    func press(_ key: ChimpKeypadKey) {
        guard phase == .entry else { return }
        if amount.apply(key, maxFractionDigits: Self.fractionDigits) {
            amountChanged()
        } else {
            rejectedKeyCount += 1
        }
    }

    private func amountChanged() {
        quoteTask?.cancel()
        technicalDetails = nil
        guard amount.value > 0 else {
            quoteState = .idle
            return
        }
        if amount.value < config.minimumAmount {
            quoteState = .failed(.tooLow)
            return
        }
        if amount.value > config.maximumAmount {
            quoteState = .failed(.tooHigh)
            return
        }
        quoteState = .loading
        let debounce = debounce
        quoteTask = Task { [weak self] in
            if debounce > .zero {
                try? await Task.sleep(for: debounce)
                guard !Task.isCancelled else { return }
            }
            await self?.refreshQuote()
        }
    }

    func refreshQuote() async {
        let requested = amount.value
        guard requested > 0, isWithinBounds else { return }
        quoteState = .loading
        do {
            let quote = try await client.quote(amount: requested, recipient: recipient)
            guard amount.value == requested else { return }
            quoteState = .quoted(quote)
        } catch is CancellationError {
        } catch {
            guard amount.value == requested else { return }
            technicalDetails = SendFlowModel.details(error)
            quoteState = .failed(Self.issue(for: error))
        }
    }

    // MARK: Commande

    func createOrder() async {
        guard canCreateOrder, phase == .entry else { return }
        let requested = amount.value
        phase = .creating
        do {
            let order = try await client.createOrder(amount: requested, recipient: recipient)
            // Vérifiée une seconde fois ici : le client et le ViewModel appliquent la même règle.
            let problems = order.problems(recipient: recipient, requested: requested, config: config)
            guard problems.isEmpty else { throw RozoError.orderMismatch(problems) }
            technicalDetails = nil
            phase = .order(order)
        } catch {
            technicalDetails = SendFlowModel.details(error)
            phase = .failed(Self.issue(for: error))
        }
    }

    /// Relit la commande jusqu'à son issue, tant que l'écran est affiché (tâche annulée en quittant). Une commande lue qui
    /// ne correspond plus à la demande n'est pas retenue.
    func track() async {
        while let current = order, !current.status.isFinal, !Task.isCancelled {
            try? await Task.sleep(for: pollInterval)
            guard !Task.isCancelled else { return }
            await readOrder(current)
        }
    }

    func readOrder(_ current: RozoOrder) async {
        do {
            let next = try await client.order(id: current.id)
            guard next.id == current.id, next.problems(recipient: recipient, requested: nil, config: config).isEmpty,
                  next.sourceAmount == current.sourceAmount, next.depositAddress == current.depositAddress else {
                isTrackingStale = true
                return
            }
            isTrackingStale = false
            if order?.id == current.id { phase = .order(next) }
        } catch is CancellationError {
        } catch {
            technicalDetails = SendFlowModel.details(error)
            isTrackingStale = true
        }
    }

    /// Après une commande expirée, renvoyée ou un refus : on recommence avec le même montant.
    func startOver() {
        phase = .entry
        technicalDetails = nil
        isTrackingStale = false
        amountChanged()
    }

    static func issue(for error: Error) -> Issue {
        switch error {
        case RozoError.amountTooLow: .tooLow
        case RozoError.amountTooHigh: .tooHigh
        case RozoError.invalidAddress: .addressRefused
        case RozoError.orderMismatch: .mismatch
        default: .unavailable
        }
    }

    /// Le temps qui reste avant l'expiration (jamais négatif) ; `nil` sans date.
    static func remaining(until date: Date?, now: Date) -> TimeInterval? {
        date.map { max(0, $0.timeIntervalSince(now)) }
    }

    /// « 9:05 ».
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
