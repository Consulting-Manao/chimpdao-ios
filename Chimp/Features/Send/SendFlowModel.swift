import Foundation
import Observation

/// ViewModel du parcours Envoyer (C1 → C9), partagé par tous ses écrans : destinataire, tiroir source,
/// actif, montant, puis (étapes B et C) vérification, signature et envoi.
///
/// **Move** (E1, E2) : le même parcours, sans C1. Déplacer de l'argent entre ses tiroirs est un `SAC.transfer` comme un
/// envoi, vers l'adresse d'un de ses tiroirs (`moveFunds` du terminal, ARCHITECTURE §3.9) : même préparation, mêmes
/// ordres (Pocket : ordre 1, seulement sa carte ; Main : ordre 2, n'importe quelle carte), mêmes feuilles et issues.
///
/// Ne fait aucun calcul crypto et ne connaît que le protocole `SendService`. La vérification des adresses
/// passe par `StellarAddressParser` (SDK Stellar).
@Observable
final class SendFlowModel {
    /// Envoyer vers une adresse, ou déplacer entre ses propres tiroirs.
    enum FlowKind: Equatable {
        case send
        case move
    }

    enum LoadPhase: Equatable {
        case loading
        case loaded
        case failed
    }

    /// État du champ d'adresse (C1).
    enum RecipientState: Equatable {
        case empty
        case invalid(RecipientIssue)
        case valid(StellarRecipient)
    }

    /// Problème de montant (C2). Montant nul : pas de message, bouton désactivé.
    enum AmountIssue: Equatable {
        /// Plus que le solde du tiroir choisi. `available` = solde déjà formaté avec son code.
        case insufficient(drawer: String, available: String)
    }

    // MARK: État

    private(set) var loadPhase: LoadPhase = .loading
    private(set) var context: SendContext?

    /// Texte du champ d'adresse (C1), tel que tapé ou collé.
    var addressText = "" {
        didSet { if addressText != oldValue { chosenContact = nil } }
    }
    /// Memo ID facultatif, seulement pour une adresse G (C1).
    var memoText = ""
    /// Destinataire choisi dans les récents : donne son nom tant que l'adresse n'a pas été modifiée.
    private(set) var chosenContact: SendContact?

    private(set) var selectedDrawerID = "main"
    /// Move : tiroir d'arrivée (`nil` pour un envoi, ou tant que les tiroirs ne sont pas lus).
    private(set) var destinationDrawerID: String?
    private(set) var asset: SendAsset = .usdc
    private(set) var amount = AmountEntry()
    /// Augmente à chaque touche refusée : déclenche un retour haptique.
    private(set) var rejectedKeyCount = 0

    // Navigation (écrans poussés par `navigationDestination(isPresented:)`).
    var isAmountPresented = false
    var isReviewPresented = false
    var isDrawerSheetPresented = false
    /// Move : feuille « Where should it go? ».
    var isDestinationSheetPresented = false
    var isAssetSheetPresented = false

    /// Montant et destinataire figés pour la vérification (C4).
    private(set) var draft: SendDraft?

    let kind: FlowKind

    // Signature (C4 → C5 / C6).
    let signingOrder: SigningOrder
    private(set) var signingStage: SigningStage = .idle
    /// PIN tapé : gardé en mémoire le temps de la signature seulement, jamais enregistré ni journalisé.
    var pin = ""
    var pinState: ChimpPinState = .entering
    /// Carte lue au premier tap (ordre « tap puis PIN »).
    private(set) var cardCheck: CardCheck?
    private var prepared: PreparedSend?
    private(set) var signed: SignedSend?
    /// Message si la préparation a échoué (rien n'a été envoyé), sous « Looks good ».
    private(set) var signingErrorMessage: String?
    /// Problème dans la feuille du tap après un échec **avant** toute signature (carte refusée, NFC, réseau) :
    /// rien n'a été signé, on peut retaper.
    private(set) var tapProblem: TapProblem?
    /// Texte technique du dernier problème (« Technical details », pour le support).
    private(set) var technicalDetails: String?

    /// Paiement signé dont l'issue n'est pas certaine : gardé sur le téléphone jusqu'à ce qu'elle le soit.
    private(set) var pending: PendingSend?
    /// Ce qui a été signé, pour les écrans d'après (envoi, C9, reçu, issue incertaine).
    private(set) var summary: SendSummary?
    /// Le parcours s'est ouvert sur un paiement en attente (Envoyer rouvert, ou app relancée) : l'écran d'état
    /// remplace C1, et « Try again » n'existe pas (il n'y a plus de brouillon).
    private(set) var resumedPending = false
    /// Le téléphone n'a pas pu enregistrer le paiement en attente (rare) : l'écran le dit.
    private(set) var pendingSaveFailed = false
    var isReceiptPresented = false
    /// Pourquoi l'envoi a échoué après la signature (réseau, serveur de frais, refus de Stellar…), pour l'écran d'attente.
    private(set) var failureReason: SendFailureReason?
    private var waitTask: Task<Void, Never>?
    /// Longueur du PIN des cartes : ⚠️ à confirmer avec Pamphile (le VERIFY PIN Infineon accepte 4 à 62 octets).
    let pinLength = 4

    private let service: SendService
    private var hasLoaded = false

    /// Appelé par « Done » à la fin du parcours (retour au Wallet).
    var onExit: (() -> Void)?

    /// `initialDrawerID` : tiroir « From » choisi d'avance (Send ou Move depuis la page d'un tiroir, B2 et B3) ; Main sinon.
    init(service: SendService, signingOrder: SigningOrder = .pinThenTap, kind: FlowKind = .send, initialDrawerID: String? = nil) {
        self.service = service
        self.signingOrder = signingOrder
        self.kind = kind
        if let initialDrawerID { selectedDrawerID = initialDrawerID }
    }

    var isMove: Bool { kind == .move }

    // MARK: Chargement

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        if let waiting = service.pendingSend {
            // Un paiement signé attend encore son issue : on la vérifie au lieu de proposer un nouvel envoi.
            pending = waiting
            summary = SendSummary(waiting, network: context?.network ?? .testnet)
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
            if !context.drawers.contains(where: { $0.id == selectedDrawerID }) {
                selectedDrawerID = context.drawers.first?.id ?? "main"
            }
            if isMove, destinationDrawer == nil || destinationDrawerID == selectedDrawerID {
                destinationDrawerID = defaultDestination(for: selectedDrawerID)
            }
            loadPhase = context.drawers.isEmpty ? .failed : .loaded
        } catch is CancellationError {
            // Chargement interrompu (écran quitté) : rien à faire.
        } catch {
            loadPhase = .failed
        }
    }

    // MARK: C1 · Destinataire

    var recents: [SendContact] { context?.recents ?? [] }

    /// Adresse vérifiée (format, somme de contrôle), puis comparée à ses propres tiroirs.
    var recipientState: RecipientState {
        switch StellarAddressParser.parse(addressText) {
        case nil:
            return .empty
        case .failure(let issue):
            return .invalid(issue)
        case .success(let recipient):
            if let own = context?.drawers.first(where: { $0.address == recipient.address }) {
                return .invalid(.ownDrawer(name: own.title, isMain: own.kind == .main))
            }
            return .valid(recipient)
        }
    }

    /// Le champ memo ID n'a de sens que pour une adresse G : une adresse M porte déjà son ID,
    /// et un contrat (C) n'en a pas.
    var acceptsMemoID: Bool {
        if case .valid(let recipient) = recipientState { return recipient.kind == .account }
        return false
    }

    var memoIDState: Result<UInt64, MemoIDIssue>? {
        acceptsMemoID ? StellarAddressParser.parseMemoID(memoText) : nil
    }

    /// Adresse réellement payée : l'éventuel memo ID est plié dans une adresse M.
    var resolvedRecipient: StellarRecipient? {
        guard case .valid(let recipient) = recipientState else { return nil }
        switch memoIDState {
        case nil:
            return recipient
        case .failure:
            return nil
        case .success(let memoID):
            return StellarAddressParser.folding(memoID: memoID, into: recipient)
        }
    }

    /// Nom du destinataire s'il vient des récents (« Maya »).
    var recipientName: String? { chosenContact?.name }

    var canContinueFromRecipient: Bool { resolvedRecipient != nil }

    func pasteAddress(_ text: String) {
        addressText = StellarAddressParser.clean(text)
    }

    func choose(_ contact: SendContact) {
        addressText = contact.address
        memoText = ""
        chosenContact = contact
        guard canContinueFromRecipient else { return }
        isAmountPresented = true
    }

    func continueFromRecipient() {
        guard canContinueFromRecipient else { return }
        isAmountPresented = true
    }

    // MARK: C2 · Montant et tiroir

    var drawers: [SendDrawer] { context?.drawers ?? [] }

    var selectedDrawer: SendDrawer? {
        drawers.first { $0.id == selectedDrawerID } ?? drawers.first
    }

    var canChooseDrawer: Bool { drawers.count > 1 }

    var available: Decimal { selectedDrawer?.balance(of: asset) ?? 0 }

    var amountIssue: AmountIssue? {
        guard let drawer = selectedDrawer, amount.value > available else { return nil }
        return .insufficient(drawer: drawer.title, available: asset.displayedWithCode(available))
    }

    var canReview: Bool {
        loadPhase == .loaded
            && hasDestination
            && selectedDrawer != nil
            && amount.value > 0
            && amountIssue == nil
    }

    /// Envoi : une adresse valide. Move : un tiroir d'arrivée différent du tiroir de départ.
    private var hasDestination: Bool {
        switch kind {
        case .send: resolvedRecipient != nil
        case .move: destinationDrawer != nil && destinationDrawer?.id != selectedDrawer?.id
        }
    }

    // MARK: E1 · Move : tiroir d'arrivée

    /// Tiroir d'arrivée d'un Move.
    var destinationDrawer: SendDrawer? {
        guard isMove, let destinationDrawerID else { return nil }
        return drawers.first { $0.id == destinationDrawerID }
    }

    /// Main → la première carte ; une carte → Main (comme la maquette E1 : « Main account » → « Jungle's wallet »).
    private func defaultDestination(for source: String) -> String? {
        source == "main" ? drawers.first { $0.id != "main" }?.id : drawers.first { $0.id == "main" }?.id
    }

    /// Solde du tiroir d'arrivée, puis après le Move s'il y a un montant valide (« 62.50 → 112.50 USDC »).
    var destinationBalanceLine: (before: String, after: String?) {
        let held = destinationDrawer?.balance(of: asset) ?? 0
        let value = amount.value
        guard value > 0, value <= available else { return (asset.displayedWithCode(held), nil) }
        return (asset.displayed(held), asset.displayedWithCode(held + value))
    }

    func showDestinationSheet() {
        guard isMove, drawers.count > 1 else { return }
        isDestinationSheetPresented = true
    }

    /// Choisir le tiroir d'arrivée ; si c'est le tiroir de départ, les deux s'échangent (jamais le même des deux côtés).
    func selectDestination(drawerID: String) {
        if drawerID == selectedDrawerID { selectedDrawerID = destinationDrawerID ?? selectedDrawerID }
        destinationDrawerID = drawerID
        isDestinationSheetPresented = false
    }

    /// ⇅ : départ et arrivée s'échangent. Le montant est gardé (le message dit s'il dépasse le nouveau solde).
    func swapDrawers() {
        guard isMove, let destination = destinationDrawerID else { return }
        destinationDrawerID = selectedDrawerID
        selectedDrawerID = destination
    }

    /// Solde du tiroir choisi, puis solde après l'envoi s'il y a un montant valide (« 720 → 695 USDC »).
    var balanceLine: (before: String, after: String?) {
        let value = amount.value
        guard value > 0, value <= available else { return (asset.displayedWithCode(available), nil) }
        return (asset.displayed(available), asset.displayedWithCode(available - value))
    }

    /// Équivalent en dollars pour un actif à prix variable (« ≈ $6.25 »), si un prix est connu.
    var usdEquivalent: String? {
        usdEquivalent(of: amount.value, asset: asset)
    }

    /// Équivalent en dollars du montant figé pour la vérification (C4).
    func usdEquivalent(of draft: SendDraft) -> String? {
        usdEquivalent(of: draft.amount, asset: draft.asset)
    }

    private func usdEquivalent(of value: Decimal, asset: SendAsset) -> String? {
        guard asset.hasVariablePrice, let price = context?.usdPrices[asset] else { return nil }
        let usd = (value * price).truncated(to: 2)
        return usd.formatted(.currency(code: "USD").presentation(.narrow))
    }

    func press(_ key: ChimpKeypadKey) {
        if !amount.apply(key, maxFractionDigits: asset.maxFractionDigits) {
            rejectedKeyCount += 1
        }
    }

    func isQuickAmountSelected(_ value: Decimal) -> Bool {
        !amount.isEmpty && amount.value == value
    }

    func setAmount(_ value: Decimal) {
        amount = AmountEntry(value, maxFractionDigits: asset.maxFractionDigits, minFractionDigits: asset == .usdc ? 2 : 0)
    }

    /// Tout le solde de l'actif dans ce tiroir. Rien à garder pour les frais (payés par ChimpDAO)
    /// ni pour une réserve (une adresse C n'en a pas) : à confirmer par Pamphile (DESIGN_NOTES §12).
    func setMax() {
        setAmount(available)
    }

    var isMaxSelected: Bool { available > 0 && !amount.isEmpty && amount.value == available.truncated(to: asset.maxFractionDigits) }

    func showDrawerSheet() {
        guard canChooseDrawer else { return }
        isDrawerSheetPresented = true
    }

    func select(drawerID: String) {
        if isMove, drawerID == destinationDrawerID { destinationDrawerID = selectedDrawerID }
        selectedDrawerID = drawerID
        isDrawerSheetPresented = false
    }

    func select(asset newAsset: SendAsset) {
        if newAsset != asset {
            asset = newAsset
            amount = amount.clamped(toFractionDigits: newAsset.maxFractionDigits)
        }
        isAssetSheetPresented = false
    }

    /// Fige le brouillon et ouvre la vérification (C4).
    func continueToReview() {
        guard canReview, let drawer = selectedDrawer, let network = context?.network else { return }
        switch kind {
        case .send:
            guard let recipient = resolvedRecipient else { return }
            draft = SendDraft(
                recipient: recipient, recipientName: recipientName, drawer: drawer,
                asset: asset, amount: amount.value, network: network
            )
        case .move:
            // L'adresse du tiroir d'arrivée, vérifiée comme une adresse collée (somme de contrôle, forme canonique).
            guard let destination = destinationDrawer,
                  case .success(let recipient) = StellarAddressParser.parse(destination.address) else { return }
            draft = SendDraft(
                recipient: recipient, recipientName: destination.title, drawer: drawer,
                asset: asset, amount: amount.value, network: network, destination: destination
            )
        }
        isReviewPresented = true
    }

    // MARK: C4 → C5 / C6 · Signature

    /// Rien ne doit interrompre ces étapes : retour par glissement, fermeture des feuilles et bouton retour bloqués.
    var isSigningLocked: Bool {
        switch signingStage {
        case .preparing, .scanning, .sending, .checking, .finished: true
        case .idle, .enteringPin, .waitingForTap, .wrongCard: false
        }
    }

    /// Feuille de signature (PIN ou tap) affichée.
    var isSigningSheetPresented: Bool {
        switch signingStage {
        case .enteringPin, .waitingForTap, .scanning: true
        case .idle, .preparing, .sending, .checking, .finished, .wrongCard: false
        }
    }

    /// Écran d'état (envoi en cours, C9, issue incertaine) à la place de la vérification.
    var showsStatus: Bool {
        switch signingStage {
        case .sending, .checking, .finished: true
        case .idle, .preparing, .enteringPin, .waitingForTap, .scanning, .wrongCard: false
        }
    }

    /// Les étapes de la signature, dans l'ordre choisi. Sert aux libellés « Step 1 of 2 · PIN ».
    var signingSteps: [SigningStep] {
        guard let drawer = draft?.drawer else { return [] }
        if let cardCheck, !cardCheck.usesPin {
            // Ordre « tap puis PIN » : la carte lue n'a pas de PIN, le premier tap signe directement.
            return [.tapToSign]
        }
        switch (signingOrder, drawer.usesPin) {
        case (_, false): return [.tapToSign]
        case (.pinThenTap, true): return [.pin, .tapToSign]
        case (.tapThenPin, true): return [.tapToRead, .pin, .tapToSign]
        }
    }

    /// Étape affichée dans la feuille.
    var currentSigningStep: SigningStep? {
        switch signingStage {
        case .enteringPin: .pin
        case .waitingForTap(let step), .scanning(let step): step
        case .idle, .preparing, .sending, .checking, .finished, .wrongCard: nil
        }
    }

    /// « Looks good » : prépare l'envoi (réseau, avant toute session NFC), puis ouvre la première feuille.
    /// Ignoré si une signature est déjà en cours : impossible d'envoyer deux fois.
    func confirmReview() {
        guard signingStage == .idle, let draft else { return }
        signingErrorMessage = nil
        technicalDetails = nil
        signingStage = .preparing
        Task {
            do {
                prepared = try await service.prepare(draft)
                beginSigning()
            } catch {
                signingStage = .idle
                signingErrorMessage = Self.preparationMessage(for: error, drawer: draft.drawer)
                technicalDetails = Self.details(error)
            }
        }
    }

    private func beginSigning() {
        pin = ""
        pinState = .entering
        cardCheck = nil
        tapProblem = nil
        switch signingSteps.first {
        case .pin: signingStage = .enteringPin
        case .tapToRead: signingStage = .waitingForTap(.tapToRead)
        case .tapToSign, nil: signingStage = .waitingForTap(.tapToSign)
        }
    }

    /// PIN complet : on passe au tap qui signe. Le PIN n'est envoyé à la carte que pendant ce tap.
    func pinEntered(_ value: String) {
        guard signingStage == .enteringPin, value.count == pinLength else { return }
        pin = value
        tapProblem = nil
        signingStage = .waitingForTap(.tapToSign)
    }

    /// « Scan my card » : ouvre la session NFC. Avant le tap qui signe, l'autorisation est refaite si elle arrive à
    /// expiration (réseau, avant la session NFC).
    func scanCard() {
        guard case .waitingForTap(let step) = signingStage, let current = prepared else { return }
        signingStage = .scanning(step)
        tapProblem = nil
        Task {
            do {
                // Autorisation refaite si elle arrive à expiration (réseau, avant la session NFC).
                let fresh = try await service.refreshedIfNeeded(current)
                prepared = fresh
                switch step {
                case .tapToRead:
                    let read = try await service.readCard(for: fresh)
                    cardCheck = read.check
                    if let signed = read.signed {
                        // Carte sans PIN : elle a signé dans le même tap.
                        pin = ""
                        self.signed = signed
                        await send(signed)
                    } else {
                        signingStage = .enteringPin
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

    /// Échec **avant** toute signature : rien n'est parti. Annulation : retour à la feuille, sans message.
    /// Le PIN n'est effacé que s'il est en cause ; sinon il reste en mémoire pour retaper (« PIN ready »), et il sera
    /// effacé à la signature ou à l'annulation.
    private func handleTapError(_ error: Error, step: SigningStep) {
        switch error {
        case ChipError.cancelled:
            signingStage = .waitingForTap(step)
        case ChipError.wrongPIN(let retriesLeft):
            pin = ""
            pinState = .wrong(triesLeft: retriesLeft)
            signingStage = .enteringPin
        case ChipError.pinLocked:
            pin = ""
            pinState = .blocked
            signingStage = .enteringPin
        case ChipError.pinRequired:
            // La carte a un PIN que l'app ne pensait pas nécessaire : on le demande, puis on retape.
            pin = ""
            pinState = .entering
            signingStage = .enteringPin
        case ChipError.cardNotAccepted(let tapped):
            // C7 : rien n'a été envoyé à cette carte après la lecture de sa clé (ni PIN, ni signature).
            technicalDetails = Self.details(error)
            signingStage = .wrongCard(wrongCard(tapped: tapped), retry: step == .tapToRead ? .tapToRead : .tapToSign)
        default:
            tapProblem = Self.tapProblem(for: error)
            technicalDetails = Self.details(error)
            signingStage = .waitingForTap(step == .tapToRead ? .tapToRead : .tapToSign)
        }
    }

    /// C7 : quelle carte a été tapée, laquelle était attendue, et pourquoi elle ne pouvait pas signer.
    private func wrongCard(tapped: ChipPublicKey) -> WrongCard {
        let known = service.knownCard(tapped)
        if let first = cardCheck, first.publicKey != nil, first.publicKey != tapped {
            // Second tap de l'ordre « tap puis PIN » : le PIN saisi est celui de la carte lue au premier tap.
            return WrongCard(reason: .notTheSameCard, tapped: known, needed: KnownCard(name: first.cardName, color: first.cardColor))
        }
        switch draft?.drawer.kind {
        case let .card(name, color):
            return WrongCard(reason: known == nil ? .notYours : .otherWallet, tapped: known, needed: KnownCard(name: name, color: color))
        case .main, nil:
            return WrongCard(reason: .notYours, tapped: known, needed: nil)
        }
    }

    /// « Try again with your … card » (C7) : retour à la feuille du tap, avec le PIN déjà saisi s'il y en a un.
    func retryAfterWrongCard() {
        guard case .wrongCard(_, let retry) = signingStage else { return }
        signingStage = .waitingForTap(retry)
    }

    /// PIN à envoyer : seulement si la carte en a un.
    private var pinForSigning: String? {
        let cardUsesPin = cardCheck?.usesPin ?? draft?.drawer.usesPin ?? false
        return cardUsesPin && !pin.isEmpty ? pin : nil
    }

    /// « Cancel » ou feuille fermée : retour à la vérification, rien n'a été signé. Impossible pendant un scan.
    func cancelSigning() {
        switch signingStage {
        case .enteringPin, .waitingForTap, .wrongCard:
            pin = ""
            pinState = .entering
            cardCheck = nil
            prepared = nil
            tapProblem = nil
            signingStage = .idle
        case .idle, .preparing, .scanning, .sending, .checking, .finished:
            break
        }
    }

    // MARK: Envoi et issue (étape C)

    /// Après la signature : envoi, puis C9 ; sinon l'issue est vérifiée (`check`), jamais devinée.
    private func send(_ signed: SignedSend) async {
        let draft = signed.prepared.draft
        summary = SendSummary(draft)
        signingStage = .sending(.checking)
        do {
            let receipt = try await service.submit(signed) { [weak self] progress in
                self?.signingStage = .sending(progress)
            }
            finish(with: .sent(receipt))
        } catch {
            technicalDetails = Self.details(error)
            failureReason = SendFailureReason(error)
            guard let failure = error as? PaymentFailure else {
                // Ne devrait pas arriver (le service rend toujours une trace) : on ne conclut rien.
                signingStage = .finished(.undetermined)
                return
            }
            let waiting = PendingSend(
                trace: failure.trace, recipient: draft.recipient.address, recipientName: draft.recipientName,
                drawerTitle: draft.drawer.title, asset: draft.asset.rawValue, amount: draft.amount, signedAt: .now
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

    /// « Check again ».
    func checkAgain() {
        switch signingStage {
        case .finished(.notConfirmed), .finished(.undetermined):
            Task { await check() }
        default:
            break
        }
    }

    private func check() async {
        guard let pending else { return }
        waitTask?.cancel()
        signingStage = .checking
        do {
            switch try await service.check(pending.trace) {
            case .sent(let hash):
                let receipt = SendReceipt(
                    summary: summary ?? SendSummary(pending, network: context?.network ?? .testnet),
                    transactionHash: hash, sentAt: pending.signedAt, explorerURL: service.explorerURL(transactionHash: hash)
                )
                finish(with: .sent(receipt))
            case .pending:
                signingStage = .finished(.notConfirmed)
            case .waiting(_, let end):
                signingStage = .finished(.waiting(until: end))
                scheduleCheck(at: end)
            case .nothingSent:
                finish(with: .nothingSent)
            case .undetermined(let reason):
                technicalDetails = [technicalDetails, reason].compactMap { $0 }.joined(separator: "\n")
                signingStage = .finished(.undetermined)
            }
        } catch {
            // La vérification elle-même a échoué (réseau) : on ne conclut rien.
            technicalDetails = Self.details(error)
            signingStage = .finished(.undetermined)
        }
    }

    /// Revérifie tout seul quand l'autorisation a expiré. L'heure affichée est une estimation : si le ledger n'est
    /// pas encore fermé, la vérification redonne une nouvelle heure.
    private func scheduleCheck(at end: Date) {
        waitTask?.cancel()
        waitTask = Task { [weak self] in
            let delay = max(0, end.timeIntervalSinceNow) + 1
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            // Ne pas se laisser annuler par `check`, qui annule l'attente en cours : c'est elle qui l'appelle.
            waitTask = nil
            await check()
        }
    }

    /// Issue certaine : le paiement en attente est effacé du téléphone.
    private func finish(with outcome: SendOutcome) {
        waitTask?.cancel()
        pending = nil
        try? service.setPendingSend(nil)
        signingStage = .finished(outcome)
    }

    /// Page de la transaction dans l'explorateur (reçu, issue incertaine), si un hash est connu.
    var explorerURL: URL? {
        if case .finished(.sent(let receipt)) = signingStage { return receipt.explorerURL }
        return pending?.trace.transactionHash.flatMap(service.explorerURL(transactionHash:))
    }

    /// « Try again » après « Nothing was sent » (certain) : retour à la vérification, avec le même brouillon.
    var canTryAgain: Bool {
        signingStage == .finished(.nothingSent) && draft != nil && !resumedPending
    }

    func tryAgain() {
        guard canTryAgain else { return }
        prepared = nil
        signed = nil
        technicalDetails = nil
        failureReason = nil
        summary = nil
        signingStage = .idle
    }

    /// Fin du parcours : retour au Wallet. Un paiement en attente reste enregistré (Envoyer le rouvrira).
    func finish() {
        waitTask?.cancel()
        onExit?()
    }

    // MARK: Messages

    static func details(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }

    /// Préparation ratée (avant la carte) : rien n'a été signé.
    static func preparationMessage(for error: Error, drawer: SendDrawer) -> String {
        switch error {
        case PaymentClient.PaymentError.insufficientBalance:
            String(localized: "Not enough in \(drawer.title). Nothing was sent.")
        default:
            String(localized: "Couldn't get ready to send. Nothing was sent. Check your connection and try again.")
        }
    }

    /// Tap raté, avant toute signature : le genre de problème (le texte est choisi par la vue).
    static func tapProblem(for error: Error) -> TapProblem {
        switch error {
        case let chip as ChipError: .card(AccountSetupModel.problemKind(for: chip))
        default: .network
        }
    }
}

/// Pourquoi un envoi n'est pas passé, **après** la signature (l'autorisation a pu sortir du téléphone : on attend
/// quand même son expiration avant de dire « Nothing was sent »).
enum SendFailureReason: Equatable {
    /// Stellar injoignable (réseau, RPC).
    case network
    /// Serveur de frais occupé ou en panne.
    case feeHelperBusy
    /// Serveur de frais qui refuse.
    case feeHelperRefused
    /// Aucun `recovery_id` accepté : la signature de la carte ne correspond pas.
    case signatureRejected
    /// Refus de Stellar (simulation, envoi ou transaction échouée).
    case refused

    init?(_ error: Error) {
        let underlying = (error as? PaymentFailure)?.underlying ?? error
        switch underlying {
        case FeeSignerError.busy, FeeSignerError.unavailable: self = .feeHelperBusy
        case is FeeSignerError: self = .feeHelperRefused
        case StellarError.signatureRejected: self = .signatureRejected
        case StellarError.rpc, StellarError.sendUnanswered, is URLError: self = .network
        case StellarError.notConfirmed: return nil
        default: self = .refused
        }
    }
}

/// C7 · Wrong card : la carte tapée, celle qu'il fallait, et pourquoi.
struct WrongCard: Equatable {
    enum Reason: Equatable {
        /// Wallet d'une carte : une autre carte du compte a été tapée (« Wrong banana! »).
        case otherWallet
        /// Une carte qui n'est pas du compte.
        case notYours
        /// Ordre « tap puis PIN » : au second tap, pas la carte lue au premier (le PIN saisi est le sien).
        case notTheSameCard
    }

    let reason: Reason
    /// Carte tapée, si c'est une carte du compte connue sur ce téléphone.
    let tapped: KnownCard?
    /// Carte attendue ; `nil` depuis le Main account (n'importe quelle carte du compte).
    let needed: KnownCard?
}

/// Échec d'un tap, avant toute signature : rien n'est parti (la carte refusée a son écran, C7).
enum TapProblem: Equatable {
    /// Erreur NFC ou de la carte : messages de Chimpy de l'onboarding (DESIGN_NOTES §11.2).
    case card(OnboardingProblem.Kind)
    /// Préparation refaite juste avant le tap, ratée (réseau).
    case network
}

/// Issue d'un envoi, une fois la carte passée.
enum SendOutcome: Equatable {
    /// Confirmé sur la chaîne (C9).
    case sent(SendReceipt)
    /// Envoyé, pas encore confirmé : « Check again », jamais « Send again ».
    case notConfirmed
    /// Pas parti, mais l'autorisation signée peut encore servir jusqu'à l'heure dite : « Not sent. Please wait until
    /// {heure} before trying again », sans bouton pour renvoyer ; revérifié tout seul à la fin.
    case waiting(until: Date)
    /// Certain : rien n'est parti (l'autorisation a expiré sans servir).
    case nothingSent
    /// Impossible de trancher pour l'instant.
    case undetermined
}

/// Ordre du PIN et du tap (DESIGN_NOTES §12, question 1 : à trancher après un test avec une vraie carte).
enum SigningOrder: String, CaseIterable, Identifiable {
    /// Vérification → PIN → un tap qui vérifie la carte, envoie le PIN et signe.
    case pinThenTap
    /// Vérification → tap (lecture de la carte) → PIN → second tap qui signe. iOS ne permet pas de taper
    /// le PIN pendant que sa fenêtre NFC est ouverte : d'où le second tap.
    case tapThenPin

    var id: String { rawValue }
}

/// Une étape de la signature, telle que l'utilisateur la voit.
enum SigningStep: Equatable {
    case pin
    /// Premier tap de l'ordre « tap puis PIN » : lecture seule, rien n'est signé.
    case tapToRead
    /// Le tap qui signe.
    case tapToSign
}

/// Où en est la signature.
enum SigningStage: Equatable {
    /// Sur la vérification (C4).
    case idle
    /// Appels réseau avant la session NFC.
    case preparing
    /// Feuille du PIN.
    case enteringPin
    /// Feuille « approchez la carte », en attente de « Scan my card ».
    case waitingForTap(SigningStep)
    /// Session NFC en cours : rien ne doit l'interrompre.
    case scanning(SigningStep)
    /// Signé par la carte, envoi en cours (« Sending… »).
    case sending(PaymentProgress)
    /// C7 : la carte tapée ne peut pas signer ce paiement ; rien n'a été envoyé. `retry` : le tap à refaire.
    case wrongCard(WrongCard, retry: SigningStep)
    /// Vérification de l'issue (« Check again »).
    case checking
    /// Issue connue ou affichée (C9, incertaine, rien n'est parti).
    case finished(SendOutcome)
}
