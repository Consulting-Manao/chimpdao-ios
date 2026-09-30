import SwiftUI
import UIKit

extension View {
    /// Impose l'apparence choisie (I2 « Look ») à **toute la fenêtre** de l'app : écrans, feuilles, alertes et feuille de
    /// partage suivent. Passer par la fenêtre plutôt que `.preferredColorScheme` : revenir à `nil` (« Auto ») avec ce
    /// dernier ne rend pas toujours la main au réglage de l'iPhone pour les vues déjà présentées.
    func chimpWindowStyle(_ style: UIUserInterfaceStyle) -> some View {
        background(WindowStyleSetter(style: style).frame(width: 0, height: 0).accessibilityHidden(true))
    }
}

/// Vue invisible qui retrouve sa fenêtre et lui applique le style.
private struct WindowStyleSetter: UIViewRepresentable {
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> WindowStyleView {
        let view = WindowStyleView()
        view.style = style
        return view
    }

    func updateUIView(_ view: WindowStyleView, context: Context) {
        view.style = style
    }

    final class WindowStyleView: UIView {
        var style: UIUserInterfaceStyle = .unspecified {
            didSet { apply() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        private func apply() {
            guard let window, window.overrideUserInterfaceStyle != style else { return }
            window.overrideUserInterfaceStyle = style
        }
    }
}
