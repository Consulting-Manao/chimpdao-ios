import UIKit

/// Les écrans poussés cachent la barre de navigation d'iOS (leur en-tête est `ChimpHeader`).
/// iOS désactive alors le glissement depuis le bord gauche pour revenir en arrière : on le réactive,
/// dès qu'il y a un écran sous l'écran affiché.
///
/// Si un écran doit un jour interdire ce retour (ex. : pendant une signature), il faudra l'exclure ici.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
