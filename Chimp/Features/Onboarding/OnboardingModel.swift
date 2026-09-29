import Foundation
import Observation

/// Écrans qu'on peut pousser dans l'onboarding (A1 est la racine).
enum OnboardingRoute: Hashable {
    /// Visite guidée A1·1 à A1·4 (premier lancement seulement).
    case tour
    /// A2 : lecture de la carte.
    case reading
    /// A3 : carte neuve ou orpheline, que doit-elle faire ?
    case choice(CardChoice)
    /// H3 : pas une vraie carte ChimpDAO.
    case notAChimpCard
    /// Création du compte (état dans `OnboardingModel.setup`) : A4, A5, A6, code de déblocage, vérifications, A7.
    case yourName
    case nameYourCard
    case pickPIN
    case unlockCode
    case setupCheck
    case welcome
}

/// Ce qu'A3 montre de la carte lue.
struct CardChoice: Hashable {
    enum Kind: Hashable {
        /// Enregistrée, sa Pocket pointe vers elle-même : une carte neuve.
        case fresh
        /// Retirée d'un compte (`orphan`) : on peut repartir sur un nouveau compte, pas en rejoindre un.
        case orphan(lastKnown: String?)
    }

    let kind: Kind
    let card: ChipKeyInfo
    let tokenID: UInt32?
    let pocket: String?
    /// La Pocket est vide ; `nil` si on ne le sait pas.
    let pocketIsEmpty: Bool?
}

extension ChipKeyInfo: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(publicKey)
    }
}

/// Un problème pendant A2, avec le message de Chimpy et les détails techniques pour le support
/// (règle d'affichage du 2026-09-29). Les erreurs NFC ne sont jamais avalées (règle 7) : elles arrivent ici.
struct OnboardingProblem: Equatable {
    enum Kind: Equatable {
        /// Ce téléphone ne lit pas le NFC.
        case nfcUnavailable
        /// Limite de 60 s d'iOS.
        case timeout
        /// Carte retirée trop tôt, liaison perdue.
        case cardMoved
        /// Plusieurs cartes dans le champ.
        case multipleCards
        /// Carte lue, mais la vérification en ligne n'a pas abouti (réseau, `unknown`) : re-taper.
        case couldntCheck
        /// Autre erreur de lecture.
        case readFailed
        /// Au tap d'A6, ce n'est pas la carte lue en A2.
        case wrongCard
    }

    let kind: Kind
    let technicalDetails: String
}

/// ViewModel de l'onboarding (A1, visite, A2, A3, H3). Ne fait aucune crypto : il appelle `ChipReader` (lecture de la
/// carte), `OnboardingService` (réseau) et `AppSession` (ce que le téléphone retient).
@Observable
final class OnboardingModel {
    enum ReadingState: Equatable {
        /// En attente d'un « Scan my card ».
        case idle
        /// Feuille NFC ouverte.
        case scanning
        /// Carte lue, vérification en ligne.
        case checking
        case failed(OnboardingProblem)
    }

    var path: [OnboardingRoute] = []
    private(set) var readingState: ReadingState = .idle
    /// Page courante de la visite guidée (0 à 3).
    var tourPage = 0

    /// Création du compte en cours (A4 à A7), `nil` avant « Start a new account ».
    private(set) var setup: AccountSetupModel?

    private let session: AppSession
    private let reader: ChipReader
    private let service: OnboardingService
    private let makeSetup: (CardChoice) throws -> AccountSetupModel

    init(
        session: AppSession,
        reader: ChipReader,
        service: OnboardingService,
        makeSetup: @escaping (CardChoice) throws -> AccountSetupModel
    ) {
        self.session = session
        self.reader = reader
        self.service = service
        self.makeSetup = makeSetup
    }

    static let tourPageCount = 4

    var isBusy: Bool { readingState == .scanning || readingState == .checking }

    // MARK: A1 et visite guidée

    /// « Let's start » : la visite au premier lancement, sinon directement la lecture de la carte.
    func start() {
        if session.wallet.tourSeen {
            openReading()
        } else {
            tourPage = 0
            path = [.tour]
        }
    }

    /// « Next » de la visite ; à la dernière page, « Tap my card ».
    func nextTourPage() {
        if tourPage < Self.tourPageCount - 1 {
            tourPage += 1
        } else {
            finishTour()
        }
    }

    /// « Skip » ou « Tap my card » : la visite ne sera plus proposée, on passe à la lecture.
    func finishTour() {
        session.markTourSeen()
        openReading()
    }

    // MARK: A2

    /// Ouvre A2 et lance tout de suite la lecture (la feuille NFC d'iOS s'affiche par-dessus).
    /// A2 remplace la visite dans la pile : « retour » ramène à A1.
    func openReading() {
        readingState = .idle
        path = [.reading]
        Task { await scan() }
    }

    /// Lit la carte, puis demande au réseau qui elle est (lecture seule, rien n'est signé ni payé).
    func scan() async {
        guard !isBusy else { return }
        readingState = .scanning
        let card: ChipKeyInfo
        do {
            card = try await reader.readKey()
        } catch ChipError.cancelled {
            readingState = .idle
            return
        } catch let error as ChipError {
            handle(error)
            return
        } catch {
            readingState = .failed(OnboardingProblem(kind: .readFailed, technicalDetails: Self.details(error)))
            return
        }

        readingState = .checking
        do {
            let inspection = try await service.inspect(card, hint: session.wallet.hint(for: card.publicKey))
            try route(inspection)
        } catch {
            readingState = .failed(OnboardingProblem(kind: .couldntCheck, technicalDetails: Self.details(error)))
        }
    }

    /// H3 « Try another card » : retour à A2 et nouvelle lecture.
    func tryAnotherCard() {
        openReading()
    }

    private func route(_ inspection: CardInspection) throws {
        switch inspection.resolution {
        case .enrolled:
            readingState = .idle
            path.append(.choice(choice(.fresh, inspection)))
        case .orphan(let lastKnown):
            readingState = .idle
            path.append(.choice(choice(.orphan(lastKnown: lastKnown), inspection)))
        case .newCard:
            readingState = .idle
            path.append(.notAChimpCard)
        case .unknown(let detail):
            readingState = .failed(OnboardingProblem(kind: .couldntCheck, technicalDetails: detail))
        case .signIn(let account, _):
            // Carte déjà dans un compte : on l'ouvre sur ce téléphone (le Wallet remplace l'onboarding).
            try session.signIn(account: account, card: SavedCard(
                publicKey: inspection.card.publicKey.hex,
                chip: inspection.card.kind.rawValue,
                tokenID: inspection.tokenID,
                pocket: inspection.pocket,
                name: nil,
                color: nil
            ))
            readingState = .idle
        }
    }

    private func choice(_ kind: CardChoice.Kind, _ inspection: CardInspection) -> CardChoice {
        CardChoice(kind: kind, card: inspection.card, tokenID: inspection.tokenID, pocket: inspection.pocket, pocketIsEmpty: inspection.pocketIsEmpty)
    }

    /// Carte sans clé, puce inconnue ou tag qui n'est pas une carte : ce n'est pas une carte ChimpDAO (H3).
    private func handle(_ error: ChipError) {
        switch error {
        case .noKey, .unknownChip, .unsupportedTag:
            readingState = .idle
            path.append(.notAChimpCard)
        case .nfcUnavailable:
            readingState = .failed(OnboardingProblem(kind: .nfcUnavailable, technicalDetails: Self.details(error)))
        case .timeout:
            readingState = .failed(OnboardingProblem(kind: .timeout, technicalDetails: Self.details(error)))
        case .transport, .sessionFailed:
            readingState = .failed(OnboardingProblem(kind: .cardMoved, technicalDetails: Self.details(error)))
        case .multipleTags:
            readingState = .failed(OnboardingProblem(kind: .multipleCards, technicalDetails: Self.details(error)))
        default:
            readingState = .failed(OnboardingProblem(kind: .readFailed, technicalDetails: Self.details(error)))
        }
    }

    // MARK: A3

    // MARK: A4 à A7 (étape 3 : répétition à blanc)

    /// « Start a new account » : une nouvelle cérémonie pour la carte lue en A2.
    func startNewAccount(with choice: CardChoice) {
        guard let model = try? makeSetup(choice) else { return }
        setup = model
        path.append(.yourName)
    }

    func continueFromName() {
        guard setup?.canContinueFromName == true else { return }
        path.append(.nameYourCard)
    }

    func continueFromCard() {
        guard setup?.canContinueFromCard == true else { return }
        path.append(.pickPIN)
    }

    /// « Scan my card » (feuille d'A6) : après le tap, le code de déblocage (nouveau PIN) ou directement les vérifications.
    func scanForSetup() {
        guard let setup else { return }
        Task {
            if await setup.scan() {
                path.append(setup.pinMode == .choose ? .unlockCode : .setupCheck)
            }
        }
    }

    func acknowledgeUnlockCode() {
        path.append(.setupCheck)
    }

    func continueAfterCheck() {
        guard setup?.report != nil else { return }
        path.append(.welcome)
    }

    /// Fin de la répétition : rien n'a été créé, retour à A1. Rien n'est enregistré sur le téléphone.
    func finishRehearsal() {
        setup = nil
        readingState = .idle
        path = []
    }

    /// Retour d'un écran de la création.
    func back() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    static func details(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }
}
