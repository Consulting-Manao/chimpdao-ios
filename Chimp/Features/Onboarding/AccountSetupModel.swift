import Foundation
import Observation

/// Un problème pendant la création (après le tap), avec le message de Chimpy et les détails pour le support.
struct CreationProblem: Equatable {
    enum Kind: Equatable {
        /// Stellar injoignable : on peut réessayer, rien n'est perdu.
        case network
        /// Serveur de frais occupé ou en panne : réessayer dans un moment.
        case feeHelperBusy
        /// Serveur de frais qui refuse de signer : un souci de notre côté, pour le support.
        case feeHelperRefused
        /// Envoyé mais pas encore confirmé : vérifier à nouveau, **jamais** renvoyer à l'aveugle.
        case notConfirmed
        /// La signature `set_owner` de la carte a expiré : un nouveau tap est nécessaire.
        case signatureExpired
        /// La vérification de la signature de la carte a échoué : un nouveau tap est nécessaire.
        case cardCheckFailed
        /// Le compte est créé mais le téléphone n'a pas pu l'enregistrer.
        case saveFailed
        /// Autre refus du réseau (simulation, envoi).
        case other
    }

    let kind: Kind
    let technicalDetails: String

    /// Le prochain essai demande un nouveau tap de la carte (sinon, on reprend avec les mêmes signatures).
    var needsNewTap: Bool { kind == .signatureExpired || kind == .cardCheckFailed }

    static func from(_ error: Error) -> CreationProblem {
        let details = OnboardingModel.details(error)
        switch error {
        case AccountCreationError.signatureExpired:
            return .init(kind: .signatureExpired, technicalDetails: details)
        case AccountCreationError.notConfirmedOnChain, StellarError.notConfirmed, StellarError.sendUnanswered:
            return .init(kind: .notConfirmed, technicalDetails: details)
        case FeeSignerError.busy, FeeSignerError.unavailable:
            return .init(kind: .feeHelperBusy, technicalDetails: details)
        case is FeeSignerError:
            return .init(kind: .feeHelperRefused, technicalDetails: details)
        case is CardPossession.PossessionError, StellarError.signatureRejected:
            return .init(kind: .cardCheckFailed, technicalDetails: details)
        case StellarError.rpc, is URLError:
            return .init(kind: .network, technicalDetails: details)
        default:
            return .init(kind: .other, technicalDetails: details)
        }
    }
}

/// ViewModel de la création du compte : A4 (prénom), A5 (carte), A6 (PIN), confirmation, tap, code de déblocage (PUK),
/// création sur la chaîne, A7. Ne fait aucune crypto : il appelle `AccountSetupService`, `ChipSigner`, `AccountCreator`
/// et `AppSession`.
///
/// **Étape 4 : le vrai onboarding.** Le tap définit le PIN (SET PIN, le PUK s'affiche une seule fois) et signe ;
/// la création passe par le serveur de frais ; le compte n'est enregistré sur le téléphone qu'une fois confirmé
/// sur la chaîne. La répétition à blanc ne reste que dans les builds Debug et Testing (décision du 2026-09-29).
@Observable
final class AccountSetupModel {
    enum PINMode: Equatable {
        /// Infineon sans PIN : l'utilisateur en choisit un, la carte le reçoit au tap (SET PIN).
        case choose
        /// Infineon qui a déjà un PIN (ou qui vient de le recevoir) : on le demande, la carte le vérifie au tap.
        case existing
        /// DUOX : pas de PIN.
        case none
    }

    enum PINStep: Equatable {
        case first
        case confirm
        case done
    }

    /// Vraie création, ou répétition à blanc (Debug et Testing seulement).
    enum RunMode: Equatable {
        case real
        #if CHIMP_ADMIN
        case rehearsal
        #endif
    }

    enum Phase: Equatable {
        case editing
        /// Lectures réseau avant le tap.
        case preparing
        /// Feuille NFC ouverte.
        case scanning
        /// Création en cours, à cette étape.
        case creating(CreationStep)
        case created(CreationResult)
        case failed(CreationProblem)
        #if CHIMP_ADMIN
        /// Répétition : carte signée, vérifications pas encore lancées.
        case signed
        case checking
        case rehearsed(RehearsalReport)
        case rehearsalFailed(OnboardingProblem)
        #endif
    }

    /// Issue d'un tap.
    enum TapOutcome: Equatable {
        /// La carte a signé (et reçu son PIN, le cas échéant).
        case signed
        /// Le PIN est défini sur la carte mais la signature a échoué : montrer le PUK, puis refaire un tap.
        case pinSetOnly
        /// La carte a refusé le PIN : retour à la saisie.
        case wrongPIN
        /// Annulé ou échoué avant tout changement sur la carte (le problème est dans `tapProblem`).
        case failed
    }

    static let pinLength = 4
    static let maximumFirstNameLength = 30
    static let maximumCardNameLength = 20

    let choice: CardChoice
    private(set) var pinMode: PINMode
    private(set) var runMode: RunMode = .real

    var firstName = ""
    var cardName = ""
    var cardColor: ChimpCardColor = .jungle

    /// Chiffres en cours de saisie (liés au pavé). Jamais enregistrés ni journalisés.
    var pinEntry = ""
    var pinState: ChimpPinState = .entering
    private(set) var pinStep: PINStep
    private var firstPIN: String?
    /// PIN confirmé, gardé en mémoire **seulement jusqu'à ce que la carte ait signé**, puis effacé.
    private var chosenPIN: String?

    var isShowingTapSheet = false
    private(set) var phase: Phase = .editing
    /// Problème survenu avant ou pendant le tap (affiché sur l'écran de confirmation).
    private(set) var tapProblem: OnboardingProblem?

    /// Code de déblocage renvoyé par la carte, à montrer **une seule fois**, effacé dès « I wrote it down ».
    private(set) var unlockCode: Data?
    /// Le PIN a été défini par un essai précédent dont le PUK s'est perdu : il n'y a pas de code à montrer.
    private(set) var unlockCodeLost = false
    /// La carte a reçu son PIN pendant cette cérémonie (irréversible).
    private(set) var pinWasSet = false
    /// Dernière étape de création atteinte (affichée en cas d'échec).
    private(set) var lastReachedStep: CreationStep?

    private let service: AccountSetupService
    private let creator: AccountCreator
    private let signer: ChipSigner
    private let session: AppSession?
    /// Le réseau où le compte sera créé (`nil` dans le catalogue, sans session).
    var network: StellarNetwork? { session?.network }
    private let accountSalt: Data
    private var plan: AccountSetupPlan?
    private var signatures: [ChipSignedDigest]?
    /// Une création est en cours (empêche deux créations en parallèle).
    private var isCreating = false
    #if CHIMP_ADMIN
    private var rehearsal: AccountRehearsing?
    #endif

    /// `randomSalt` : sel d'une carte orpheline dont l'ancien compte est inconnu (`freshSalt` du terminal), tiré une
    /// seule fois pour toute la cérémonie. `session` : où enregistrer le compte une fois confirmé (`nil` dans le catalogue).
    init(
        choice: CardChoice,
        service: AccountSetupService,
        creator: AccountCreator,
        signer: ChipSigner,
        session: AppSession?,
        randomSalt: () throws -> Data = { try SorobanAuth.randomBytes(count: 32) }
    ) throws {
        self.choice = choice
        self.service = service
        self.creator = creator
        self.signer = signer
        self.session = session
        switch choice.kind {
        case .fresh:
            accountSalt = ChimpAccountClient.salt(for: choice.card.publicKey)
        case .orphan(let lastKnown?):
            accountSalt = try ChimpAccountClient.recoverySalt(publicKey: choice.card.publicKey, escapedFrom: lastKnown)
        case .orphan(nil):
            accountSalt = try randomSalt()
        }
        let mode: PINMode = switch choice.card.kind {
        case .duox: .none
        case .infineon2Go: choice.card.pinActive ? .existing : .choose
        }
        pinMode = mode
        pinStep = mode == .none ? .done : .first
    }

    #if CHIMP_ADMIN
    /// Debug et Testing : la même cérémonie, avec en plus la répétition à blanc.
    convenience init(
        choice: CardChoice,
        service: AccountSetupService,
        creator: AccountCreator,
        signer: ChipSigner,
        session: AppSession?,
        rehearsal: AccountRehearsing?,
        randomSalt: () throws -> Data = { try SorobanAuth.randomBytes(count: 32) }
    ) throws {
        try self.init(choice: choice, service: service, creator: creator, signer: signer, session: session, randomSalt: randomSalt)
        self.rehearsal = rehearsal
    }

    /// La répétition à blanc est-elle proposée ? (Debug et Testing, avec un service de répétition.)
    var canRehearse: Bool { rehearsal != nil }
    var isRehearsal: Bool { runMode == .rehearsal }
    #else
    var isRehearsal: Bool { false }
    #endif

    // MARK: A4, A5

    var trimmedFirstName: String { firstName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedCardName: String { cardName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canContinueFromName: Bool {
        !trimmedFirstName.isEmpty && trimmedFirstName.count <= Self.maximumFirstNameLength
    }

    var canContinueFromCard: Bool {
        !trimmedCardName.isEmpty && trimmedCardName.count <= Self.maximumCardNameLength
    }

    /// Numéro affiché (« 0007 »).
    var cardNumber: String {
        choice.tokenID.map { String(format: "%04u", $0) } ?? "····"
    }

    /// Nom affiché dans A6 et la feuille du tap (« Jungle »), ou « your » à défaut.
    var displayCardName: String { trimmedCardName.isEmpty ? String(localized: "your") : trimmedCardName }

    // MARK: A6 : PIN

    /// Le pavé a reçu 4 chiffres.
    func pinCompleted(_ pin: String) {
        guard pin.count == Self.pinLength, pin.allSatisfy(\.isNumber) else { return }
        tapProblem = nil
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
                // Comme `NewCardPin.tsx` : « The PINs don't match — start again ».
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

    /// « Change the PIN » : on repart de la première saisie, rien n'est gardé.
    func restartPIN() {
        guard pinMode != .none, !isBusy else { return }
        firstPIN = nil
        chosenPIN = nil
        pinEntry = ""
        pinState = .entering
        pinStep = .first
    }

    var canFinish: Bool { pinStep == .done && !isBusy }

    var isBusy: Bool {
        switch phase {
        case .preparing, .scanning, .creating: return true
        #if CHIMP_ADMIN
        case .checking: return true
        #endif
        default: return false
        }
    }

    // MARK: Confirmation et tap

    /// Écran de confirmation : « Create my account » (ou la répétition, en Debug et Testing) ouvre la feuille du tap.
    func openTapSheet(_ mode: RunMode) {
        guard canFinish else { return }
        runMode = mode
        tapProblem = nil
        isShowingTapSheet = true
    }

    func cancelTapSheet() {
        guard !isBusy else { return }
        isShowingTapSheet = false
    }

    /// « Scan my card » : lectures réseau d'abord (hors session NFC, règle 9), puis **un seul tap** :
    /// - vraie création, carte sans PIN : SET PIN (PUK), puis les deux signatures avec ce PIN ;
    /// - carte avec PIN : VERIFY PIN puis les deux signatures ; DUOX : les deux signatures ;
    /// - répétition : jamais SET PIN, seulement un PIN déjà défini est vérifié.
    /// Après une vraie signature, la création doit démarrer aussitôt (la signature `set_owner` ne vaut que ~10 min).
    func scan() async -> TapOutcome {
        guard canFinish else { return .failed }
        tapProblem = nil
        guard let pocket = choice.pocket else {
            failTap(OnboardingProblem(kind: .readFailed, technicalDetails: "This card has no wallet (Pocket) on chain."))
            return .failed
        }
        phase = .preparing
        let plan: AccountSetupPlan
        do {
            plan = try await service.prepare(card: choice.card, pocket: pocket, accountSalt: accountSalt)
        } catch {
            failTap(OnboardingProblem(kind: .couldntCheck, technicalDetails: OnboardingModel.details(error)))
            return .failed
        }

        phase = .scanning
        do {
            let signed: [ChipSignedDigest]
            if runMode == .real, pinMode == .choose, let chosenPIN {
                let result = try await signer.setPINAndSign(digests: plan.digests, expectedKey: choice.card.publicKey, newPIN: chosenPIN)
                pinWasSet = true
                unlockCode = result.puk
                unlockCodeLost = result.puk == nil
                signed = result.signatures
            } else {
                signed = try await signer.sign(
                    digests: plan.digests, expectedKey: choice.card.publicKey, pin: pinMode == .existing ? chosenPIN : nil
                )
            }
            self.plan = plan
            signatures = signed
            clearPIN()
            if pinWasSet { pinMode = .existing }
            isShowingTapSheet = false
            #if CHIMP_ADMIN
            if runMode == .rehearsal {
                phase = .signed
                return .signed
            }
            #endif
            // La création est lancée aussitôt par la navigation (`OnboardingModel.scanForSetup`).
            phase = .creating(.checkingCard)
            return .signed
        } catch let error as PINSetButSigningFailed {
            // Le PIN est écrit sur la carte : on montre le PUK, puis un nouveau tap signera avec ce PIN (gardé en mémoire).
            pinWasSet = true
            unlockCode = error.puk
            pinMode = .existing
            isShowingTapSheet = false
            phase = .editing
            tapProblem = OnboardingProblem(kind: Self.problemKind(for: error.underlying), technicalDetails: OnboardingModel.details(error))
            return .pinSetOnly
        } catch ChipError.cancelled {
            phase = .editing
            return .failed
        } catch ChipError.wrongPIN(let retriesLeft) {
            wrongPIN(.wrong(triesLeft: retriesLeft))
            return .wrongPIN
        } catch ChipError.pinLocked {
            wrongPIN(.blocked)
            return .wrongPIN
        } catch let error as ChipError {
            failTap(OnboardingProblem(kind: Self.problemKind(for: error), technicalDetails: OnboardingModel.details(error)))
            return .failed
        } catch {
            failTap(OnboardingProblem(kind: .readFailed, technicalDetails: OnboardingModel.details(error)))
            return .failed
        }
    }

    /// Le PIN a été refusé par la carte : retour à la saisie, avec l'état donné par la puce.
    private func wrongPIN(_ state: ChimpPinState) {
        clearPIN()
        isShowingTapSheet = false
        phase = .editing
        pinStep = .first
        pinState = state
    }

    private func failTap(_ problem: OnboardingProblem) {
        isShowingTapSheet = false
        phase = .editing
        tapProblem = problem
    }

    private func clearPIN() {
        firstPIN = nil
        chosenPIN = nil
        pinEntry = ""
    }

    static func problemKind(for error: ChipError) -> OnboardingProblem.Kind {
        switch error {
        case .nfcUnavailable: .nfcUnavailable
        case .timeout: .timeout
        case .transport, .sessionFailed: .cardMoved
        case .multipleTags: .multipleCards
        case .wrongCard: .wrongCard
        default: .readFailed
        }
    }

    // MARK: Code de déblocage

    /// « I wrote it down » : le code est effacé de la mémoire, il ne sera plus jamais montré.
    func acknowledgeUnlockCode() {
        unlockCode = nil
        unlockCodeLost = false
    }

    // MARK: Création (vraie)

    /// Crée le compte avec les signatures du dernier tap, puis l'enregistre sur le téléphone **après** confirmation.
    /// Relancée par « Try again » / « Check again » : chaque étape déjà faite sur la chaîne est sautée.
    func create() async {
        guard runMode == .real, let plan, let signatures, !isCreating else { return }
        isCreating = true
        defer { isCreating = false }
        phase = .creating(.checkingCard)
        lastReachedStep = .checkingCard
        let result: CreationResult
        do {
            result = try await creator.create(plan, signatures: signatures) { [weak self] step in
                self?.phase = .creating(step)
                self?.lastReachedStep = step
            }
        } catch {
            phase = .failed(CreationProblem.from(error))
            return
        }
        do {
            try session?.completeOnboarding(
                account: result.account,
                card: SavedCard(
                    publicKey: choice.card.publicKey.hex, chip: choice.card.kind.rawValue, tokenID: choice.tokenID,
                    pocket: choice.pocket, name: trimmedCardName, color: cardColor.rawValue
                ),
                firstName: trimmedFirstName
            )
            phase = .created(result)
        } catch {
            phase = .failed(CreationProblem(kind: .saveFailed, technicalDetails: OnboardingModel.details(error)))
        }
    }

    /// « Try again » après un échec qui ne demande pas de nouveau tap.
    func retryCreation() {
        guard case .failed(let problem) = phase, !problem.needsNewTap else { return }
        // Toutes les étapes déjà faites sur la chaîne sont relues et sautées (y compris après un échec d'enregistrement).
        Task { await create() }
    }

    /// Un nouveau tap est nécessaire (signature expirée ou refusée) : retour à A6 ; le PIN est redemandé s'il a été effacé.
    func prepareNewTap() {
        signatures = nil
        plan = nil
        phase = .editing
        if chosenPIN == nil, pinMode != .none {
            pinEntry = ""
            pinState = .entering
            pinStep = .first
        }
    }

    var createdResult: CreationResult? {
        if case .created(let result) = phase { return result }
        return nil
    }

    // MARK: Répétition à blanc (Debug et Testing)

    #if CHIMP_ADMIN
    /// Après le code de déblocage : simulations seulement. Peut être relancé (mêmes signatures, valables ~10 min).
    func check() async {
        guard let rehearsal, let plan, let signatures else { return }
        switch phase {
        case .signed, .rehearsalFailed: break
        default: return
        }
        phase = .checking
        do {
            phase = .rehearsed(try await rehearsal.rehearse(plan, signatures: signatures))
        } catch {
            phase = .rehearsalFailed(OnboardingProblem(kind: .couldntCheck, technicalDetails: OnboardingModel.details(error)))
        }
    }

    var report: RehearsalReport? {
        if case .rehearsed(let report) = phase { return report }
        return nil
    }
    #endif
}
