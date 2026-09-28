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

    /// Ce qui sera envoyé, figé au passage à la vérification (C4).
    struct Draft: Equatable {
        let recipient: StellarRecipient
        /// Nom du destinataire s'il vient des récents.
        let recipientName: String?
        let drawer: SendDrawer
        let asset: SendAsset
        /// Montant exact, indépendant de la langue du téléphone.
        let amount: Decimal
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

    /// Montant et destinataire figés pour la vérification (étape B).
    private(set) var draft: Draft?

    private let service: SendService
    private var hasLoaded = false

    init(service: SendService) {
        self.service = service
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
        guard asset.hasVariablePrice, let price = context?.usdPrices[asset] else { return nil }
        let usd = (amount.value * price).truncated(to: 2)
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
        guard canReview, let recipient = resolvedRecipient, let drawer = selectedDrawer else { return }
        draft = Draft(recipient: recipient, recipientName: recipientName, drawer: drawer, asset: asset, amount: amount.value)
        isReviewPresented = true
    }
}
