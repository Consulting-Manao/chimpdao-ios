import Foundation
import Observation

/// ViewModel du parcours du vault (F3 à F5 pour mettre, F7 pour retirer, F8 pour les issues incertaines ; D1) : tiroir,
/// montant, devis, vérification, PIN et tap, et les mêmes états d'envoi qu'Envoyer et Swap.
///
/// Mêmes garanties que Swap (`SwapFlowModel`, dont la machine à états est reprise) : une seule préparation et une seule
/// signature à la fois, rien n'interrompt la signature ni l'envoi (`isSigningLocked`), une issue incertaine est gardée sur
/// le téléphone et revérifiée (« Check again »), « Nothing was moved » seulement quand c'est certain.
///
/// Affichage : des quantités d'actif seulement, aucun taux promis (décision de Barth du 2026-10-15). Ne fait aucun calcul
/// crypto et ne connaît que le protocole `VaultService`.
@Observable
final class VaultFlowModel {
    enum LoadPhase: Equatable {
        case loading
        case loaded
        /// F3b : le vault ne répond pas.
        case unavailable
        case failed
    }

    enum QuoteState: Equatable {
        case idle
        case loading
        case quoted(VaultQuote)
        case failed(QuoteIssue)
    }

    enum QuoteIssue: Equatable {
        case vaultUnavailable
        /// Une valeur lue n'est pas vraisemblable : rien n'est affiché comme un montant.
        case implausible
        case amountTooSmall
        case network
    }

    enum AmountIssue: Equatable {
        /// Mettre : pas assez de l'actif dans le tiroir (F3a).
        case insufficient(drawer: String, available: Decimal, asset: SendAsset)
        /// Retirer : plus que la position.
        case moreThanPosition(available: Decimal, asset: SendAsset)
    }

    /// Préparation ratée (avant la carte) : rien n'a été signé.
    enum PreparationIssue: Equatable {
        /// Le vault rendrait moins que le minimum affiché : nouveau devis, vérification à refaire.
        case priceMoved
        case insufficientBalance
        case notEnoughShares
        case notEnoughLiquidity
        case vaultUnavailable
        case implausible
        case other
    }

    // MARK: État

    let action: VaultAction
    private(set) var loadPhase: LoadPhase = .loading
    private(set) var context: VaultContext?
    private(set) var selectedDrawerID = "main"
    private(set) var amount = AmountEntry()
    /// Retirer : « All » (toutes les parts).
    private(set) var withdrawAll = false
    private(set) var rejectedKeyCount = 0
    private(set) var quoteState: QuoteState = .idle

    var isReviewPresented = false
    var isDrawerSheetPresented = false
    private(set) var draft: VaultDraft?

    let signingOrder: SigningOrder
    private(set) var stage: VaultStage = .idle
    /// PIN tapé : gardé en mémoire le temps de la signature seulement, jamais enregistré ni journalisé.
    var pin = ""
    var pinState: ChimpPinState = .entering
    private(set) var cardCheck: CardCheck?
    private var prepared: PreparedVault?
    private(set) var signed: SignedVault?
    private(set) var preparationIssue: PreparationIssue?
    /// Le vault a bougé : un nouveau devis remplace le brouillon dès qu'il arrive (vérification complète à refaire).
    private(set) var isRefreshingQuote = false
    private(set) var tapProblem: TapProblem?
    private(set) var technicalDetails: String?

    private(set) var pending: PendingSend?
    private(set) var summary: VaultSummary?
    private(set) var resumedPending = false
    /// F3c : une autre opération attend son issue (un envoi, un swap) : rien ne se signe avant.
    private(set) var blockedByPendingPayment = false
    private(set) var pendingSaveFailed = false
    private(set) var failureReason: SendFailureReason?
    private var waitTask: Task<Void, Never>?
    private var quoteTask: Task<Void, Never>?
    let pinLength = 4

    private let service: VaultService
    private var hasLoaded = false
    let quoteDebounce: Duration

    var onExit: (() -> Void)?

    init(
        service: VaultService,
        action: VaultAction,
        signingOrder: SigningOrder = .pinThenTap,
        initialDrawerID: String? = nil,
        quoteDebounce: Duration = .milliseconds(400)
    ) {
        self.service = service
        self.action = action
        self.signingOrder = signingOrder
        self.quoteDebounce = quoteDebounce
        if let initialDrawerID { selectedDrawerID = initialDrawerID }
        hasChosenDrawer = initialDrawerID != nil
    }

    private var hasChosenDrawer: Bool

    // MARK: Chargement

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        if let waiting = service.pendingSend {
            pending = waiting
            guard let vault = VaultSummary(waiting, network: context?.network ?? .testnet) else {
                blockedByPendingPayment = true
                await load()
                return
            }
            summary = vault
            resumedPending = true
            await check()
            return
        }
        await load()
    }

    func load() async {
        loadPhase = .loading
        do {
            let context = try await service.fetchContext()
            self.context = context
            if action == .withdraw, !hasChosenDrawer || context.holding(drawerID: selectedDrawerID) == nil {
                // Retirer : depuis le tiroir qui détient la position.
                selectedDrawerID = context.holdings.first?.drawerID ?? selectedDrawerID
            }
            if !context.drawers.contains(where: { $0.id == selectedDrawerID }) {
                selectedDrawerID = context.drawers.first?.id ?? "main"
            }
            loadPhase = context.drawers.isEmpty ? .failed : .loaded
        } catch is CancellationError {
        } catch VaultServiceError.vaultUnavailable {
            loadPhase = .unavailable
        } catch {
            technicalDetails = SendFlowModel.details(error)
            loadPhase = .failed
        }
    }

    // MARK: F3c · Une autre opération attend son issue

    private(set) var isCheckingPendingPayment = false

    func checkPendingPayment() async {
        guard blockedByPendingPayment, let waiting = pending, !isCheckingPendingPayment else { return }
        isCheckingPendingPayment = true
        defer { isCheckingPendingPayment = false }
        do {
            switch try await service.check(waiting.trace) {
            case .sent, .nothingSent:
                try? service.setPendingSend(nil)
                pending = nil
                blockedByPendingPayment = false
                if context == nil { await load() }
            case .pending, .waiting, .undetermined:
                break
            }
        } catch {
            technicalDetails = SendFlowModel.details(error)
        }
    }

    // MARK: F3 / F7 · Tiroir et montant

    var drawers: [SendDrawer] {
        guard let context else { return [] }
        // Retirer : seulement les tiroirs qui détiennent une position.
        return action == .deposit ? context.drawers : context.drawers.filter { context.holding(drawerID: $0.id) != nil }
    }

    var selectedDrawer: SendDrawer? { drawers.first { $0.id == selectedDrawerID } ?? drawers.first }
    var holding: VaultHolding? { selectedDrawer.flatMap { context?.holding(drawerID: $0.id) } }
    var asset: SendAsset { context?.vault.asset ?? .xlm }
    var canChooseDrawer: Bool { drawers.count > 1 }

    /// Mettre : le solde de l'actif dans le tiroir. Retirer : la valeur de la position.
    var available: Decimal {
        switch action {
        case .deposit: selectedDrawer?.balance(of: asset) ?? 0
        case .withdraw: holding?.value ?? 0
        }
    }

    var amountIssue: AmountIssue? {
        guard !withdrawAll, amount.value > available else { return nil }
        switch action {
        case .deposit:
            guard let drawer = selectedDrawer else { return nil }
            return .insufficient(drawer: drawer.title, available: available, asset: asset)
        case .withdraw:
            return .moreThanPosition(available: available, asset: asset)
        }
    }

    var currentQuote: VaultQuote? {
        guard case .quoted(let quote) = quoteState, quote.all == withdrawAll, withdrawAll || quote.amount == amount.value else { return nil }
        return quote
    }

    var canReview: Bool {
        loadPhase == .loaded && selectedDrawer != nil && (amount.value > 0 || withdrawAll) && amountIssue == nil
            && currentQuote != nil && !blockedByPendingPayment
    }

    func press(_ key: ChimpKeypadKey) {
        if amount.apply(key, maxFractionDigits: asset.maxFractionDigits) {
            withdrawAll = false
            amountChanged()
        } else {
            rejectedKeyCount += 1
        }
    }

    func setAmount(_ value: Decimal) {
        amount = AmountEntry(value, maxFractionDigits: asset.maxFractionDigits, minFractionDigits: 0)
        withdrawAll = false
        amountChanged()
    }

    /// Mettre : tout le solde (les frais sont payés par ChimpDAO). Retirer : « All », toutes les parts.
    func setMax() {
        switch action {
        case .deposit:
            setAmount(available)
        case .withdraw:
            amount = AmountEntry(available.truncated(to: 2), maxFractionDigits: asset.maxFractionDigits, minFractionDigits: 0)
            withdrawAll = true
            amountChanged()
        }
    }

    func showDrawerSheet() {
        guard canChooseDrawer else { return }
        isDrawerSheetPresented = true
    }

    func select(drawerID: String) {
        selectedDrawerID = drawerID
        isDrawerSheetPresented = false
        amountChanged()
    }

    // MARK: Devis

    private func amountChanged() {
        quoteTask?.cancel()
        guard amount.value > 0 || withdrawAll else {
            quoteState = .idle
            return
        }
        quoteState = .loading
        let debounce = quoteDebounce
        quoteTask = Task { [weak self] in
            if debounce > .zero {
                try? await Task.sleep(for: debounce)
                guard !Task.isCancelled else { return }
            }
            await self?.refreshQuote()
        }
    }

    func refreshQuote() async {
        let (value, all, drawerID) = (amount.value, withdrawAll, selectedDrawerID)
        guard let drawer = selectedDrawer, value > 0 || all else {
            quoteState = .idle
            return
        }
        quoteState = .loading
        do {
            let quote = action == .deposit
                ? try await service.depositQuote(drawer: drawer, amount: value)
                : try await service.withdrawQuote(drawer: drawer, amount: value, all: all)
            guard value == amount.value, all == withdrawAll, drawerID == selectedDrawerID else { return }
            quoteState = .quoted(quote)
        } catch is CancellationError {
        } catch {
            guard value == amount.value, all == withdrawAll, drawerID == selectedDrawerID else { return }
            technicalDetails = SendFlowModel.details(error)
            quoteState = .failed(Self.quoteIssue(for: error))
        }
    }

    static func quoteIssue(for error: Error) -> QuoteIssue {
        switch error {
        case VaultServiceError.vaultUnavailable, YieldError.vaultUnavailable: .vaultUnavailable
        case YieldError.implausibleValue: .implausible
        case YieldError.amountTooSmall: .amountTooSmall
        default: .network
        }
    }

    func continueToReview() {
        guard canReview, let drawer = selectedDrawer, let quote = currentQuote, let context else { return }
        draft = VaultDraft(drawer: drawer, vault: context.vault, quote: quote, network: context.network)
        preparationIssue = nil
        isReviewPresented = true
    }

    // MARK: Vérification → PIN / tap

    var isSigningLocked: Bool {
        switch stage {
        case .preparing, .scanning, .sending, .checking, .finished: true
        case .idle, .enteringPin, .waitingForTap, .wrongCard: false
        }
    }

    var isSigningSheetPresented: Bool {
        switch stage {
        case .enteringPin, .waitingForTap, .scanning: true
        default: false
        }
    }

    var showsStatus: Bool {
        switch stage {
        case .sending, .checking, .finished: true
        default: false
        }
    }

    var signingSteps: [SigningStep] {
        guard let drawer = draft?.drawer else { return [] }
        if let cardCheck, !cardCheck.usesPin { return [.tapToSign] }
        switch (signingOrder, drawer.usesPin) {
        case (_, false): return [.tapToSign]
        case (.pinThenTap, true): return [.pin, .tapToSign]
        case (.tapThenPin, true): return [.tapToRead, .pin, .tapToSign]
        }
    }

    var currentSigningStep: SigningStep? {
        switch stage {
        case .enteringPin: .pin
        case .waitingForTap(let step), .scanning(let step): step
        default: nil
        }
    }

    /// « Looks good » : prépare la signature (réseau, avant toute session NFC), puis ouvre la première feuille.
    func confirmReview() {
        guard stage == .idle, let draft, !blockedByPendingPayment, !isRefreshingQuote else { return }
        preparationIssue = nil
        technicalDetails = nil
        stage = .preparing
        Task {
            do {
                prepared = try await service.prepare(draft)
                beginSigning()
            } catch {
                stage = .idle
                technicalDetails = SendFlowModel.details(error)
                let issue = Self.preparationIssue(for: error)
                preparationIssue = issue
                if issue == .priceMoved { await refreshDraft() }
            }
        }
    }

    static func preparationIssue(for error: Error) -> PreparationIssue {
        switch error {
        case VaultServiceError.priceMoved, YieldError.belowMinimum: .priceMoved
        case PaymentClient.PaymentError.insufficientBalance, YieldError.insufficientBalance: .insufficientBalance
        case YieldError.notEnoughShares: .notEnoughShares
        case YieldError.notEnoughLiquidity: .notEnoughLiquidity
        case VaultServiceError.vaultUnavailable, YieldError.vaultUnavailable: .vaultUnavailable
        case YieldError.implausibleValue: .implausible
        default: .other
        }
    }

    /// Le vault a bougé : nouveau devis pour le même tiroir et le même montant ; il remplace le brouillon et la
    /// vérification se refait **en entier** (« Looks good » à nouveau), jamais une signature directe (comme E4p).
    func refreshDraft() async {
        guard let draft else { return }
        isRefreshingQuote = true
        defer { isRefreshingQuote = false }
        do {
            let quote = draft.action == .deposit
                ? try await service.depositQuote(drawer: draft.drawer, amount: draft.amount)
                : try await service.withdrawQuote(drawer: draft.drawer, amount: draft.quote.all ? 0 : draft.amount, all: draft.quote.all)
            self.draft = VaultDraft(drawer: draft.drawer, vault: draft.vault, quote: quote, network: draft.network)
            quoteState = .quoted(quote)
        } catch {
            technicalDetails = SendFlowModel.details(error)
        }
    }

    /// « Change the amount » : retour à la saisie.
    func changeAmount() {
        guard stage == .idle else { return }
        isReviewPresented = false
    }

    private func beginSigning() {
        pin = ""
        pinState = .entering
        cardCheck = nil
        tapProblem = nil
        switch signingSteps.first {
        case .pin: stage = .enteringPin
        case .tapToRead: stage = .waitingForTap(.tapToRead)
        case .tapToSign, nil: stage = .waitingForTap(.tapToSign)
        }
    }

    func pinEntered(_ value: String) {
        guard stage == .enteringPin, value.count == pinLength else { return }
        pin = value
        tapProblem = nil
        stage = .waitingForTap(.tapToSign)
    }

    func scanCard() {
        guard case .waitingForTap(let step) = stage, let current = prepared else { return }
        stage = .scanning(step)
        tapProblem = nil
        Task {
            do {
                let fresh = try await service.refreshedIfNeeded(current)
                prepared = fresh
                switch step {
                case .tapToRead:
                    let read = try await service.readCard(for: fresh)
                    cardCheck = read.check
                    if let signed = read.signed {
                        pin = ""
                        self.signed = signed
                        await send(signed)
                    } else {
                        stage = .enteringPin
                    }
                case .tapToSign, .pin:
                    let signed = try await service.sign(fresh, pin: pinForSigning, onlyCard: cardCheck?.publicKey)
                    pin = ""
                    self.signed = signed
                    await send(signed)
                }
            } catch {
                handleTapError(error, step: step)
            }
        }
    }

    /// Échec **avant** toute signature : rien n'est parti. Mêmes cas qu'Envoyer, plus le vault qui a bougé pendant la
    /// préparation refaite juste avant le tap : retour à la vérification, avec un nouveau devis.
    private func handleTapError(_ error: Error, step: SigningStep) {
        switch error {
        case ChipError.cancelled:
            stage = .waitingForTap(step)
        case ChipError.wrongPIN(let retriesLeft):
            pin = ""
            pinState = .wrong(triesLeft: retriesLeft)
            stage = .enteringPin
        case ChipError.pinLocked:
            pin = ""
            pinState = .blocked
            stage = .enteringPin
        case ChipError.pinRequired:
            pin = ""
            pinState = .entering
            stage = .enteringPin
        case ChipError.cardNotAccepted(let tapped):
            technicalDetails = SendFlowModel.details(error)
            stage = .wrongCard(wrongCard(tapped: tapped), retry: step == .tapToRead ? .tapToRead : .tapToSign)
        case VaultServiceError.priceMoved, YieldError.belowMinimum, YieldError.notEnoughShares, YieldError.notEnoughLiquidity,
             YieldError.insufficientBalance, PaymentClient.PaymentError.insufficientBalance, YieldError.implausibleValue:
            resetSigning()
            technicalDetails = SendFlowModel.details(error)
            let issue = Self.preparationIssue(for: error)
            preparationIssue = issue
            if issue == .priceMoved { Task { await refreshDraft() } }
        default:
            tapProblem = SendFlowModel.tapProblem(for: error)
            technicalDetails = SendFlowModel.details(error)
            stage = .waitingForTap(step == .tapToRead ? .tapToRead : .tapToSign)
        }
    }

    private func wrongCard(tapped: ChipPublicKey) -> WrongCard {
        let known = service.knownCard(tapped)
        if let first = cardCheck, first.publicKey != nil, first.publicKey != tapped {
            return WrongCard(reason: .notTheSameCard, tapped: known, needed: KnownCard(name: first.cardName, color: first.cardColor))
        }
        switch draft?.drawer.kind {
        case let .card(name, color):
            return WrongCard(reason: known == nil ? .notYours : .otherWallet, tapped: known, needed: KnownCard(name: name, color: color))
        case .main, nil:
            return WrongCard(reason: .notYours, tapped: known, needed: nil)
        }
    }

    func retryAfterWrongCard() {
        guard case .wrongCard(_, let retry) = stage else { return }
        stage = .waitingForTap(retry)
    }

    private var pinForSigning: String? {
        let cardUsesPin = cardCheck?.usesPin ?? draft?.drawer.usesPin ?? false
        return cardUsesPin && !pin.isEmpty ? pin : nil
    }

    func cancelSigning() {
        switch stage {
        case .enteringPin, .waitingForTap, .wrongCard:
            resetSigning()
        default:
            break
        }
    }

    private func resetSigning() {
        pin = ""
        pinState = .entering
        cardCheck = nil
        prepared = nil
        tapProblem = nil
        stage = .idle
    }

    // MARK: Envoi et issue

    private func send(_ signed: SignedVault) async {
        let draft = signed.prepared.draft
        summary = VaultSummary(draft)
        stage = .sending(.checking)
        do {
            let receipt = try await service.submit(signed) { [weak self] progress in
                self?.stage = .sending(progress)
            }
            finish(with: .sent(receipt))
        } catch {
            technicalDetails = SendFlowModel.details(error)
            failureReason = SendFailureReason(error)
            guard let failure = error as? PaymentFailure else {
                stage = .finished(.undetermined)
                return
            }
            let summary = VaultSummary(draft)
            let waiting = PendingSend(
                trace: failure.trace, recipient: draft.vault.id, recipientName: draft.vault.name,
                drawerTitle: draft.drawer.title, asset: draft.vault.asset.rawValue, amount: summary.amount, signedAt: .now,
                vault: PendingVault(action: draft.action.rawValue, vaultName: draft.vault.name, shares: summary.shares, minimumReceived: summary.minimumOut)
            )
            pending = waiting
            do {
                try service.setPendingSend(waiting)
            } catch {
                pendingSaveFailed = true
            }
            await check()
        }
    }

    func checkAgain() {
        switch stage {
        case .finished(.notConfirmed), .finished(.undetermined):
            Task { await check() }
        default:
            break
        }
    }

    private func check() async {
        guard let pending, pending.vault != nil else { return }
        waitTask?.cancel()
        stage = .checking
        do {
            switch try await service.check(pending.trace) {
            case .sent(let hash):
                guard let summary = summary ?? VaultSummary(pending, network: context?.network ?? .testnet) else { return }
                finish(with: .sent(VaultReceipt(
                    summary: summary, transactionHash: hash, sentAt: pending.signedAt,
                    explorerURL: service.explorerURL(transactionHash: hash), shares: summary.shares, received: nil
                )))
            case .pending:
                stage = .finished(.notConfirmed)
            case .waiting(_, let end):
                stage = .finished(.waiting(until: end))
                scheduleCheck(at: end)
            case .nothingSent:
                finish(with: .nothingSent)
            case .undetermined(let reason):
                technicalDetails = [technicalDetails, reason].compactMap { $0 }.joined(separator: "\n")
                stage = .finished(.undetermined)
            }
        } catch {
            technicalDetails = SendFlowModel.details(error)
            stage = .finished(.undetermined)
        }
    }

    private func scheduleCheck(at end: Date) {
        waitTask?.cancel()
        waitTask = Task { [weak self] in
            let delay = max(0, end.timeIntervalSinceNow) + 1
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            waitTask = nil
            await check()
        }
    }

    private func finish(with outcome: VaultOutcome) {
        waitTask?.cancel()
        pending = nil
        try? service.setPendingSend(nil)
        stage = .finished(outcome)
    }

    var explorerURL: URL? {
        if case .finished(.sent(let receipt)) = stage { return receipt.explorerURL }
        return pending?.trace.transactionHash.flatMap(service.explorerURL(transactionHash:))
    }

    var canTryAgain: Bool {
        stage == .finished(.nothingSent) && draft != nil && !resumedPending
    }

    func tryAgain() {
        guard canTryAgain else { return }
        prepared = nil
        signed = nil
        technicalDetails = nil
        failureReason = nil
        summary = nil
        stage = .idle
    }

    func finish() {
        waitTask?.cancel()
        quoteTask?.cancel()
        onExit?()
    }
}

/// Issue d'un dépôt ou d'un retrait, une fois la carte passée (mêmes cas qu'Envoyer).
enum VaultOutcome: Equatable {
    case sent(VaultReceipt)
    case notConfirmed
    case waiting(until: Date)
    case nothingSent
    case undetermined
}

/// Où en est la signature (mêmes étapes que Swap).
enum VaultStage: Equatable {
    case idle
    case preparing
    case enteringPin
    case waitingForTap(SigningStep)
    case scanning(SigningStep)
    case sending(PaymentProgress)
    case wrongCard(WrongCard, retry: SigningStep)
    case checking
    case finished(VaultOutcome)

    var sound: ChimpSound? {
        switch self {
        case .sending: .confirmation
        case .finished(.sent): .money
        case .wrongCard: .hurt
        case .finished(.nothingSent), .finished(.waiting): .error
        default: nil
        }
    }
}
