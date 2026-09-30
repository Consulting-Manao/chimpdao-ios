import SwiftUI
import UIKit

extension View {
    /// Verrou de l'app (Face ID) : une **fenêtre à part**, au-dessus de tout (feuilles, alertes, parcours plein écran
    /// compris : un simple calque sous une feuille la laisserait visible). Suit le cycle de vie de la scène : verrouillage
    /// en arrière-plan, Face ID au retour au premier plan.
    func chimpAppLock(_ lock: AppLock, style: UIUserInterfaceStyle) -> some View {
        modifier(AppLockModifier(lock: lock, style: style))
    }
}

private struct AppLockModifier: ViewModifier {
    let lock: AppLock
    let style: UIUserInterfaceStyle
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .background(LockWindowHost(lock: lock, isLocked: lock.isLocked, style: style).frame(width: 0, height: 0).accessibilityHidden(true))
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .background: lock.didEnterBackground()
                case .active: Task { await lock.didBecomeActive() }
                // « Inactif » (feuille NFC, fenêtre Face ID, centre de contrôle) : rien ne change.
                case .inactive: break
                @unknown default: break
                }
            }
    }
}

/// Vue invisible qui retrouve la scène de sa fenêtre et y montre (ou retire) la fenêtre du verrou.
private struct LockWindowHost: UIViewRepresentable {
    let lock: AppLock
    let isLocked: Bool
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.lock = lock
        return view
    }

    func updateUIView(_ view: HostView, context: Context) {
        view.style = style
        view.isLocked = isLocked
    }

    final class HostView: UIView {
        var lock: AppLock?
        var isLocked = false { didSet { update() } }
        var style: UIUserInterfaceStyle = .unspecified { didSet { lockWindow?.overrideUserInterfaceStyle = style } }
        private var lockWindow: UIWindow?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            update()
        }

        private func update() {
            guard let lock, let scene = window?.windowScene else { return }
            if isLocked, lockWindow == nil {
                let lockWindow = UIWindow(windowScene: scene)
                lockWindow.windowLevel = .alert + 1
                lockWindow.overrideUserInterfaceStyle = style
                let host = UIHostingController(rootView: AppLockView(lock: lock))
                host.view.backgroundColor = .clear
                lockWindow.rootViewController = host
                lockWindow.isHidden = false
                lockWindow.makeKeyAndVisible()
                self.lockWindow = lockWindow
            } else if !isLocked, let lockWindow {
                lockWindow.isHidden = true
                self.lockWindow = nil
                window?.makeKey()
            }
        }
    }
}

/// Écran de verrouillage (non dessiné dans la maquette, texte proposé) : fond de l'en-tête, tête de Chimpy, et **toujours**
/// deux moyens d'ouvrir : « Unlock with Face ID » (Face ID, avec repli sur le code) et « Use iPhone passcode » (le code de
/// l'iPhone, directement, sans attendre un échec de Face ID). Face ID est aussi proposé tout seul au lancement, au retour
/// d'arrière-plan et en arrivant sur le compte. Pas de code propre à l'app.
struct AppLockView: View {
    let lock: AppLock

    var body: some View {
        let kind = lock.kind
        VStack(spacing: 0) {
            Spacer()
            Image(.tileHead)
                .resizable()
                .scaledToFit()
                .frame(width: 120)
                .shadow(color: .black.opacity(0.3), radius: 0, x: 5, y: 6)
                .accessibilityHidden(true)
            Text("ChimpDAO is locked")
                .chimpFont(.displayL)
                .multilineTextAlignment(.center)
                .foregroundStyle(.chimpOnHeaderPrimary)
                .padding(.top, ChimpSpacing.xxl)
                .accessibilityAddTraits(.isHeader)
            Text("Your bananas are safe on your cards.")
                .chimpFont(.bodyL)
                .multilineTextAlignment(.center)
                .foregroundStyle(.chimpOnHeaderSecondary)
                .padding(.top, ChimpSpacing.s)
            Spacer()
            if let failure = lock.lastFailure {
                ChimpTechnicalDetails(details: failure, onDarkBackground: true)
                    .padding(.bottom, ChimpSpacing.m)
            }
            if let biometry = Self.biometryTitle(kind) {
                ChimpButton(biometry, size: .large, isLoading: lock.isAuthenticating) {
                    Task { await lock.unlock() }
                }
                ChimpButton("Use iPhone passcode", kind: .onHeader, size: .large) {
                    Task { await lock.unlockWithPasscode() }
                }
                .disabled(lock.isAuthenticating)
                .padding(.top, ChimpSpacing.m)
                .padding(.bottom, ChimpSpacing.xxl)
            } else {
                // Pas de biométrie enregistrée : le code de l'iPhone seul (ou plus de code : l'app s'ouvre).
                ChimpButton(kind == .passcode ? "Use iPhone passcode" : "Unlock", size: .large, isLoading: lock.isAuthenticating) {
                    Task { await lock.unlockWithPasscode() }
                }
                .padding(.bottom, ChimpSpacing.xxl)
            }
        }
        .padding(.horizontal, ChimpSpacing.fullScreenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .chimpFullScreenBackground()
    }

    /// Bouton biométrique ; `nil` si l'iPhone n'a que son code.
    static func biometryTitle(_ kind: DeviceLockKind) -> LocalizedStringKey? {
        switch kind {
        case .faceID: "Unlock with Face ID"
        case .touchID: "Unlock with Touch ID"
        case .opticID: "Unlock with Optic ID"
        case .passcode, .unavailable: nil
        }
    }
}
