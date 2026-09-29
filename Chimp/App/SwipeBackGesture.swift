import SwiftUI
import UIKit

/// Les écrans poussés cachent la barre de navigation d'iOS (leur en-tête est `ChimpHeader`).
/// iOS désactive alors le glissement depuis le bord gauche pour revenir en arrière : on le réactive,
/// dès qu'il y a un écran sous l'écran affiché, sauf quand un écran l'interdit (`blocksSwipeBack`).
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1 && !SwipeBackLock.isLocked
    }
}

/// Interdit le retour par glissement, pour toute l'app, tant qu'un écran le demande
/// (ex. : pendant la signature et l'envoi d'une transaction).
enum SwipeBackLock {
    static var isLocked = false
}

extension View {
    /// Interdit le retour par glissement depuis le bord tant que `isBlocked` est vrai.
    /// Le verrou est levé quand l'écran disparaît, pour ne jamais rester bloqué.
    func blocksSwipeBack(_ isBlocked: Bool) -> some View {
        onChange(of: isBlocked, initial: true) { _, blocked in
            SwipeBackLock.isLocked = blocked
        }
        .onDisappear {
            SwipeBackLock.isLocked = false
        }
    }
}
