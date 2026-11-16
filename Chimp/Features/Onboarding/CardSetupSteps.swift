import Foundation
import Observation

/// Ce que les écrans A4 (prénom), A5 (nom et couleur de la carte) et A6 (PIN) demandent à leur ViewModel. Partagés par
/// la création du compte (`AccountSetupModel`) et l'ajout d'une carte (`AddCardModel`, G1b et A8) : mêmes écrans, pas
/// de copie.
protocol FirstNameEditing: AnyObject, Observable {
    var firstName: String { get set }
    var trimmedFirstName: String { get }
    var canContinueFromName: Bool { get }
}

protocol CardNaming: AnyObject, Observable {
    var cardName: String { get set }
    var cardColor: ChimpCardColor { get set }
    /// La carte s'affichera avec le dessin de son NFT au lieu de sa couleur (choix local, comme la couleur).
    var usesCardDesign: Bool { get set }
    var trimmedCardName: String { get }
    /// Clé publique de la carte qu'on nomme, pour aller chercher son dessin ; `nil` tant qu'elle n'est pas lue.
    var namedCardKey: ChipPublicKey? { get }
    /// « 0007 ».
    var cardNumber: String { get }
    /// Le wallet de la carte est vide ; `nil` si on ne le sait pas.
    var pocketIsEmpty: Bool? { get }
    var canContinueFromCard: Bool { get }
}

protocol CardPINChoosing: AnyObject, Observable {
    var pinMode: AccountSetupModel.PINMode { get }
    var pinStep: AccountSetupModel.PINStep { get }
    var pinEntry: String { get set }
    var pinState: ChimpPinState { get set }
    var isBusy: Bool { get }
    var canFinish: Bool { get }
    var displayCardName: String { get }
    var cardColor: ChimpCardColor { get set }
    /// La carte a reçu son PIN pendant cette cérémonie (irréversible).
    var pinWasSet: Bool { get }
    var tapProblem: OnboardingProblem? { get }
    func pinCompleted(_ pin: String)
    func restartPIN()
}

extension AccountSetupModel: FirstNameEditing, CardNaming, CardPINChoosing {
    var pocketIsEmpty: Bool? { choice.pocketIsEmpty }
}
