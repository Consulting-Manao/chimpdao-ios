import Foundation
import Observation

/// ViewModel du parcours Swap (E3, D2 de la tranche 2) : tiroir, actifs donné et reçu, montant, devis en direct, puis
/// vérification, PIN et tap, et les mêmes états d'envoi qu'Envoyer (série C).
///
/// Mêmes garanties qu'Envoyer (`SendFlowModel`, dont la machine à états est reprise étape par étape) : une seule
/// préparation et une seule signature à la fois, rien n'interrompt la signature ni l'envoi (`isSigningLocked`), une issue
/// incertaine est gardée sur le téléphone et revérifiée (« Check again »), « Nothing was sent » seulement quand c'est
/// certain, autorisation refaite avant le tap si elle arrive à expiration.
///
/// Affichage : des quantités d'actifs seulement, jamais de dollars tirés d'un pool (décision du 2026-10-14).
/// Ne fait aucun calcul crypto et ne connaît que le protocole `SwapService`.
@Observable
final class SwapFlowModel {
    enum LoadPhase: Equatable {
        case loading
        case loaded
        case failed
    }

    /// Le devis en direct de l'écran Swap.
    enum QuoteState: Equatable {
        /// Pas de montant : rien à demander.
        case idle
        case loading
        case quoted(SwapQuoteSummary)
        case failed(QuoteIssue)
    }

    enum QuoteIssue: Equatable {
        /// Aucune route entre ces actifs.
        case noRoute
        /// Aucun protocole n'a répondu (leurs noms).
        case protocolUnavailable([String])
        /// Le devis est invraisemblable (`Slippage.isPlausible`) : rien n'est affiché comme un prix.
        case implausibleQuote
        /// Réseau.
        case network
    }

    /// Problème de montant. Montant nul : pas de message, bouton désactivé.
    enum AmountIssue: Equatable {
        case insufficient(drawer: String, available: Decimal, asset: SendAsset)
    }

    /// E4p · Le prix a bougé : rien n'a été signé. L'ancien minimum, et le nouveau devis dès qu'il est arrivé.
    struct PriceMoved: Equatable {
        let oldMinimum: Decimal
        let received: SendAsset
        /// Le nouveau brouillon (nouveau devis, même tolérance) ; `nil` tant qu'il n'est pas arrivé, ou s'il n'a pas pu l'être.
        var newDraft: SwapDraft?
        /// Le nouveau devis n'a pas pu être lu : « Try again ».
        var failed = false
    }

    /// Préparation ratée (avant la carte) : rien n'a été signé.
    enum PreparationIssue: Equatable {
        /// Le prix a bougé sous le minimum affiché : nouveau devis à revoir.
        case priceMoved
        case insufficientBalance
        case noRoute
        /// Le nouveau devis est invraisemblable : rien n'est signé.
        case implausibleQuote
        case protocolUnavailable
        /// L'émetteur a gelé cet actif dans ce tiroir (relu juste avant de signer).
        case frozen(SendAsset)
        /// Réseau, serveur, refus inattendu.
        case other
    }

    // MARK: État

    private(set) var loadPhase: LoadPhase = .loading
    private(set) var context: SwapContext?
    /// L'actif que son émetteur a gelé entre la signature et l'envoi (relu après l'échec) : « Etherfuse froze your CETES ».
    private(set) var frozenAtSend: SendAsset?
    private(set) var selectedDrawerID = "main"
    private(set) var given: SendAsset = .xlm
    private(set) var received: SendAsset = .usdc
    private(set) var amount = AmountEntry()
    private(set) var rejectedKeyCount = 0
    /// Tolérance de slippage, 0,5 % par défaut, 3 % au plus.
    private(set) var slippageBasisPoints = Slippage.defaultBasisPoints
    private(set) var quoteState: QuoteState = .idle

    var isReviewPresented = false
    var isDrawerSheetPresented = false

    /// Ce qui sera signé, figé au passage à la vérification.
    private(set) var draft: SwapDraft?

    // Signature.
    let signingOrder: SigningOrder
    private(set) var stage: SwapStage = .idle
    /// PIN tapé : gardé en mémoire le temps de la signature seulement, jamais enregistré ni journalisé.
    var pin = ""
    var pinState: ChimpPinState = .entering
    private(set) var cardCheck: CardCheck?
    private var prepared: PreparedSwap?
    /// Préparation lancée par « Looks good », encore en cours (le PIN se tape pendant ce temps).
    private var preparation: Task<PreparedSwap, Error>?
    private(set) var signed: SignedSwap?
    private(set) var preparationIssue: PreparationIssue?
    /// E4p, affiché par-dessus la vérification.
    private(set) var priceMoved: PriceMoved?
    private(set) var tapProblem: TapProblem?
    /// Après le PIN (ou « Scan my card ») : la signature se prépare encore (réseau), la fenêtre NFC d'iOS n'est pas
    /// encore ouverte. La feuille dit « Getting ready… » au lieu de « Hold your card » (demande de Barth du 2026-11-05).
    private(set) var isGettingReady = false
    private(set) var technicalDetails: String?

    /// Opération signée à l'issue incertaine (ce swap, ou un envoi laissé en attente).
    private(set) var pending: PendingSend?
    private(set) var summary: SwapSummary?
    /// Le parcours s'est ouvert sur un swap en attente : l'écran d'état remplace l'écran Swap.
    private(set) var resumedPending = false
    /// Un **envoi** (pas un swap) attend son issue : aucun swap ne peut être signé avant (un seul emplacement).
    private(set) var blockedByPendingPayment = false
    private(set) var pendingSaveFailed = false
    private(set) var failureReason: SendFailureReason?
    private var waitTask: Task<Void, Never>?
    private var quoteTask: Task<Void, Never>?
    let pinLength = 4

    private let service: SwapService
    private var hasLoaded = false
    /// Attente après la dernière touche avant de demander un devis (le RPC public est lent) ; zéro dans les tests.
    let quoteDebounce: Duration

    /// Appelé par « Done » à la fin du parcours.
    var onExit: (() -> Void)?

    init(
        service: SwapService,
        signingOrder: SigningOrder = .pinThenTap,
        initialDrawerID: String? = nil,
        prefill: SwapPrefill? = nil,
        quoteDebounce: Duration = .milliseconds(400)
    ) {
        self.service = service
        self.signingOrder = signingOrder
        self.quoteDebounce = quoteDebounce
        if let initialDrawerID { selectedDrawerID = initialDrawerID }
        if let prefill {
            prefillDrawerAddress = prefill.drawerAddress
            given = prefill.given
            received = prefill.received
            if let value = prefill.amount, value > 0, value == value.truncated(to: prefill.given.maxFractionDigits) {
                amount = AmountEntry(value, maxFractionDigits: prefill.given.maxFractionDigits, minFractionDigits: prefill.given == .usdc ? 2 : 0)
            }
        }
    }

    /// Tiroir du préremplissage, retrouvé par son adresse une fois les tiroirs lus.
    private var prefillDrawerAddress: String?

    /// Préremplissage demandé (« Swap again ») : le devis est demandé dès que les tiroirs sont lus.
    private var needsInitialQuote: Bool { amount.value > 0 && quoteState == .idle }

    // MARK: Chargement

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        if let waiting = service.pendingSend {
            pending = waiting
            guard let swap = SwapSummary(waiting, network: context?.network ?? service.network) else {
                // Un envoi attend son issue : l'écran s'affiche (E3f), mais aucun swap ne se signe avant.
                blockedByPendingPayment = true
                await load()
                return
            }
            summary = swap
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
            if let address = prefillDrawerAddress, let drawer = context.drawers.first(where: { $0.address == address }) {
                selectedDrawerID = drawer.id
                prefillDrawerAddress = nil
            }
            if !context.drawers.contains(where: { $0.id == selectedDrawerID }) {
                selectedDrawerID = context.drawers.first?.id ?? "main"
            }
            loadPhase = context.drawers.isEmpty ? .failed : .loaded
            if loadPhase == .loaded, needsInitialQuote { await refreshQuote() }
        } catch is CancellationError {
        } catch {
            loadPhase = .failed
        }
    }

    // MARK: E3f · Un envoi attend son issue

    /// Vérification en cours de l'envoi en attente (E3f « Check again »).
    private(set) var isCheckingPendingPayment = false

    /// E3f « Check again » : vérifie l'envoi en attente. Issue certaine (parti, ou rien n'est parti) : il est effacé, et le
    /// swap redevient possible. Sinon le bandeau reste (Envoyer montre le détail).
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

    // MARK: E3 · Tiroir, actifs, montant

    var drawers: [SendDrawer] { context?.drawers ?? [] }
    var selectedDrawer: SendDrawer? { drawers.first { $0.id == selectedDrawerID } ?? drawers.first }
    var canChooseDrawer: Bool { drawers.count > 1 }
    var available: Decimal { selectedDrawer?.balance(of: given) ?? 0 }

    var amountIssue: AmountIssue? {
        guard let drawer = selectedDrawer, amount.value > available else { return nil }
        return .insufficient(drawer: drawer.title, available: available, asset: given)
    }

    /// L'actif (donné ou reçu) que son émetteur a gelé dans ce tiroir, lu sur la chaîne : aucun devis, aucun swap.
    var frozenAsset: SendAsset? {
        guard let drawer = selectedDrawer, let frozen = context?.frozen[drawer.id] else { return nil }
        return [given, received].first { frozen.contains($0) }
    }

    /// Le devis affiché, s'il correspond exactement à ce qui est à l'écran (tiroir, actifs, montant).
    var currentQuote: SwapQuoteSummary? {
        guard case .quoted(let quote) = quoteState, quote.given == given, quote.received == received,
              quote.amountIn == amount.value else { return nil }
        return quote
    }

    /// Minimum reçu au slippage choisi, pour le devis affiché.
    var currentMinimum: Decimal? {
        currentQuote.map { SwapUnits.amount(fromUnits: Slippage.minimum(of: $0.expectedOutUnits, basisPoints: slippageBasisPoints), asset: $0.received) }
    }

    var canReview: Bool {
        loadPhase == .loaded && selectedDrawer != nil && amount.value > 0 && amountIssue == nil && currentQuote != nil
            && !blockedByPendingPayment && frozenAsset == nil
    }

    func press(_ key: ChimpKeypadKey) {
        if amount.apply(key, maxFractionDigits: given.maxFractionDigits) {
            amountChanged()
        } else {
            rejectedKeyCount += 1
        }
    }

    func setAmount(_ value: Decimal) {
        amount = AmountEntry(value, maxFractionDigits: given.maxFractionDigits, minFractionDigits: given == .usdc ? 2 : 0)
        amountChanged()
    }

    /// Tout le solde de l'actif donné dans ce tiroir (les frais sont payés par ChimpDAO).
    func setMax() {
        setAmount(available)
    }

    func showDrawerSheet() {
        guard canChooseDrawer else { return }
        isDrawerSheetPresented = true
    }

    func select(drawerID: String) {
        selectedDrawerID = drawerID
        isDrawerSheetPresented = false
        // Un tiroir gelé n'avait pas de devis : en quittant le gel, le devis est demandé.
        if quoteState == .idle, amount.value > 0 { amountChanged() }
    }

    /// ⇅ : l'actif donné et l'actif reçu s'échangent ; le montant garde au plus les décimales du nouvel actif.
    func flipAssets() {
        swap(&given, &received)
        amount = amount.clamped(toFractionDigits: given.maxFractionDigits)
        amountChanged()
    }

    /// Un côté du swap.
    enum Side: Identifiable {
        case given, received
        var id: Self { self }
    }

    /// Choix d'un actif pour un côté (feuille E3p) : l'actif de l'autre côté échange les deux (jamais le même des deux
    /// côtés) ; un troisième actif (CETES) remplace seulement ce côté.
    func choose(_ asset: SendAsset, for side: Side) {
        let (current, other) = side == .given ? (given, received) : (received, given)
        guard asset != current else { return }
        if asset == other { return flipAssets() }
        if side == .given { given = asset } else { received = asset }
        amount = amount.clamped(toFractionDigits: given.maxFractionDigits)
        amountChanged()
    }

    /// E3s : les trois tolérances proposées (maquette), 0,5 % par défaut. Pas de saisie libre.
    static let slippageOptions = [50, 100, 300]
    var isSlippageSheetPresented = false

    /// Minimum reçu pour une tolérance donnée, au devis affiché (E3s : « You get at least 98.68 USDC »).
    func minimum(atSlippage basisPoints: Int) -> Decimal? {
        currentQuote.map { SwapUnits.amount(fromUnits: Slippage.minimum(of: $0.expectedOutUnits, basisPoints: basisPoints), asset: $0.received) }
    }

    /// Taux du devis affiché, en quantités : « 1 XLM ≈ 0.2492 USDC » (4 décimales, tronqué). Jamais de dollars.
    var rate: Decimal? {
        guard let quote = currentQuote, quote.amountIn > 0 else { return nil }
        return (quote.expectedOut / quote.amountIn).truncated(to: 4)
    }

    /// Solde de l'actif reçu, puis après le swap (au devis) : « 620 → 719.68 USDC in Main ».
    var receivedBalanceLine: (before: Decimal, after: Decimal?) {
        let held = selectedDrawer?.balance(of: received) ?? 0
        return (held, currentQuote.map { held + $0.expectedOut })
    }

    /// Solde de l'actif donné, puis après le swap : « 800 → 400 XLM in Main » (`nil` après si le montant dépasse).
    var givenBalanceLine: (before: Decimal, after: Decimal?) {
        let value = amount.value
        guard value > 0, value <= available else { return (available, nil) }
        return (available, available - value)
    }

    /// Choisit la tolérance de slippage (en points de base). Refusée au-delà de 3 % : la valeur précédente reste.
    @discardableResult
    func setSlippage(_ basisPoints: Int) -> Bool {
        guard let checked = try? Slippage.checked(basisPoints) else { return false }
        slippageBasisPoints = checked
        isSlippageSheetPresented = false
        return true
    }

    // MARK: Devis en direct

    /// Après chaque changement : l'ancien devis ne vaut plus, un nouveau est demandé après une courte attente.
    private func amountChanged() {
        quoteTask?.cancel()
        guard amount.value > 0, frozenAsset == nil else {
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

    /// Demande un devis pour ce qui est à l'écran. Un devis arrivé pour un montant déjà changé est ignoré.
    func refreshQuote() async {
        let (given, received, value) = (given, received, amount.value)
        guard value > 0, frozenAsset == nil else {
            quoteState = .idle
            return
        }
        quoteState = .loading
        do {
            let quote = try await service.quote(given: given, received: received, amount: value)
            guard given == self.given, received == self.received, value == amount.value else { return }
            quoteState = .quoted(quote)
        } catch is CancellationError {
        } catch {
            guard given == self.given, received == self.received, value == amount.value else { return }
            technicalDetails = SendFlowModel.details(error)
            quoteState = .failed(Self.quoteIssue(for: error))
        }
    }

    static func quoteIssue(for error: Error) -> QuoteIssue {
        switch error {
        case SwapError.noRoute, SwapError.insufficientLiquidity: .noRoute
        case SwapError.implausibleQuote: .implausibleQuote
        case SwapServiceError.protocolUnavailable(let names): .protocolUnavailable(names)
        default: .network
        }
    }

    /// Fige le brouillon et ouvre la vérification.
    func continueToReview() {
        guard canReview, let drawer = selectedDrawer, let quote = currentQuote, let network = context?.network else { return }
        draft = SwapDraft(drawer: drawer, quote: quote, slippageBasisPoints: slippageBasisPoints, network: network)
        preparationIssue = nil
        isReviewPresented = true
    }

    // MARK: Vérification → PIN / tap

    /// Rien ne doit interrompre ces étapes : retour par glissement, fermeture des feuilles et bouton retour bloqués.
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
    /// Ignoré si une préparation ou une signature est déjà en cours : impossible de signer deux fois.
    func confirmReview() {
        guard stage == .idle, let draft, !blockedByPendingPayment else { return }
        preparationIssue = nil
        technicalDetails = nil
        // Si le PIN vient d'abord, son pavé s'ouvre tout de suite : la préparation se fait pendant la saisie.
        let task = Task { try await service.prepare(draft) }
        preparation = task
        if signingSteps.first == .pin {
            beginSigning()
        } else {
            stage = .preparing
        }
        Task {
            do {
                let ready = try await task.value
                guard preparation == task else { return }
                prepared = ready
                preparation = nil
                if stage == .preparing { beginSigning() }
            } catch {
                // Annulée par « Cancel » : `cancelSigning` a déjà tout remis à zéro.
                guard preparation == task else { return }
                preparation = nil
                resetSigning()
                technicalDetails = SendFlowModel.details(error)
                let issue = Self.preparationIssue(for: error)
                if issue == .priceMoved {
                    await priceDidMove()
                } else {
                    preparationIssue = issue
                }
            }
        }
    }

    static func preparationIssue(for error: Error) -> PreparationIssue {
        switch error {
        case SwapError.slippageExceeded, SwapError.deadlineExpired: .priceMoved
        case SwapError.noRoute, SwapError.insufficientLiquidity: .noRoute
        case SwapError.implausibleQuote: .implausibleQuote
        case PaymentClient.PaymentError.insufficientBalance: .insufficientBalance
        case SwapServiceError.protocolUnavailable: .protocolUnavailable
        case SwapServiceError.frozen(let code): SendAsset(code: code).map(PreparationIssue.frozen) ?? .other
        default: .other
        }
    }

    /// E4p : le prix a bougé sous le minimum signé. Rien n'a été signé ; un nouveau devis est demandé tout de suite pour
    /// montrer le nouveau minimum (décision de Barth du 2026-10-14).
    private func priceDidMove() async {
        guard let draft else { return }
        priceMoved = PriceMoved(oldMinimum: draft.minimumOut, received: draft.received)
        await fetchNewPrice()
    }

    /// Nouveau devis pour le même swap (même tiroir, mêmes actifs, même montant, même tolérance).
    func fetchNewPrice() async {
        guard let draft, var moved = priceMoved else { return }
        moved.failed = false
        moved.newDraft = nil
        priceMoved = moved
        do {
            let quote = try await service.quote(given: draft.given, received: draft.received, amount: draft.amount)
            moved.newDraft = SwapDraft(drawer: draft.drawer, quote: quote, slippageBasisPoints: draft.slippageBasisPoints, network: draft.network)
        } catch {
            technicalDetails = SendFlowModel.details(error)
            moved.failed = true
        }
        if priceMoved != nil { priceMoved = moved }
    }

    /// « See new price » : retour à une vérification **complète** (E4) avec les nouvelles bornes ; jamais une signature
    /// directe (décision de Barth du 2026-10-14). Il faudra appuyer de nouveau sur « Looks good ».
    func acceptNewPrice() {
        guard stage == .idle, let newDraft = priceMoved?.newDraft else { return }
        draft = newDraft
        quoteState = .quoted(newDraft.quote)
        priceMoved = nil
        preparationIssue = nil
    }

    /// E4i « Change the amount » : retour à la saisie (E3).
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
        case .tapToRead: autoScan(.tapToRead)
        case .tapToSign, nil: autoScan(.tapToSign)
        }
    }

    func pinEntered(_ value: String) {
        guard stage == .enteringPin, value.count == pinLength else { return }
        pin = value
        tapProblem = nil
        autoScan(.tapToSign)
    }

    /// La fenêtre NFC d'iOS s'ouvre sans « Scan my card » (après le PIN, « Looks good » ou « Try again »). La feuille du
    /// tap reste derrière : elle sert à retaper après une annulation ou un échec.
    private func autoScan(_ step: SigningStep) {
        stage = .waitingForTap(step)
        startScan(after: AutoScan.pause)
    }

    /// « Scan my card » : ouvre la session NFC. L'autorisation est refaite avant si elle arrive à expiration.
    func scanCard() {
        startScan(after: .zero)
    }

    private func startScan(after pause: Duration) {
        guard case .waitingForTap(let step) = stage, prepared != nil || preparation != nil else { return }
        stage = .scanning(step)
        isGettingReady = true
        tapProblem = nil
        Task {
            if pause > .zero { try? await Task.sleep(for: pause) }
            // PIN tapé plus vite que le réseau : on attend la préparation. Ratée, `confirmReview` revient à la vérification.
            guard let current = await readyPrepared() else {
                isGettingReady = false
                return
            }
            do {
                let fresh = try await service.refreshedIfNeeded(current)
                prepared = fresh
                // La session NFC s'ouvre maintenant.
                isGettingReady = false
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
                isGettingReady = false
                handleTapError(error, step: step)
            }
        }
    }

    /// Échec **avant** toute signature : rien n'est parti. Mêmes cas qu'Envoyer, plus le prix qui a bougé pendant la
    /// préparation refaite juste avant le tap : retour à la vérification, avec un nouveau devis à revoir.
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
        case SwapError.slippageExceeded, SwapError.deadlineExpired:
            // La préparation refaite juste avant le tap a trouvé un prix plus bas : E4p, rien n'a été signé.
            resetSigning()
            technicalDetails = SendFlowModel.details(error)
            Task { await priceDidMove() }
        case SwapError.noRoute, SwapError.insufficientLiquidity, PaymentClient.PaymentError.insufficientBalance:
            resetSigning()
            preparationIssue = Self.preparationIssue(for: error)
            technicalDetails = SendFlowModel.details(error)
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
        autoScan(retry)
    }

    private var pinForSigning: String? {
        let cardUsesPin = cardCheck?.usesPin ?? draft?.drawer.usesPin ?? false
        return cardUsesPin && !pin.isEmpty ? pin : nil
    }

    /// « Cancel » ou feuille fermée : retour à la vérification, rien n'a été signé. Impossible pendant un scan.
    func cancelSigning() {
        switch stage {
        case .enteringPin, .waitingForTap, .wrongCard:
            resetSigning()
        default:
            break
        }
    }

    /// La signature préparée, ou la préparation encore en cours ; `nil` si elle a échoué ou a été annulée.
    private func readyPrepared() async -> PreparedSwap? {
        if let prepared { return prepared }
        return try? await preparation?.value
    }

    private func resetSigning() {
        preparation?.cancel()
        preparation = nil
        pin = ""
        pinState = .entering
        cardCheck = nil
        prepared = nil
        tapProblem = nil
        stage = .idle
    }

    // MARK: Envoi et issue

    private func send(_ signed: SignedSwap) async {
        let draft = signed.prepared.draft
        summary = SwapSummary(draft)
        stage = .sending(.checking)
        func waiting(_ trace: PaymentTrace) -> PendingSend {
            PendingSend(
                trace: trace, recipient: signed.prepared.contract, recipientName: draft.quote.protocolName,
                drawerTitle: draft.drawer.title, asset: draft.given.rawValue, amount: draft.amount, signedAt: .now,
                swap: PendingSwap(
                    receivedAsset: draft.received.rawValue, expectedReceived: draft.quote.expectedOut,
                    minimumReceived: draft.minimumOut, protocolName: draft.quote.protocolName
                )
            )
        }
        // Revue de sécurité F7 : gardée dès le retour de la carte, avant l'envoi (effacée par `finish`).
        if let trace = try? service.trace(for: signed) { keepPending(waiting(trace)) }
        do {
            let receipt = try await service.submit(signed) { [weak self] progress in
                self?.stage = .sending(progress)
            }
            finish(with: .sent(receipt))
        } catch {
            technicalDetails = SendFlowModel.details(error)
            failureReason = SendFailureReason(error)
            // Gel entre la signature et l'envoi (décision de Barth du 2026-10-15) : on ne bloque pas l'envoi, mais l'échec
            // est traduit, relu sur la chaîne.
            let bonds = [draft.given, draft.received].filter { !$0.isSendable }
            if !bonds.isEmpty { frozenAtSend = await service.frozenAsset(in: draft.drawer, among: bonds) }
            guard let failure = error as? PaymentFailure else {
                stage = .finished(.undetermined)
                return
            }
            keepPending(waiting(failure.trace))
            await check()
        }
    }

    private func keepPending(_ waiting: PendingSend) {
        pending = waiting
        do {
            try service.setPendingSend(waiting)
        } catch {
            pendingSaveFailed = true
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
        guard let pending, pending.swap != nil else { return }
        waitTask?.cancel()
        stage = .checking
        do {
            switch try await service.check(pending.trace) {
            case .sent(let hash):
                let summary = summary ?? SwapSummary(pending, network: context?.network ?? service.network)
                guard let summary else { return }
                finish(with: .sent(SwapReceipt(
                    summary: summary, transactionHash: hash, sentAt: pending.signedAt,
                    explorerURL: service.explorerURL(transactionHash: hash), receivedAmount: nil
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

    private func finish(with outcome: SwapOutcome) {
        waitTask?.cancel()
        pending = nil
        try? service.setPendingSend(nil)
        stage = .finished(outcome)
    }

    var explorerURL: URL? {
        if case .finished(.sent(let receipt)) = stage { return receipt.explorerURL }
        return pending?.trace.transactionHash.flatMap(service.explorerURL(transactionHash:))
    }

    /// Revue de sécurité F3, partie 2 (décision de Pamphile du 2026-10-19), comme Envoyer : tant que l'autorisation
    /// signée n'a pas expiré, « Try again » la renvoie telle quelle dans une nouvelle transaction, sans nouvelle signature
    /// (même nonce : une seule exécution possible). Un swap Soroswap dont l'échéance (5 minutes au plus) est passée
    /// échouera de nouveau : on attend alors l'expiration, puis « Nothing was sent » et une nouvelle signature.
    var canResend: Bool {
        guard case .finished(.waiting) = stage else { return false }
        return signed != nil
    }

    func resend() {
        guard canResend, let signed else { return }
        waitTask?.cancel()
        technicalDetails = nil
        failureReason = nil
        frozenAtSend = nil
        Task { await send(signed) }
    }

    /// « Try again » après « Nothing was sent » (certain) : retour à la vérification, avec le même brouillon.
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

    /// « Swap again » (reçu) : un parcours neuf, prérempli (même tiroir, mêmes actifs, même montant), devis neuf.
    var onSwapAgain: ((SwapPrefill) -> Void)?

    /// Le bouton du reçu de E5 : seul « Swap again » relance le swap ; toute autre action est ignorée ici.
    func receiptAgain(_ again: ReceiptAgain) {
        guard case .swapAgain(let prefill) = again else { return }
        onSwapAgain?(prefill)
    }
}

/// Ce que « Swap again » préremplit : un swap déjà fait, à refaire au prix du moment (tout est revérifié).
struct SwapPrefill: Equatable, Hashable {
    /// Adresse du tiroir (Main account ou Pocket).
    let drawerAddress: String
    let given: SendAsset
    let received: SendAsset
    let amount: Decimal?
}

/// Issue d'un swap, une fois la carte passée (mêmes cas qu'Envoyer).
enum SwapOutcome: Equatable {
    case sent(SwapReceipt)
    case notConfirmed
    case waiting(until: Date)
    case nothingSent
    case undetermined
}

/// Où en est la signature d'un swap (mêmes étapes que `SigningStage` d'Envoyer).
enum SwapStage: Equatable {
    case idle
    case preparing
    case enteringPin
    case waitingForTap(SigningStep)
    case scanning(SigningStep)
    case sending(PaymentProgress)
    case wrongCard(WrongCard, retry: SigningStep)
    case checking
    case finished(SwapOutcome)

    /// Mêmes sons qu'Envoyer.
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
