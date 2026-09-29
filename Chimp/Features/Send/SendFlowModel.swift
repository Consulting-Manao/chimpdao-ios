import Foundation
import Observation

/// ViewModel du parcours Envoyer (C1 → C9), partagé par tous ses écrans : destinataire, tiroir source,
/// actif, montant, puis (étapes B et C) vérification, signature et envoi.
///
/// Ne fait aucun calcul crypto et ne connaît que le protocole `SendService`. La vérification des adresses
/// passe par `StellarAddressParser` (SDK Stellar).
@Observable
final class SendFlowModel {
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
    private(set) var asset: SendAsset = .usdc
    private(set) var amount = AmountEntry()
    /// Augmente à chaque touche refusée : déclenche un retour haptique.
    private(set) var rejectedKeyCount = 0

    // Navigation (écrans poussés par `navigationDestination(isPresented:)`).
    var isAmountPresented = false
    var isReviewPresented = false
    var isDrawerSheetPresented = false
    var isAssetSheetPresented = false

    /// Montant et destinataire figés pour la vérification (C4).
    private(set) var draft: SendDraft?

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
    /// Message si la préparation a échoué (rien n'a été envoyé). Les erreurs détaillées viennent à l'étape C.
    private(set) var signingErrorMessage: String?
    /// Longueur du PIN des cartes : ⚠️ à confirmer avec Pamphile (le VERIFY PIN Infineon accepte 4 à 62 octets).
    let pinLength = 4

    private let service: SendService
    private var hasLoaded = false

    /// Appelé par « Done » à la fin du parcours (retour au Wallet).
    var onExit: (() -> Void)?

    init(service: SendService, signingOrder: SigningOrder = .pinThenTap) {
        self.service = service
        self.signingOrder = signingOrder
    }

    // MARK: Chargement

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
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
        return .insufficient(drawer: drawer.title, available: asset.formattedWithCode(available))
    }

    var canReview: Bool {
        loadPhase == .loaded
            && resolvedRecipient != nil
            && selectedDrawer != nil
            && amount.value > 0
            && amountIssue == nil
    }

    /// Solde du tiroir choisi, puis solde après l'envoi s'il y a un montant valide (« 720 → 695 USDC »).
    var balanceLine: (before: String, after: String?) {
        let value = amount.value
        guard value > 0, value <= available else { return (asset.formattedWithCode(available), nil) }
        return (asset.formatted(available), asset.formattedWithCode(available - value))
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
        guard canReview, let recipient = resolvedRecipient, let drawer = selectedDrawer, let network = context?.network else { return }
        draft = SendDraft(
            recipient: recipient, recipientName: recipientName, drawer: drawer,
            asset: asset, amount: amount.value, network: network
        )
        isReviewPresented = true
    }

    // MARK: C4 → C5 / C6 · Signature

    /// Rien ne doit interrompre ces étapes : retour par glissement, fermeture des feuilles et bouton retour bloqués.
    var isSigningLocked: Bool {
        switch signingStage {
        case .preparing, .scanning, .signed: true
        case .idle, .enteringPin, .waitingForTap: false
        }
    }

    /// Feuille de signature (PIN ou tap) affichée.
    var isSigningSheetPresented: Bool {
        switch signingStage {
        case .enteringPin, .waitingForTap, .scanning: true
        case .idle, .preparing, .signed: false
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
        case .idle, .preparing, .signed: nil
        }
    }

    /// « Looks good » : prépare l'envoi (réseau, avant toute session NFC), puis ouvre la première feuille.
    /// Ignoré si une signature est déjà en cours : impossible d'envoyer deux fois.
    func confirmReview() {
        guard signingStage == .idle, let draft else { return }
        signingErrorMessage = nil
        signingStage = .preparing
        Task {
            do {
                prepared = try await service.prepare(draft)
                beginSigning()
            } catch {
                signingStage = .idle
                signingErrorMessage = String(localized: "Couldn't get ready to send. Nothing was sent. Check your connection and try again.")
            }
        }
    }

    private func beginSigning() {
        pin = ""
        pinState = .entering
        cardCheck = nil
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
        signingStage = .waitingForTap(.tapToSign)
    }

    /// « Scan my card » : ouvre la session NFC (factice ici).
    func scanCard() {
        guard case .waitingForTap(let step) = signingStage, let prepared else { return }
        signingStage = .scanning(step)
        Task {
            do {
                switch step {
                case .tapToRead:
                    let check = try await service.readCard(for: prepared)
                    cardCheck = check
                    if check.usesPin {
                        signingStage = .enteringPin
                    } else {
                        // Carte sans PIN : au jalon 5, la même session NFC signera directement (un seul tap).
                        signed = try await service.sign(prepared, pin: nil)
                        finishSigning()
                    }
                case .tapToSign, .pin:
                    signed = try await service.sign(prepared, pin: pinForSigning)
                    finishSigning()
                }
            } catch {
                // TODO(étape C) : mauvais PIN, carte bloquée, carte retirée, mauvaise carte, délai dépassé.
                pin = ""
                signingStage = .waitingForTap(step)
            }
        }
    }

    /// PIN à envoyer : seulement si la carte en a un.
    private var pinForSigning: String? {
        let cardUsesPin = cardCheck?.usesPin ?? draft?.drawer.usesPin ?? false
        return cardUsesPin && !pin.isEmpty ? pin : nil
    }

    private func finishSigning() {
        pin = ""
        signingStage = .signed
    }

    /// « Cancel » ou feuille fermée : retour à la vérification, rien n'a été signé. Impossible pendant un scan.
    func cancelSigning() {
        switch signingStage {
        case .enteringPin, .waitingForTap:
            pin = ""
            pinState = .entering
            cardCheck = nil
            prepared = nil
            signingStage = .idle
        case .idle, .preparing, .scanning, .signed:
            break
        }
    }

    /// Fin du parcours (provisoire, étape B) : retour au Wallet.
    func finish() {
        onExit?()
    }
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
    /// Signé par la carte (l'envoi vient à l'étape C).
    case signed
}
