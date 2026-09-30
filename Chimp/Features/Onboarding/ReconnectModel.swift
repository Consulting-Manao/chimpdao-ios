import Foundation
import Observation

/// Reconnexion d'une carte déjà liée à un compte, sur un téléphone qui ne connaît pas (ou plus) ce compte
/// (décisions de Barth du 2026-09-29, DESIGN_NOTES §12) :
/// - **Infineon avec PIN** : le PIN est demandé, puis un second tap de **la même carte** le fait vérifier par la puce
///   (VERIFY PIN, `ChipSigner.verifyPIN`). Rien n'est signé ni payé.
/// - **DUOX** (pas de PIN) ou Infineon sans PIN : le tap d'A2 suffit, comme `resolveAccountForCard` du terminal.
/// - Puis **« Welcome back! »** si le prénom, le nom ou la couleur de la carte manquent sur ce téléphone.
///
/// Le compte n'est enregistré sur le téléphone (`AppSession.signIn`) qu'à la toute fin : tant que ce n'est pas fait,
/// l'onboarding reste affiché. Ne fait aucune crypto : il appelle `ChipSigner` et `AppSession`.
@Observable
final class ReconnectModel {
    let account: String
    let card: ChipKeyInfo
    let tokenID: UInt32?
    let pocket: String?

    /// Infineon dont le SELECT d'A2 a dit « PIN actif » : le PIN est vérifié par la carte avant d'ouvrir le compte.
    let needsPIN: Bool
    /// Le PIN a été accepté par la carte (ou il n'y en avait pas à vérifier).
    private(set) var isPINVerified: Bool

    // MARK: PIN

    /// Chiffres en cours de saisie (liés au pavé). Jamais enregistrés ni journalisés.
    var pinEntry = ""
    var pinState: ChimpPinState = .entering
    /// PIN complet, gardé en mémoire le temps du tap seulement.
    private var pin: String?
    var isShowingTapSheet = false
    private(set) var isScanning = false
    /// Tap raté (NFC, autre carte) : message dans la feuille du tap, le PIN reste en mémoire pour retaper.
    private(set) var tapProblem: OnboardingProblem?

    // MARK: Welcome back!

    var firstName: String
    var cardName: String
    var cardColor: ChimpCardColor
    /// Ce que « Welcome back! » demande : seulement ce qui manque sur ce téléphone.
    let asksFirstName: Bool
    let asksCard: Bool
    /// L'enregistrement sur le téléphone a échoué (texte technique).
    private(set) var saveError: String?

    private let session: AppSession
    private let signer: ChipSigner

    init(account: String, inspection: CardInspection, session: AppSession, signer: ChipSigner) {
        self.account = account
        card = inspection.card
        tokenID = inspection.tokenID
        pocket = inspection.pocket
        self.session = session
        self.signer = signer
        needsPIN = inspection.card.kind == .infineon2Go && inspection.card.pinActive
        isPINVerified = !needsPIN
        // Ce que le téléphone sait déjà : le prénom, et le nom et la couleur de la carte, enregistrés pour ce compte (ouvert,
        // ou fermé par « Disconnect this phone »).
        let known = session.wallet.account?.address == account
            ? session.wallet.account
            : session.wallet.disconnectedAccount(account)
        let saved = known?.cards.first { $0.publicKey == inspection.card.publicKey.hex }
        let knownColor = saved?.color.flatMap(ChimpCardColor.init(rawValue:))
        firstName = session.wallet.firstName ?? ""
        cardName = saved?.name ?? ""
        cardColor = knownColor ?? .jungle
        asksFirstName = session.wallet.firstName == nil
        asksCard = saved?.name == nil || knownColor == nil
    }

    static let pinLength = AccountSetupModel.pinLength

    /// Numéro affiché (« 0007 »).
    var cardNumber: String {
        tokenID.map { String(format: "%04u", $0) } ?? "····"
    }

    // MARK: PIN puis tap

    /// Le pavé a reçu 4 chiffres : la feuille du tap s'ouvre (le PIN part à la carte pendant ce tap).
    func pinCompleted(_ value: String) {
        guard needsPIN, !isPINVerified, value.count == Self.pinLength, value.allSatisfy(\.isNumber) else { return }
        pin = value
        tapProblem = nil
        isShowingTapSheet = true
    }

    /// Feuille fermée : le PIN est effacé, on le retape.
    func cancelTap() {
        guard !isScanning else { return }
        isShowingTapSheet = false
        clearPIN()
    }

    /// « Scan my card » : VERIFY PIN sur la carte lue en A2 (même clé). Renvoie vrai si le PIN est accepté.
    func scan() async -> Bool {
        guard let pin, !isScanning, !isPINVerified else { return false }
        isScanning = true
        tapProblem = nil
        defer { isScanning = false }
        do {
            try await signer.verifyPIN(expectedKey: card.publicKey, pin: pin)
            clearPIN()
            isShowingTapSheet = false
            isPINVerified = true
            return true
        } catch ChipError.cancelled {
            // Feuille NFC fermée : on reste sur la feuille du tap, le PIN est gardé.
            return false
        } catch ChipError.wrongPIN(let retriesLeft) {
            wrongPIN(.wrong(triesLeft: retriesLeft))
            return false
        } catch ChipError.pinLocked {
            wrongPIN(.blocked)
            return false
        } catch let error as ChipError {
            tapProblem = OnboardingProblem(kind: AccountSetupModel.problemKind(for: error), technicalDetails: OnboardingModel.details(error))
            return false
        } catch {
            tapProblem = OnboardingProblem(kind: .readFailed, technicalDetails: OnboardingModel.details(error))
            return false
        }
    }

    private func wrongPIN(_ state: ChimpPinState) {
        clearPIN()
        isShowingTapSheet = false
        pinState = state
    }

    private func clearPIN() {
        pin = nil
        pinEntry = ""
    }

    // MARK: Welcome back!

    var trimmedFirstName: String { firstName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedCardName: String { cardName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// « Welcome back! » est nécessaire : le prénom, le nom ou la couleur de la carte manquent sur ce téléphone.
    var needsWelcomeBack: Bool { asksFirstName || asksCard }

    var canSave: Bool {
        guard isPINVerified else { return false }
        if asksFirstName, trimmedFirstName.isEmpty || trimmedFirstName.count > AccountSetupModel.maximumFirstNameLength { return false }
        if asksCard, trimmedCardName.isEmpty || trimmedCardName.count > AccountSetupModel.maximumCardNameLength { return false }
        return true
    }

    /// Ouvre le compte sur ce téléphone, avec ce que « Welcome back! » a demandé. Le Wallet remplace alors l'onboarding.
    func save() throws {
        guard canSave else { return }
        saveError = nil
        do {
            try session.signIn(
                account: account,
                card: SavedCard(
                    publicKey: card.publicKey.hex, chip: card.kind.rawValue, tokenID: tokenID, pocket: pocket,
                    name: asksCard ? trimmedCardName : nil, color: asksCard ? cardColor.rawValue : nil
                ),
                firstName: asksFirstName ? trimmedFirstName : nil
            )
        } catch {
            saveError = OnboardingModel.details(error)
            throw error
        }
    }
}
