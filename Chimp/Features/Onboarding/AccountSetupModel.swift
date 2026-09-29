import Foundation
import Observation

/// ViewModel de la création du compte : A4 (prénom), A5 (nom et couleur de la carte), A6 (PIN et tap), code de
/// déblocage (PUK), vérifications, A7. Ne fait aucune crypto : il appelle `AccountSetupService` et `ChipSigner`.
///
/// **Étape 3 : répétition à blanc.** Le tap fait signer la carte (preuve de possession et `set_owner`), puis tout est
/// vérifié par simulation. Rien n'est envoyé au réseau (le service n'a pas de serveur de frais) et **SET PIN n'est
/// jamais envoyé** : `ChipSigner` ne sait que lire la clé, vérifier un PIN existant et signer.
@Observable
final class AccountSetupModel {
    /// Ce qu'A6 demande pour le PIN, selon la carte (décision du 2026-09-29 : PIN obligatoire sur Infineon).
    enum PINMode: Equatable {
        /// Infineon sans PIN : l'utilisateur en choisit un (saisie, confirmation), la carte le recevra à la vraie création.
        case choose
        /// Infineon qui a déjà un PIN : on le demande une fois, la carte le vérifie au tap.
        case existing
        /// DUOX : pas de PIN.
        case none
    }

    enum PINStep: Equatable {
        case first
        case confirm
        case done
    }

    enum Phase: Equatable {
        case editing
        /// Lectures réseau avant le tap (dernier ledger, adresse du compte).
        case preparing
        /// Feuille NFC ouverte.
        case scanning
        /// Carte signée, en attente des vérifications (après le code de déblocage).
        case signed
        /// Simulations en cours.
        case checking
        case succeeded(RehearsalReport)
        case failed(OnboardingProblem)
    }

    static let pinLength = 4
    static let maximumFirstNameLength = 30
    static let maximumCardNameLength = 20

    let choice: CardChoice
    let isRehearsal = true
    let pinMode: PINMode

    var firstName = ""
    var cardName = ""
    var cardColor: ChimpCardColor = .jungle

    /// Chiffres en cours de saisie (liés au pavé). Jamais enregistrés ni journalisés.
    var pinEntry = ""
    var pinState: ChimpPinState = .entering
    private(set) var pinStep: PINStep
    private var firstPIN: String?
    private var chosenPIN: String?

    var isShowingTapSheet = false
    private(set) var phase: Phase = .editing
    /// Problème survenu avant ou pendant le tap (affiché sur A6, la feuille fermée).
    private(set) var tapProblem: OnboardingProblem?

    private let service: AccountSetupService
    private let signer: ChipSigner
    private let accountSalt: Data
    private var plan: AccountSetupPlan?
    private var signatures: [ChipSignedDigest]?

    /// `randomSalt` : sel d'une carte orpheline dont l'ancien compte est inconnu (`freshSalt` du terminal), tiré une
    /// seule fois pour toute la cérémonie.
    init(choice: CardChoice, service: AccountSetupService, signer: ChipSigner, randomSalt: () throws -> Data = { try SorobanAuth.randomBytes(count: 32) }) throws {
        self.choice = choice
        self.service = service
        self.signer = signer
        switch choice.kind {
        case .fresh:
            accountSalt = ChimpAccountClient.salt(for: choice.card.publicKey)
        case .orphan(let lastKnown?):
            accountSalt = try ChimpAccountClient.recoverySalt(publicKey: choice.card.publicKey, escapedFrom: lastKnown)
        case .orphan(nil):
            accountSalt = try randomSalt()
        }
        switch choice.card.kind {
        case .duox: pinMode = .none
        case .infineon2Go: pinMode = choice.card.pinActive ? .existing : .choose
        }
        pinStep = pinMode == .none ? .done : .first
    }

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

    var isBusy: Bool { phase == .preparing || phase == .scanning || phase == .checking }

    /// « Hold your Jungle card to finish » : ouvre la feuille qui montre ce que la carte va signer (règle 8).
    func openTapSheet() {
        guard canFinish else { return }
        tapProblem = nil
        isShowingTapSheet = true
    }

    func cancelTapSheet() {
        guard !isBusy else { return }
        isShowingTapSheet = false
    }

    /// PIN envoyé à la carte pendant le tap. En répétition, seulement un PIN **déjà défini** sur la carte (VERIFY PIN) ;
    /// le PIN choisi pour une carte sans PIN n'est pas envoyé (SET PIN n'existe pas dans la répétition).
    private var pinForTap: String? {
        pinMode == .existing ? chosenPIN : nil
    }

    // MARK: Tap

    /// « Scan my card » : lectures réseau d'abord (hors session NFC, règle 9), puis un seul tap qui signe les deux digests.
    /// Renvoie `true` si la carte a signé.
    @discardableResult
    func scan() async -> Bool {
        guard canFinish, phase != .signed else { return false }
        tapProblem = nil
        guard let pocket = choice.pocket else {
            fail(OnboardingProblem(kind: .readFailed, technicalDetails: "This card has no wallet (Pocket) on chain."))
            return false
        }
        phase = .preparing
        let plan: AccountSetupPlan
        do {
            plan = try await service.prepare(card: choice.card, pocket: pocket, accountSalt: accountSalt)
        } catch {
            fail(OnboardingProblem(kind: .couldntCheck, technicalDetails: OnboardingModel.details(error)))
            return false
        }

        phase = .scanning
        do {
            let signed = try await signer.sign(digests: plan.digests, expectedKey: choice.card.publicKey, pin: pinForTap)
            self.plan = plan
            signatures = signed
            clearPIN()
            isShowingTapSheet = false
            phase = .signed
            return true
        } catch ChipError.cancelled {
            phase = .editing
        } catch ChipError.wrongPIN(let retriesLeft) {
            wrongPIN(.wrong(triesLeft: retriesLeft))
        } catch ChipError.pinLocked {
            wrongPIN(.blocked)
        } catch let error as ChipError {
            fail(OnboardingProblem(kind: Self.problemKind(for: error), technicalDetails: OnboardingModel.details(error)))
        } catch {
            fail(OnboardingProblem(kind: .readFailed, technicalDetails: OnboardingModel.details(error)))
        }
        return false
    }

    /// Le PIN de la carte (déjà défini) a été refusé : retour à la saisie, avec l'état donné par la puce.
    private func wrongPIN(_ state: ChimpPinState) {
        clearPIN()
        isShowingTapSheet = false
        phase = .editing
        pinState = state
    }

    private func fail(_ problem: OnboardingProblem) {
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

    // MARK: Vérifications (répétition à blanc)

    /// Après le code de déblocage : simulations seulement. Peut être relancé (mêmes signatures, valables ~10 min).
    func check() async {
        guard let plan, let signatures, phase == .signed || isFailedCheck else { return }
        phase = .checking
        do {
            phase = .succeeded(try await service.rehearse(plan, signatures: signatures))
        } catch {
            phase = .failed(OnboardingProblem(kind: .couldntCheck, technicalDetails: OnboardingModel.details(error)))
        }
    }

    private var isFailedCheck: Bool {
        if case .failed = phase { return true }
        return false
    }

    var report: RehearsalReport? {
        if case .succeeded(let report) = phase { return report }
        return nil
    }
}
