import CoreNFC
import Foundation
import Observation

/// Un problème pendant l'ajout d'une carte, avant tout envoi (lecture, vérification, tap).
struct AddCardProblem: Equatable {
    enum Kind: Equatable {
        /// Erreur NFC ou de la carte : messages de Chimpy d'A2.
        case card(OnboardingProblem.Kind)
        /// Carte sans clé, puce inconnue, carte jamais enregistrée : pas une vraie carte ChimpDAO.
        case notAChimpCard
        /// La nouvelle carte est déjà dans ce compte.
        case alreadyInAccount
        /// La nouvelle carte est encore dans un autre compte : elle doit être donnée par son titulaire.
        case otherAccount
        /// La carte tapée pour dire oui n'est pas dans le compte.
        case notAMember
        /// La nouvelle carte a été tapée à la place d'une carte du compte (« a card can't invite itself »).
        case isTheNewCard
        /// Une autre carte du compte que celle choisie pour dire oui (son PIN a été saisi pour celle-là).
        case notTheChosenCard(String)
        /// Réseau (avant toute signature) : réessayer.
        case network
    }

    let kind: Kind
    let technicalDetails: String
}

/// ViewModel de l'ajout d'une carte à un compte (ARCHITECTURE §3.12, `startAddCard` du terminal). Deux entrées :
/// - **G1 → G3** : « + Add » du Wallet, le compte est connu ;
/// - **A8 → A9** : « Join an account I already have » (A3), nouveau téléphone : la nouvelle carte a été lue en A2, le
///   compte vient d'une carte membre lue en A8.
///
/// Décision de Barth (2026-09-29) : **la nouvelle carte d'abord** (nom, couleur, PIN, puis sa signature `set_owner`),
/// **une carte du compte à la fin** (`add_card`). Ordre des envois du terminal : `set_owner` puis `add_card`, chaque
/// étape relue et sautée si elle est déjà faite (reprise sans double envoi). Ne fait aucune crypto : il appelle
/// `ChipReader`, `ChipSigner`, `AddCardService` et `AppSession`.
@Observable
final class AddCardModel: FirstNameEditing, CardNaming, CardPINChoosing {
    enum Entry: Equatable {
        case wallet(account: String)
        case join
    }

    enum Screen: Equatable {
        /// G1 : lire la nouvelle carte.
        case tapNew
        /// A4 (rejoindre seulement) : le prénom.
        case firstName
        /// G1b / A5 : nom et couleur.
        case nameCard
        /// A6 : PIN de la nouvelle carte.
        case pin
        /// A8, rejoindre seulement : lire une carte du compte pour savoir lequel.
        case findAccount
        /// « Let {carte} in? », puis le tap qui fait signer `set_owner` à la nouvelle carte.
        case confirm
        /// Code de déblocage (PUK), une seule fois.
        case unlockCode
        /// G2 / A8 : une carte du compte dit oui (`add_card`).
        case member
        /// Envois et confirmation.
        case adding
        /// G3 / A9.
        case done
    }

    /// Étapes des envois, dans l'ordre.
    enum AddStep: Int, CaseIterable, Comparable {
        /// `pocket.set_owner(compte)` signé par la nouvelle carte.
        case linking
        /// `account.add_card(nouvelle)` signé par une carte du compte.
        case admitting
        /// Relecture : la Pocket nomme le compte et le compte liste la carte.
        case confirming

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum AddingPhase: Equatable {
        case running(AddStep)
        case failed(AddStep, CreationProblem)
    }

    enum AddCardError: Error, Equatable, LocalizedError {
        case newCardSignatureExpired
        case memberSignatureExpired
        case notConfirmedOnChain(String)

        var errorDescription: String? {
            switch self {
            case .newCardSignatureExpired: "The new card's signature has expired. A new tap is needed."
            case .memberSignatureExpired: "The signature of the account's card has expired. A new tap is needed."
            case .notConfirmedOnChain(let detail): "Sent, but not visible on Stellar yet: \(detail)"
            }
        }
    }

    let entry: Entry
    private(set) var screen: Screen
    private(set) var account: String?

    // MARK: Nouvelle carte

    private(set) var newCard: ChipKeyInfo?
    private(set) var tokenID: UInt32?
    private(set) var addable: CardMembershipClient.AddableCard?

    // MARK: Noms (données du téléphone)

    var firstName = ""
    var cardName = ""
    var cardColor: ChimpCardColor

    // MARK: PIN de la nouvelle carte

    private(set) var pinMode: AccountSetupModel.PINMode = .none
    private(set) var pinStep: AccountSetupModel.PINStep = .done
    var pinEntry = ""
    var pinState: ChimpPinState = .entering
    private var firstPIN: String?
    /// PIN confirmé, gardé en mémoire **seulement jusqu'au tap**.
    private var chosenPIN: String?
    private(set) var pinWasSet = false
    private(set) var unlockCode: Data?
    private(set) var unlockCodeLost = false

    // MARK: Taps

    /// Lecture en cours (G1, A8) ou vérification en ligne.
    private(set) var isReading = false
    private(set) var isBusy = false
    private(set) var problem: AddCardProblem?
    var isShowingTapSheet = false
    /// Carte du compte lue en A8 (rejoindre) : seule elle signera `add_card` (son PIN est saisi pour elle).
    private(set) var member: ChipKeyInfo?
    var memberPIN = ""
    var memberPINState: ChimpPinState = .entering
    var isShowingMemberPINSheet = false
    var isShowingMemberTapSheet = false
    /// Nom local de la carte membre qui a dit oui.
    private(set) var memberName: String?

    // MARK: Envois

    private(set) var addingPhase: AddingPhase = .running(.linking)
    private var link: DeclaredAuthorization?
    private var linkSignature: ChipSignedDigest?
    private var linkTask: Task<Void, Never>?
    private var prepared: CardMembershipClient.PreparedAddCard?
    private var memberSignature: CardSignatures?
    /// `add_card` envoyé depuis ce téléphone (hash, carte qui a dit oui), gardé pour l'historique jusqu'à la confirmation,
    /// même à travers un « Try again ». Une cérémonie reprise sans ce hash : l'historique le relira sur la chaîne.
    private var admission: (hash: String, approvedBy: String)?
    private var isRunning = false
    /// Nombre de cartes du compte une fois la nouvelle entrée (G3), s'il est connu.
    private(set) var cardCount: Int?

    private let session: AppSession
    private let reader: ChipReader
    private let signer: ChipSigner
    private let service: AddCardService

    /// Wallet (G1) : `account` connu. Rejoindre (A8) : `newCard` lue en A2, avec son numéro.
    init(entry: Entry, session: AppSession, reader: ChipReader, signer: ChipSigner, service: AddCardService,
         newCard: ChipKeyInfo? = nil, tokenID: UInt32? = nil) {
        self.entry = entry
        self.session = session
        self.reader = reader
        self.signer = signer
        self.service = service
        let used = Set(session.wallet.account?.cards.compactMap(\.color) ?? [])
        cardColor = ChimpCardColor.allCases.first { !used.contains($0.rawValue) } ?? .jungle
        switch entry {
        case .wallet(let account):
            self.account = account
            screen = .tapNew
        case .join:
            self.newCard = newCard
            self.tokenID = tokenID
            // Rejoindre se fait sans compte ouvert : le prénom est toujours demandé (chaque compte a le sien).
            screen = .firstName
            if let newCard { setPINMode(for: newCard) }
        }
        firstName = entry == .join ? "" : session.wallet.firstName ?? ""
    }

    static let pinLength = AccountSetupModel.pinLength

    var isJoining: Bool { entry == .join }

    // MARK: G1 · Lire la nouvelle carte

    /// Lit la nouvelle carte, puis vérifie qu'elle peut entrer dans le compte (lectures seulement).
    func scanNewCard() async {
        guard case .wallet(let account) = entry, !isReading else { return }
        isReading = true
        problem = nil
        defer { isReading = false }
        let card: ChipKeyInfo
        do {
            card = try await reader.readKey()
        } catch {
            handleReadError(error)
            return
        }
        if let refusal = OnboardingProblem.refusingDuox(card, on: session.config) {
            problem = AddCardProblem(kind: .card(refusal.kind), technicalDetails: refusal.technicalDetails)
            return
        }
        do {
            let found = try await service.checkNewCard(card, account: account)
            newCard = card
            addable = found
            tokenID = found.state.tokenID
            setPINMode(for: card)
            screen = .nameCard
        } catch {
            problem = Self.problem(for: error)
        }
    }

    private func handleReadError(_ error: Error) {
        switch error {
        case ChipError.cancelled:
            break
        case ChipError.noKey, ChipError.unknownChip, ChipError.unsupportedTag:
            problem = AddCardProblem(kind: .notAChimpCard, technicalDetails: OnboardingModel.details(error))
        case let chip as ChipError:
            problem = AddCardProblem(kind: .card(AccountSetupModel.problemKind(for: chip)), technicalDetails: OnboardingModel.details(error))
        default:
            problem = AddCardProblem(kind: .card(.readFailed), technicalDetails: OnboardingModel.details(error))
        }
    }

    /// Réponses de la chaîne à la vérification : carte déjà dans le compte, dans un autre, pas enregistrée, réseau.
    static func problem(for error: Error) -> AddCardProblem {
        let details = OnboardingModel.details(error)
        switch error {
        case CardMembershipClient.MembershipError.alreadyInAccount: return AddCardProblem(kind: .alreadyInAccount, technicalDetails: details)
        case CardMembershipClient.MembershipError.belongsToAnotherAccount: return AddCardProblem(kind: .otherAccount, technicalDetails: details)
        case CardMembershipClient.MembershipError.notEnrolled: return AddCardProblem(kind: .notAChimpCard, technicalDetails: details)
        default: return AddCardProblem(kind: .network, technicalDetails: details)
        }
    }

    // MARK: A4, G1b

    var trimmedFirstName: String { firstName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedCardName: String { cardName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canContinueFromName: Bool {
        !trimmedFirstName.isEmpty && trimmedFirstName.count <= AccountSetupModel.maximumFirstNameLength
    }

    var canContinueFromCard: Bool {
        !trimmedCardName.isEmpty && trimmedCardName.count <= AccountSetupModel.maximumCardNameLength
    }

    var cardNumber: String { tokenID.map { String(format: "%04u", $0) } ?? "····" }
    var pocketIsEmpty: Bool? { nil }
    var displayCardName: String { trimmedCardName.isEmpty ? String(localized: "new") : trimmedCardName }

    func continueFromName() {
        guard canContinueFromName else { return }
        screen = .nameCard
    }

    /// Après le nom : le PIN, sauf s'il n'y a rien à signer ni à définir (DUOX, ou carte déjà liée au compte).
    func continueFromCard() {
        guard canContinueFromCard else { return }
        if pinMode == .none || addable?.needsLink == false {
            chosenPIN = nil
            pinStep = .done
            screen = isJoining && account == nil ? .findAccount : .confirm
        } else {
            screen = .pin
        }
    }

    // MARK: A6 · PIN de la nouvelle carte

    private func setPINMode(for card: ChipKeyInfo) {
        pinMode = switch card.kind {
        case .duox: .none
        case .infineon2Go: card.pinActive ? .existing : .choose
        }
        pinStep = pinMode == .none ? .done : .first
    }

    /// Même règle que l'onboarding (`NewCardPin.tsx`) : 4 chiffres, puis confirmation pour un nouveau PIN.
    func pinCompleted(_ pin: String) {
        guard pin.count == Self.pinLength, pin.allSatisfy(\.isNumber) else { return }
        problem = nil
        switch (pinMode, pinStep) {
        case (.choose, .first):
            firstPIN = pin
            pinEntry = ""
            pinStep = .confirm
        case (.choose, .confirm):
            if pin == firstPIN {
                chosenPIN = pin
                pinStep = .done
            } else {
                firstPIN = nil
                pinState = .mismatch
                pinStep = .first
            }
        case (.existing, .first):
            chosenPIN = pin
            pinStep = .done
        default:
            break
        }
    }

    func restartPIN() {
        guard pinMode != .none, !isBusy else { return }
        clearPIN()
        pinState = .entering
        pinStep = .first
    }

    var canFinish: Bool { pinStep == .done && !isBusy }

    /// Problème de carte affiché sur l'écran du PIN (A6) après un tap raté.
    var tapProblem: OnboardingProblem? {
        guard let problem, case .card(let kind) = problem.kind else { return nil }
        return OnboardingProblem(kind: kind, technicalDetails: problem.technicalDetails)
    }

    /// A6 : PIN prêt. Rejoindre : il faut d'abord trouver le compte (A8) ; sinon, la confirmation.
    func continueFromPIN() {
        guard canFinish else { return }
        screen = isJoining && account == nil ? .findAccount : .confirm
    }

    // MARK: A8 · Trouver le compte (rejoindre)

    /// Lit une carte du compte à rejoindre (lecture seule) et demande à la chaîne de quel compte elle est membre, puis
    /// vérifie que la nouvelle carte peut y entrer.
    func scanForAccount() async {
        guard isJoining, let newCard, !isReading else { return }
        isReading = true
        problem = nil
        defer { isReading = false }
        let card: ChipKeyInfo
        do {
            card = try await reader.readKey()
        } catch {
            handleReadError(error)
            return
        }
        guard card.publicKey != newCard.publicKey else {
            problem = AddCardProblem(kind: .isTheNewCard, technicalDetails: card.publicKey.hex)
            return
        }
        // La carte qui dit oui signe pour le compte (ordre 2) : une DUOX est refusée là aussi (revue F1).
        if let refusal = OnboardingProblem.refusingDuox(card, on: session.config) {
            problem = AddCardProblem(kind: .card(refusal.kind), technicalDetails: refusal.technicalDetails)
            return
        }
        do {
            guard let found = try await service.account(ofMember: card, hint: session.wallet.hint(for: card.publicKey)) else {
                problem = AddCardProblem(kind: .notAMember, technicalDetails: card.publicKey.hex)
                return
            }
            let checked = try await service.checkNewCard(newCard, account: found)
            account = found
            member = card
            addable = checked
            tokenID = tokenID ?? checked.state.tokenID
            if !checked.needsLink { chosenPIN = nil }
            screen = .confirm
        } catch {
            problem = Self.problem(for: error)
        }
    }

    // MARK: Confirmation et tap de la nouvelle carte (set_owner)

    /// « Let {carte} in? » : la nouvelle carte doit-elle encore signer ? (Non : cérémonie reprise, sa Pocket nomme déjà
    /// le compte.)
    var newCardMustSign: Bool { addable?.needsLink ?? true }

    func openTapSheet() {
        guard !isBusy else { return }
        problem = nil
        if newCardMustSign {
            isShowingTapSheet = true
        } else {
            screen = .member
            skipMemberIfAlreadyIn()
        }
    }

    func cancelTapSheet() {
        guard !isBusy else { return }
        isShowingTapSheet = false
    }

    /// « Scan my card » : l'entrée `set_owner` (réseau, avant la session NFC), puis **un tap** de la nouvelle carte :
    /// SET PIN si elle n'en a pas (le PUK revient une seule fois), puis VERIFY PIN et SIGN ; DUOX : SIGN.
    /// Le lien part aussitôt, pendant l'écran du code ou de la carte du compte (« les pointeurs d'abord »).
    func scanNewCardToSign() async {
        guard let account, let newCard, let addable, !isBusy else { return }
        isBusy = true
        problem = nil
        defer { isBusy = false }
        let declared: DeclaredAuthorization
        do {
            declared = try await service.declareLink(pocket: addable.pocket, account: account)
        } catch {
            problem = AddCardProblem(kind: .network, technicalDetails: OnboardingModel.details(error))
            return
        }
        do {
            let signature: ChipSignedDigest
            if pinMode == .choose, let chosenPIN {
                let result = try await signer.setPINAndSign(digests: [declared.digest], expectedKey: newCard.publicKey, newPIN: chosenPIN)
                pinWasSet = true
                unlockCode = result.puk
                unlockCodeLost = result.puk == nil
                signature = try Self.single(result.signatures)
            } else {
                signature = try Self.single(try await signer.sign(
                    digests: [declared.digest], expectedKey: newCard.publicKey, pin: pinMode == .existing ? chosenPIN : nil
                ))
            }
            link = declared
            linkSignature = signature
            clearPIN()
            if pinWasSet { pinMode = .existing }
            isShowingTapSheet = false
            startLinking()
            screen = unlockCode != nil || unlockCodeLost ? .unlockCode : .member
            if screen == .member { skipMemberIfAlreadyIn() }
        } catch let error as PINSetButSigningFailed {
            // Le PIN est écrit sur la carte : le code d'abord, puis un nouveau tap signera avec ce PIN (gardé en mémoire).
            pinWasSet = true
            unlockCode = error.puk
            pinMode = .existing
            isShowingTapSheet = false
            problem = AddCardProblem(kind: .card(AccountSetupModel.problemKind(for: error.underlying)), technicalDetails: OnboardingModel.details(error))
            screen = .unlockCode
        } catch ChipError.cancelled {
            return
        } catch ChipError.wrongPIN(let retriesLeft) {
            backToPIN(.wrong(triesLeft: retriesLeft))
        } catch ChipError.pinLocked {
            backToPIN(.blocked)
        } catch let error as ChipError {
            problem = AddCardProblem(kind: .card(AccountSetupModel.problemKind(for: error)), technicalDetails: OnboardingModel.details(error))
        } catch {
            problem = AddCardProblem(kind: .card(.readFailed), technicalDetails: OnboardingModel.details(error))
        }
    }

    private static func single(_ signatures: [ChipSignedDigest]) throws -> ChipSignedDigest {
        guard signatures.count == 1, let first = signatures.first else {
            throw ChipError.malformedResponse("expected 1 signature, got \(signatures.count)")
        }
        return first
    }

    private func backToPIN(_ state: ChimpPinState) {
        clearPIN()
        isShowingTapSheet = false
        pinStep = .first
        pinState = state
        screen = .pin
    }

    private func clearPIN() {
        firstPIN = nil
        chosenPIN = nil
        pinEntry = ""
    }

    /// Envoi de `set_owner` dès la signature ; `runAdding` l'attend avant de relire la chaîne (jamais deux envois
    /// en même temps). Une erreur ici n'est pas perdue : `runAdding` refait l'étape (reprise) et l'affiche.
    private func startLinking() {
        linkTask = Task { [weak self] in
            try? await self?.linkIfNeeded()
        }
    }

    /// « I wrote it down » : le code est effacé. Si la signature a échoué après SET PIN, retour à la confirmation pour
    /// un nouveau tap (VERIFY PIN, jamais un second SET PIN) ; sinon, la carte du compte.
    func acknowledgeUnlockCode() {
        unlockCode = nil
        unlockCodeLost = false
        if linkSignature == nil {
            // Le PIN est gardé en mémoire (`chosenPIN`) pour le nouveau tap.
            screen = .confirm
        } else {
            screen = .member
            skipMemberIfAlreadyIn()
        }
    }

    // MARK: G2 · Une carte du compte dit oui (add_card)

    /// Cérémonie reprise, la carte est déjà dans `cards()` : pas besoin d'une carte du compte.
    private func skipMemberIfAlreadyIn() {
        guard addable?.isMember == true else { return }
        screen = .adding
        Task { await runAdding() }
    }

    /// Un PIN est-il à demander avant le tap ? Rejoindre : la carte lue en A8 (on sait si elle a un PIN). Wallet : la
    /// carte choisie pour dire oui ; sans choix, au moins une carte du compte en a un (le PIN n'est envoyé qu'à une
    /// carte qui en a un actif), comme un envoi depuis Main.
    var memberUsesPIN: Bool {
        if let member { return member.kind == .infineon2Go && member.pinActive }
        if let chosenMember { return chosenMember.chip != ChipKind.duox.rawValue }
        return session.wallet.account?.cards.contains { $0.chip != ChipKind.duox.rawValue } ?? true
    }

    /// Nom local de la carte qui doit dire oui : lue en A8 (rejoindre) ou choisie (Wallet), s'il est connu.
    var expectedMemberName: String? {
        if let member { return session.wallet.account?.cards.first { $0.publicKey == member.publicKey.hex }?.name }
        return chosenMember?.name
    }

    /// Couleur locale de cette carte, pour sa vignette.
    var expectedMemberColor: ChimpCardColor? {
        let key = member?.publicKey.hex ?? chosenMember?.publicKey
        return session.wallet.account?.cards.first { $0.publicKey == key }?.color.flatMap(ChimpCardColor.init(rawValue:))
    }

    // MARK: G2 · Quelle carte dit oui ? (retour du call avec Pamphile, 2026-10-01)

    /// Cartes du compte qui peuvent dire oui (Wallet) : toutes, sauf la nouvelle.
    var memberCandidates: [SavedCard] {
        guard !isJoining else { return [] }
        return session.wallet.account?.cards.filter { $0.publicKey != newCard?.publicKey.hex } ?? []
    }

    /// Carte choisie pour dire oui. Avant, le PIN était demandé « pour votre carte » sans dire laquelle : on choisit
    /// d'abord la carte, puis son PIN, puis on tape **cette** carte (seule sa clé est acceptée). Une seule carte :
    /// choisie d'office.
    private(set) var chosenMemberKey: String?

    var chosenMember: SavedCard? {
        let candidates = memberCandidates
        if let chosenMemberKey { return candidates.first { $0.publicKey == chosenMemberKey } }
        return candidates.count == 1 ? candidates.first : nil
    }

    /// Plusieurs cartes possibles et aucune choisie : « Scan my card » attend le choix.
    var needsMemberChoice: Bool {
        member == nil && memberCandidates.count > 1 && chosenMember == nil
    }

    func chooseMember(_ key: String) {
        guard member == nil, !isBusy, memberCandidates.contains(where: { $0.publicKey == key }) else { return }
        if chosenMemberKey != key { memberPIN = "" }
        chosenMemberKey = key
        problem = nil
    }

    // MARK: Étapes affichées (« Step x of y »)

    /// Écrans où l'on agit, dans l'ordre : la barre « Step x of y » les compte tous, pas seulement les taps (retour du
    /// 2026-10-01 : on ne savait pas où on en était). Avant la lecture de la nouvelle carte, on compte l'étape du PIN
    /// (Infineon) ; une DUOX, sans PIN, en a une de moins.
    var progressScreens: [Screen] {
        let needsPIN = newCard == nil || (pinMode != .none && addable?.needsLink != false)
        let start: [Screen] = isJoining ? [.firstName, .nameCard] : [.tapNew, .nameCard]
        let middle: [Screen] = needsPIN ? [.pin] : []
        let end: [Screen] = isJoining ? [.findAccount, .confirm, .member] : [.confirm, .member]
        return start + middle + end
    }

    /// (étape, nombre d'étapes) d'un écran ; le code de déblocage fait partie du tap de la nouvelle carte.
    func progress(at screen: Screen) -> (step: Int, of: Int)? {
        let screens = progressScreens
        let target = screen == .unlockCode ? .confirm : screen
        guard let index = screens.firstIndex(of: target) else { return nil }
        return (index + 1, screens.count)
    }

    /// « Scan my card » de G2 : le PIN d'abord s'il en faut un (« PIN puis tap »), puis la feuille du tap.
    func startMemberStep() {
        guard !isBusy, !needsMemberChoice else { return }
        problem = nil
        if memberUsesPIN, memberPIN.count != Self.pinLength {
            memberPIN = ""
            isShowingMemberPINSheet = true
        } else {
            isShowingMemberTapSheet = true
        }
    }

    func memberPINEntered(_ value: String) {
        guard value.count == Self.pinLength else { return }
        memberPIN = value
        isShowingMemberPINSheet = false
        isShowingMemberTapSheet = true
    }

    func cancelMemberStep() {
        guard !isBusy else { return }
        memberPIN = ""
        memberPINState = .entering
        isShowingMemberPINSheet = false
        isShowingMemberTapSheet = false
    }

    /// `add_card` préparé (réseau, avant la session NFC ; refait s'il arrive à expiration), puis le tap d'une carte du
    /// compte : sa clé est comparée **avant** tout PIN ; la nouvelle carte, ou une carte hors du compte, ne reçoit rien.
    func scanMember() async {
        guard let account, let newCard, !isBusy else { return }
        isBusy = true
        problem = nil
        defer { isBusy = false }
        do {
            if let current = prepared, try await !service.needsRefresh(current) {
                // Encore valable.
            } else {
                prepared = try await service.prepareAddCard(account: account, newCard: newCard.publicKey, curve: newCard.curve)
            }
        } catch {
            problem = AddCardProblem(kind: .network, technicalDetails: OnboardingModel.details(error))
            return
        }
        guard let prepared else { return }
        let accepted: [ChipPublicKey] = if let member {
            prepared.acceptedKeys.filter { $0 == member.publicKey }
        } else if let chosenMember {
            prepared.acceptedKeys.filter { $0.hex == chosenMember.publicKey }
        } else {
            prepared.acceptedKeys
        }
        do {
            let signed = try await signer.sign(digests: [prepared.digest], acceptedKeys: accepted, pin: memberPIN.isEmpty ? nil : memberPIN)
            memberSignature = signed
            memberName = session.wallet.account?.cards.first { $0.publicKey == signed.card.publicKey.hex }?.name
            cardCount = prepared.acceptedKeys.count + 1
            memberPIN = ""
            memberPINState = .entering
            isShowingMemberTapSheet = false
            screen = .adding
            await runAdding()
        } catch ChipError.cancelled {
            return
        } catch ChipError.wrongPIN(let retriesLeft) {
            memberPINFailed(.wrong(triesLeft: retriesLeft))
        } catch ChipError.pinLocked {
            memberPINFailed(.blocked)
        } catch ChipError.pinRequired {
            memberPINFailed(.entering)
        } catch ChipError.cardNotAccepted(let tapped) {
            // Rien n'a été envoyé à cette carte après la lecture de sa clé (ni PIN, ni signature).
            let kind: AddCardProblem.Kind = if tapped == newCard.publicKey {
                .isTheNewCard
            } else if let chosen = chosenMember, prepared.acceptedKeys.contains(tapped) {
                .notTheChosenCard(chosen.name ?? String(localized: "the card you picked"))
            } else {
                .notAMember
            }
            problem = AddCardProblem(kind: kind, technicalDetails: tapped.hex)
        } catch let error as ChipError {
            problem = AddCardProblem(kind: .card(AccountSetupModel.problemKind(for: error)), technicalDetails: OnboardingModel.details(error))
        } catch {
            problem = AddCardProblem(kind: .card(.readFailed), technicalDetails: OnboardingModel.details(error))
        }
    }

    private func memberPINFailed(_ state: ChimpPinState) {
        memberPIN = ""
        memberPINState = state
        isShowingMemberTapSheet = false
        isShowingMemberPINSheet = true
    }

    // MARK: Envois : set_owner, add_card, confirmation

    /// `linkCardToAccount` : rien si la Pocket nomme déjà le compte (« a resumed ceremony »), sinon `set_owner` avec la
    /// signature du tap, si elle a encore 20 ledgers devant elle.
    private func linkIfNeeded() async throws {
        guard let account, let newCard, let addable else { return }
        guard try await service.pocketOwner(addable.pocket) != account else { return }
        guard let link, let linkSignature else { throw AddCardError.newCardSignatureExpired }
        if link.needsRefresh(currentLedger: try await service.latestLedger()) { throw AddCardError.newCardSignatureExpired }
        _ = try await service.submitLink(link, pocket: addable.pocket, account: account, curve: newCard.curve, signed: linkSignature)
    }

    /// `set_owner` (s'il le faut), puis `add_card` (s'il le faut), puis relecture, puis enregistrement sur le téléphone.
    /// Relancé par « Try again » / « Check again » : chaque étape déjà faite sur la chaîne est sautée.
    func runAdding() async {
        guard let account, let newCard, let addable, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        if let linkTask {
            await linkTask.value
            self.linkTask = nil
        }
        var step = AddStep.linking
        do {
            addingPhase = .running(.linking)
            try await linkIfNeeded()

            step = .admitting
            addingPhase = .running(.admitting)
            if try await !service.hasCard(account: account, publicKey: newCard.publicKey) {
                guard let prepared, let memberSignature else { throw AddCardError.memberSignatureExpired }
                if try await service.needsRefresh(prepared) { throw AddCardError.memberSignatureExpired }
                let hash = try await service.submitAddCard(prepared, signed: memberSignature)
                admission = (hash, memberSignature.card.publicKey.hex)
            }

            step = .confirming
            addingPhase = .running(.confirming)
            guard try await service.pocketOwner(addable.pocket) == account else {
                throw AddCardError.notConfirmedOnChain("the card doesn't point to the account yet")
            }
            guard try await service.hasCard(account: account, publicKey: newCard.publicKey) else {
                throw AddCardError.notConfirmedOnChain("the account doesn't list the card yet")
            }
        } catch {
            addingPhase = .failed(step, Self.addingProblem(error))
            return
        }
        do {
            try save(account: account, card: newCard, addable: addable)
            if let admission {
                session.recordActivity(.cardAdded(
                    hash: admission.hash, account: account, cardKey: newCard.publicKey.hex, approvedBy: admission.approvedBy
                ), account: account)
            }
            screen = .done
        } catch {
            addingPhase = .failed(.confirming, CreationProblem(kind: .saveFailed, technicalDetails: OnboardingModel.details(error)))
        }
    }

    static func addingProblem(_ error: Error) -> CreationProblem {
        let details = OnboardingModel.details(error)
        switch error {
        case AddCardError.newCardSignatureExpired, AddCardError.memberSignatureExpired:
            return CreationProblem(kind: .signatureExpired, technicalDetails: details)
        case AddCardError.notConfirmedOnChain:
            return CreationProblem(kind: .notConfirmed, technicalDetails: details)
        default:
            return CreationProblem.from(error)
        }
    }

    /// Enregistrement sur le téléphone, **après** confirmation sur la chaîne. Rejoindre : le compte s'ouvre (A9 reste
    /// affiché jusqu'à « Let's swing »).
    private func save(account: String, card: ChipKeyInfo, addable: CardMembershipClient.AddableCard) throws {
        let saved = SavedCard(
            publicKey: card.publicKey.hex, chip: card.kind.rawValue, tokenID: tokenID ?? addable.state.tokenID,
            pocket: addable.pocket, name: trimmedCardName, color: cardColor.rawValue
        )
        switch entry {
        case .wallet:
            try session.addCard(saved, account: account)
        case .join:
            try session.completeJoin(account: account, card: saved, firstName: trimmedFirstName)
        }
    }

    /// Échec qui demande un nouveau tap : la nouvelle carte (lien) ou la carte du compte (`add_card`).
    func newTapAfterFailure() {
        guard case .failed(let step, let problem) = addingPhase, problem.needsNewTap else { return }
        if step == .linking {
            link = nil
            linkSignature = nil
            screen = pinMode == .none || chosenPIN != nil ? .confirm : .pin
            if screen == .pin {
                pinStep = .first
                pinState = .entering
            }
        } else {
            prepared = nil
            memberSignature = nil
            screen = .member
        }
    }

    func retryAdding() {
        guard case .failed(_, let problem) = addingPhase, !problem.needsNewTap else { return }
        Task { await runAdding() }
    }

    /// Carte ajoutée : le Wallet (rejoindre : l'onboarding laisse la place au Wallet).
    func finish() {
        if isJoining { session.finishOnboarding() }
    }

    // MARK: Retour

    /// Écran précédent. Impossible pendant un tap ou un envoi ; depuis les envois, on ne revient jamais en arrière.
    /// Renvoie faux s'il faut quitter le parcours.
    func back() -> Bool {
        guard !isBusy, !isReading else { return true }
        problem = nil
        switch screen {
        case .tapNew: return false
        case .firstName: return false
        case .nameCard:
            if case .wallet = entry { screen = .tapNew; return true }
            screen = .firstName
            return true
        case .pin: screen = .nameCard
        case .findAccount: screen = pinMode == .none ? .nameCard : .pin
        case .confirm:
            if linkSignature != nil || pinWasSet { return true }
            if isJoining { screen = .findAccount } else { screen = pinMode == .none || addable?.needsLink == false ? .nameCard : .pin }
        case .unlockCode, .member, .adding, .done: return true
        }
        return true
    }

    /// Le retour par glissement et le bouton retour sont-ils bloqués ? (Tap, envoi, ou ce qui a déjà touché la carte.)
    var isLocked: Bool {
        switch screen {
        case .unlockCode, .member, .adding, .done: true
        case .confirm: isBusy || linkSignature != nil || pinWasSet
        default: isBusy || isReading
        }
    }
}

extension AddCardModel {
    /// G1 depuis le Wallet : la vraie carte (Core NFC) et le réseau de la session. Sur un appareil sans NFC (simulateur), les builds
    /// Debug et Testing prennent une carte et une chaîne factices ; en Release, l'erreur « pas de NFC » s'affiche.
    static func live(account: String, session: AppSession) -> AddCardModel {
        #if DESIGN_CATALOG
        if !NFCTagReaderSession.readingAvailable {
            // Carte et chaîne factices : une copie en mémoire de la session, pour que la fausse carte ne soit jamais
            // enregistrée dans le vrai fichier du téléphone.
            let scratch = AppSession(store: InMemoryLocalWalletStore(session.wallet), config: session.config)
            return AddCardModel(
                entry: .wallet(account: account), session: scratch, reader: MockChipReader(scenario: .infineon),
                signer: MockChipSigner(), service: MockAddCardService()
            )
        }
        #endif
        return AddCardModel(
            entry: .wallet(account: account), session: session, reader: NFCChipReader(), signer: NFCChipSigner(),
            service: ChainAddCardService(config: session.config)
        )
    }
}
