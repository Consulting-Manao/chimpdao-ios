import CoreNFC
import Foundation
import Observation

/// La carte dont on change le PIN (une Infineon du compte).
struct PINCard: Hashable, Identifiable {
    let key: ChipPublicKey
    let name: String
    let color: ChimpCardColor
    /// « 0007 ».
    let number: String

    var id: String { key.hex }
}

/// Un problème pendant le tap, avec les détails techniques pour le support.
struct ChangePINProblem: Equatable {
    enum Kind: Equatable {
        /// Erreur NFC (messages d'A2).
        case card(OnboardingProblem.Kind)
        /// Une autre carte a été tapée : elle n'a reçu aucun PIN.
        case otherCard
        /// La carte n'a pas de PIN (ou c'est une DUOX) : rien n'a changé.
        case noPIN
    }

    let kind: Kind
    let technicalDetails: String
}

/// ViewModel du changement de PIN (réglages et page d'une carte). ⚠️ CHANGE PIN n'est pas dans `reference/` (manuel
/// Infineon) : à faire valider par Pamphile. Écran de revue, PIN actuel, nouveau PIN (deux fois), puis **un tap** qui
/// démarre tout seul (lecture de la clé, puis CHANGE PIN), nouveau code de déblocage affiché une seule fois. Aucun PIN n'est gardé après l'écran.
///
/// Réponse perdue (carte retirée pendant CHANGE PIN) : on ne sait pas quel PIN est actif. Proposition (à valider) :
/// vérifier avec le **nouveau** PIN (VERIFY PIN, un tap ; un essai perdu s'il est faux) pour savoir lequel marche.
@Observable
final class ChangePINModel {
    enum Screen: Equatable {
        /// Ce qui va se passer (avant toute saisie, règle 8).
        case review
        /// PIN actuel.
        case current
        /// Nouveau PIN, puis confirmation, suivie du tap.
        case new
        case confirmNew
        /// Nouveau code de déblocage (une seule fois).
        case unlockCode
        /// La réponse de la carte s'est perdue : on ne sait pas quel PIN est actif.
        case unknownOutcome
        /// Fini. `codeLost` : le nouveau PIN est actif mais son code de déblocage n'a pas pu être montré.
        case done(codeLost: Bool)
    }

    /// Ce que la vérification après une réponse perdue a trouvé.
    enum RecoveryResult: Equatable {
        /// L'ancien PIN est toujours le bon : rien n'a changé.
        case oldPINStillActive(triesLeft: Int)
    }

    static let pinLength = 4

    let card: PINCard
    private(set) var screen = Screen.review
    var pinEntry = ""
    var pinState = ChimpPinState.entering
    var isShowingTapSheet = false
    private(set) var isBusy = false
    /// Scans lancés : le scan automatique n'a lieu que si aucun n'a démarré pendant sa courte pause.
    private(set) var scanAttempts = 0
    private(set) var problem: ChangePINProblem?
    /// Nouveau PUK, en mémoire le temps de l'écran du code seulement.
    private(set) var unlockCode: Data?
    private(set) var recoveryResult: RecoveryResult?

    private var currentPIN: String?
    private var newPIN: String?
    private let signer: ChipSigner

    init(card: PINCard, signer: ChipSigner) {
        self.card = card
        self.signer = signer
    }

    // MARK: Saisie

    func pinCompleted(_ pin: String) {
        guard pin.count == Self.pinLength, pin.allSatisfy(\.isNumber) else { return }
        problem = nil
        switch screen {
        case .current:
            currentPIN = pin
            pinEntry = ""
            pinState = .entering
            screen = .new
        case .new:
            newPIN = pin
            pinEntry = ""
            pinState = .entering
            screen = .confirmNew
        case .confirmNew:
            pinEntry = ""
            if pin == newPIN {
                pinState = .entering
                autoScan()
            } else {
                // Comme A6 (`NewCardPin.tsx`) : les deux saisies diffèrent, on recommence le nouveau PIN.
                newPIN = nil
                pinState = .mismatch
                screen = .new
            }
        default:
            break
        }
    }

    /// Retour d'un écran de saisie ou de la revue. `false` : quitter le parcours.
    func back() -> Bool {
        guard !isBusy else { return true }
        pinEntry = ""
        pinState = .entering
        switch screen {
        case .review: return false
        case .current:
            currentPIN = nil
            screen = .review
        case .new, .confirmNew:
            newPIN = nil
            currentPIN = nil
            screen = .current
        case .unlockCode, .unknownOutcome, .done: return false
        }
        return true
    }

    /// Revue lue : la saisie du PIN actuel.
    func continueFromReview() {
        guard screen == .review else { return }
        problem = nil
        pinEntry = ""
        pinState = .entering
        screen = .current
    }

    // MARK: Tap

    /// Nouveau PIN confirmé : la feuille du tap, et la fenêtre NFC d'iOS juste après, sans « Scan my card » (`AutoScan`).
    /// Feuille fermée : retaper la confirmation la rouvre.
    private func autoScan() {
        problem = nil
        isShowingTapSheet = true
        let attempts = scanAttempts
        AutoScan.start(when: { [weak self] in self?.isShowingTapSheet == true && self?.scanAttempts == attempts }) { [weak self] in
            await self?.scan()
        }
    }

    func cancelTapSheet() {
        guard !isBusy else { return }
        isShowingTapSheet = false
    }

    /// Un tap : la carte vérifie sa clé (bonne carte ? PIN actif ?), puis CHANGE PIN. Une autre carte ne reçoit aucun PIN.
    func scan() async {
        guard let currentPIN, let newPIN, !isBusy else { return }
        scanAttempts += 1
        isBusy = true
        problem = nil
        defer { isBusy = false }
        do {
            let puk = try await signer.changePIN(expectedKey: card.key, currentPIN: currentPIN, newPIN: newPIN)
            unlockCode = puk
            forgetPINs(keepingNew: false)
            isShowingTapSheet = false
            screen = .unlockCode
        } catch ChipError.cancelled {
            return
        } catch ChipError.wrongPIN(let triesLeft) {
            restartFromCurrent(state: .wrong(triesLeft: triesLeft))
        } catch ChipError.pinLocked {
            restartFromCurrent(state: .blocked)
        } catch ChipError.wrongCard {
            problem = ChangePINProblem(kind: .otherCard, technicalDetails: ChipError.wrongCard.localizedDescription)
        } catch let error as ChipError where error == .pinNotSet || error == .pinUnsupported {
            problem = ChangePINProblem(kind: .noPIN, technicalDetails: OnboardingModel.details(error))
        } catch let unknown as ChangePINOutcomeUnknown {
            // Le nouveau PIN est gardé en mémoire le temps de la vérification, jamais enregistré.
            isShowingTapSheet = false
            problem = ChangePINProblem(kind: .card(.cardMoved), technicalDetails: OnboardingModel.details(unknown.underlying))
            screen = .unknownOutcome
        } catch let error as ChipError {
            problem = ChangePINProblem(kind: .card(AccountSetupModel.problemKind(for: error)), technicalDetails: OnboardingModel.details(error))
        } catch {
            problem = ChangePINProblem(kind: .card(.readFailed), technicalDetails: OnboardingModel.details(error))
        }
    }

    private func restartFromCurrent(state: ChimpPinState) {
        forgetPINs(keepingNew: false)
        isShowingTapSheet = false
        pinEntry = ""
        pinState = state
        screen = .current
    }

    // MARK: Réponse perdue

    /// « Check with my new PIN » : VERIFY PIN avec le nouveau PIN (un tap, rien n'est signé). Accepté → le nouveau PIN est
    /// actif, son code de déblocage est perdu. Refusé (`63 Cx`) → l'ancien PIN est toujours le bon (un essai perdu).
    func checkNewPIN() async {
        guard let newPIN, !isBusy else { return }
        isBusy = true
        problem = nil
        defer { isBusy = false }
        do {
            try await signer.verifyPIN(expectedKey: card.key, pin: newPIN)
            forgetPINs(keepingNew: false)
            screen = .done(codeLost: true)
        } catch ChipError.cancelled {
            return
        } catch ChipError.wrongPIN(let triesLeft) {
            recoveryResult = .oldPINStillActive(triesLeft: triesLeft)
            forgetPINs(keepingNew: false)
            pinEntry = ""
            pinState = .entering
            screen = .current
        } catch ChipError.pinLocked {
            restartFromCurrent(state: .blocked)
        } catch let error as ChipError {
            problem = ChangePINProblem(kind: .card(AccountSetupModel.problemKind(for: error)), technicalDetails: OnboardingModel.details(error))
        } catch {
            problem = ChangePINProblem(kind: .card(.readFailed), technicalDetails: OnboardingModel.details(error))
        }
    }

    /// « I wrote it down » : le code est effacé de la mémoire.
    func acknowledgeUnlockCode() {
        unlockCode = nil
        screen = .done(codeLost: false)
    }

    private func forgetPINs(keepingNew: Bool) {
        currentPIN = nil
        if !keepingNew { newPIN = nil }
    }

    /// Le retour est bloqué pendant le tap, et après l'envoi de CHANGE PIN.
    var blocksLeaving: Bool {
        if isBusy { return true }
        switch screen {
        case .unlockCode, .unknownOutcome: return true
        default: return false
        }
    }
}

extension ChangePINModel {
    /// La vraie carte (Core NFC). Sur un appareil sans NFC (simulateur), les builds Debug et Testing prennent une carte
    /// factice (PIN accepté, code de déblocage factice).
    static func live(card: PINCard) -> ChangePINModel {
        #if DESIGN_CATALOG
        if !NFCTagReaderSession.readingAvailable {
            return ChangePINModel(card: card, signer: MockChipSigner())
        }
        #endif
        return ChangePINModel(card: card, signer: NFCChipSigner())
    }
}
