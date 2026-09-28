import SwiftUI

/// État de la saisie du PIN.
enum ChimpPinState: Equatable {
    /// Saisie normale.
    case entering
    /// PIN refusé par la carte. `triesLeft` vient de la réponse de la puce (Infineon : `63 Cx`,
    /// x = essais restants), jamais d'un compteur de l'app ; `nil` si la réponse ne le dit pas.
    case wrong(triesLeft: Int?)
    /// Carte bloquée (Infineon : `69 83`).
    case blocked
}

/// Points du PIN : un rond par chiffre, plein quand le chiffre est saisi.
struct ChimpPinDots: View {
    /// Longueur du PIN (paramètre : on ne connaît pas encore celle des cartes Infineon).
    let length: Int
    let filled: Int
    var isError = false

    var body: some View {
        HStack(spacing: ChimpSize.pinDotSpacing) {
            ForEach(0..<length, id: \.self) { index in
                let isFilled = index < filled
                Circle()
                    .fill(isFilled ? dotColor : .clear)
                    .overlay { Circle().strokeBorder(isError ? Color(.chimpNegative) : Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
                    .frame(width: ChimpSize.pinDot, height: ChimpSize.pinDot)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("PIN"))
        .accessibilityValue(Text("\(filled) of \(length) digits entered"))
    }

    private var dotColor: Color {
        isError ? Color(.chimpNegative) : Color(.chimpTextPrimary)
    }
}

/// Saisie du PIN : points (ou cadenas si la carte est bloquée), message, puis pavé numérique.
///
/// - La longueur du PIN est un paramètre.
/// - Erreur (`.wrong`) : les points passent au rouge et tremblent (sauf « Réduire les animations »),
///   retour haptique d'erreur, message lu par VoiceOver, puis le PIN est vidé. Taper un nouveau
///   chiffre repasse l'état à `.entering`.
/// - Carte bloquée (`.blocked`) : cadenas, message, ligne d'aide, pavé désactivé.
///
/// Le PIN n'est gardé que dans la variable `pin` de l'écran appelant : jamais enregistré ni journalisé.
/// Ce composant ne suppose aucun ordre entre le PIN et le tap de la carte.
struct ChimpPinPad<Middle: View>: View {
    @Binding var pin: String
    let length: Int
    @Binding var state: ChimpPinState
    /// Ligne d'aide sous « carte bloquée ».
    var blockedHelp: LocalizedStringKey = Self.defaultBlockedHelp
    /// Appelé quand le PIN atteint sa longueur.
    var onComplete: (String) -> Void = { _ in }
    /// Contenu optionnel entre les points et le pavé (ex. : bulle de Chimpy en A6).
    @ViewBuilder var middle: Middle

    // TODO(jalon 4) : texte provisoire. Que doit faire l'utilisateur d'une carte bloquée (PUK ?) ?
    // À écrire quand le déblocage sera décidé avec Pamphile (DESIGN_NOTES §10, points 3 et 16).
    static var defaultBlockedHelp: LocalizedStringKey { "Unlocking a card isn't available yet." }

    @State private var isShowingError = false
    @State private var shakeTrigger = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: ChimpSpacing.l)
            display
            middle
            Spacer(minLength: ChimpSpacing.l)
            ChimpKeypad(mode: .pin, onKey: handle)
                .disabled(state == .blocked || isShowingError)
                .opacity(state == .blocked ? ChimpOpacity.disabled : 1)
        }
        .onChange(of: state) { _, newState in
            switch newState {
            case .wrong: showError()
            case .blocked:
                // Le PIN refusé ne reste pas en mémoire ; même retour haptique qu'une erreur.
                pin = ""
                shakeTrigger += 1
                announce(String(localized: "This card is blocked."))
            case .entering: break
            }
        }
        .sensoryFeedback(.error, trigger: shakeTrigger)
    }

    @ViewBuilder
    private var display: some View {
        VStack(spacing: ChimpSpacing.m) {
            if state == .blocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: ChimpSize.pinDot, weight: .heavy))
                    .foregroundStyle(.chimpNegative)
                    .accessibilityHidden(true)
                VStack(spacing: ChimpSpacing.xxs) {
                    Text("This card is blocked.")
                        .chimpFont(.rowTitle)
                        .foregroundStyle(.chimpNegative)
                    Text(blockedHelp)
                        .chimpFont(.caption)
                        .foregroundStyle(.chimpTextSecondary)
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
            } else {
                ChimpPinDots(length: length, filled: isShowingError ? length : pin.count, isError: isShowingError)
                    .keyframeAnimator(initialValue: CGFloat(0), trigger: shakeTrigger) { dots, x in
                        dots.offset(x: x)
                    } keyframes: { _ in
                        KeyframeTrack {
                            LinearKeyframe(-shakeAmplitude, duration: shakeStep)
                            LinearKeyframe(shakeAmplitude, duration: shakeStep)
                            LinearKeyframe(-shakeAmplitude * 0.7, duration: shakeStep)
                            LinearKeyframe(shakeAmplitude * 0.7, duration: shakeStep)
                            LinearKeyframe(-shakeAmplitude * 0.35, duration: shakeStep)
                            LinearKeyframe(shakeAmplitude * 0.35, duration: shakeStep)
                            LinearKeyframe(0, duration: shakeStep)
                        }
                    }
                // Ligne toujours présente (vide si pas d'erreur) pour que rien ne saute à l'écran.
                Text(verbatim: wrongMessage ?? " ")
                    .chimpFont(.bodyS)
                    .foregroundStyle(.chimpNegative)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(wrongMessage == nil)
            }
        }
    }

    private var shakeAmplitude: CGFloat {
        reduceMotion ? 0 : ChimpMotion.Shake.amplitude
    }

    private var shakeStep: Double {
        ChimpMotion.Shake.duration / 7
    }

    private var wrongMessage: String? {
        guard case .wrong(let triesLeft) = state else { return nil }
        if let triesLeft {
            return String(localized: "Wrong PIN. \(triesLeft) tries left.")
        }
        return String(localized: "Wrong PIN.")
    }

    private func handle(_ key: ChimpKeypadKey) {
        switch key {
        case .digit(let value):
            guard pin.count < length else { return }
            if case .wrong = state { state = .entering }
            pin.append(String(value))
            if pin.count == length { onComplete(pin) }
        case .delete:
            if !pin.isEmpty { pin.removeLast() }
        case .decimal:
            break
        }
    }

    private func showError() {
        isShowingError = true
        shakeTrigger += 1
        if let wrongMessage { announce(wrongMessage) }
        Task {
            try? await Task.sleep(for: .seconds(ChimpMotion.Shake.errorDisplay))
            pin = ""
            isShowingError = false
        }
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}

extension ChimpPinPad where Middle == EmptyView {
    init(
        pin: Binding<String>,
        length: Int,
        state: Binding<ChimpPinState>,
        blockedHelp: LocalizedStringKey = Self.defaultBlockedHelp,
        onComplete: @escaping (String) -> Void = { _ in }
    ) {
        self.init(pin: pin, length: length, state: state, blockedHelp: blockedHelp, onComplete: onComplete) {
            EmptyView()
        }
    }
}

private struct ChimpPinPadPreview: View {
    @State private var pin = ""
    @State private var state = ChimpPinState.entering

    var body: some View {
        VStack(spacing: ChimpSpacing.l) {
            HStack {
                ChimpButton("Wrong", kind: .secondary, size: .compact) { state = .wrong(triesLeft: 2) }
                ChimpButton("Blocked", kind: .secondary, size: .compact) { state = .blocked }
                ChimpButton("Reset", kind: .secondary, size: .compact) { state = .entering; pin = "" }
            }
            ChimpPinPad(pin: $pin, length: 4, state: $state)
        }
        .padding(ChimpSpacing.xxl)
        .background(Color(.chimpBackground))
    }
}

#Preview("Light") {
    ChimpPinPadPreview()
}

#Preview("Dark") {
    ChimpPinPadPreview()
        .preferredColorScheme(.dark)
}
