import SwiftUI

/// En-tête des écrans (« Chimp Top » dans la maquette) : fond `chimpHeader` + motif,
/// bouton retour, titre, sous-titre, bouton réglages et barre d'étapes.
///
/// À placer tout en haut de l'écran : son fond passe sous la barre d'état.
struct ChimpHeader: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    /// Étape courante (à partir de 1) et nombre d'étapes. La barre d'étapes s'affiche si les deux sont > 0.
    var step = 0
    var steps = 0
    /// Bouton retour affiché seulement si une action est fournie.
    var onBack: (() -> Void)?
    /// Bouton réglages (roue dentée) affiché seulement si une action est fournie.
    var onSettings: (() -> Void)?

    @Environment(\.chimpScreenInsets) private var screenInsets

    private var hasSteps: Bool { step > 0 && steps > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: ChimpSpacing.m) {
                if let onBack {
                    ChimpHeaderRoundButton(size: ChimpSize.headerButton, action: onBack) {
                        ChimpBackChevron()
                            .stroke(Color(.chimpOnHeaderPrimary), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                            .frame(width: 12, height: 20)
                    }
                    .accessibilityLabel(Text("Back"))
                }

                VStack(alignment: .leading, spacing: 3) {
                    if hasSteps {
                        Text("Step \(step) of \(steps)")
                            .chimpFont(.labelWide)
                            .textCase(.uppercase)
                            .foregroundStyle(.chimpOnHeaderAccent)
                    }
                    Text(title)
                        .chimpFont(.displayM)
                        .foregroundStyle(.chimpOnHeaderPrimary)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .chimpFont(.caption)
                            .foregroundStyle(.chimpOnHeaderSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let onSettings {
                    ChimpHeaderSettingsButton(action: onSettings)
                }
            }

            if hasSteps {
                HStack(spacing: ChimpSpacing.xs) {
                    ForEach(0..<steps, id: \.self) { index in
                        Capsule()
                            .fill(index < step ? Color(.chimpAccent) : Color(.chimpStepSegmentInactive))
                            .overlay { Capsule().strokeBorder(Color(.chimpOutlineOnHeader), lineWidth: ChimpBorder.thin) }
                            .frame(height: ChimpSize.stepSegmentHeight)
                    }
                }
                .padding(.top, ChimpSpacing.ml)
                .accessibilityHidden(true)
            }
        }
        .padding(ChimpSpacing.header(for: screenInsets))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Color(.chimpHeader)
                .overlay { ChimpPattern() }
                .ignoresSafeArea(edges: .top)
        }
    }
}

/// Bouton réglages (roue dentée) de l'en-tête : rond de 42 pt, zone tactile de 44 pt.
struct ChimpHeaderSettingsButton: View {
    let action: () -> Void

    var body: some View {
        ChimpHeaderRoundButton(size: ChimpSize.headerGearButton, action: action) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.chimpOnHeaderPrimary)
        }
        .accessibilityLabel(Text("Settings"))
    }
}

/// Bouton rond de l'en-tête (retour, réglages) : visuel de 40–42 pt, zone tactile de 44 pt.
struct ChimpHeaderRoundButton<Content: View>: View {
    let size: CGFloat
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            content
                .frame(width: size, height: size)
                .background(Circle().fill(Color(.chimpHeaderButtonFill)))
        }
        .buttonStyle(ChimpPressableStyle())
        .expandedTouchTarget(visualSize: size)
    }
}

/// Appui sur un élément sans ombre : il pâlit (non spécifié par la maquette).
struct ChimpPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? ChimpOpacity.pressed : 1)
    }
}

/// Chevron « retour » de la maquette : tracé `M10 2 L2 10 L10 18` dans un cadre de 12 × 20.
struct ChimpBackChevron: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 12, sy = rect.height / 20
        var path = Path()
        path.move(to: CGPoint(x: 10 * sx, y: 2 * sy))
        path.addLine(to: CGPoint(x: 2 * sx, y: 10 * sy))
        path.addLine(to: CGPoint(x: 10 * sx, y: 18 * sy))
        return path
    }
}

private struct ChimpHeaderPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "How much, from where", step: 2, steps: 3, onBack: {})
            Spacer()
        }
        .background(Color(.chimpBackground))
    }
}

#Preview("Étapes") {
    ChimpHeaderPreview()
}

#Preview("Étapes · sombre") {
    ChimpHeaderPreview()
        .preferredColorScheme(.dark)
}

#Preview("Sous-titre et réglages") {
    VStack(spacing: 0) {
        ChimpHeader(title: "Léo's account", subtitle: "2 cards · Main + 2 wallets", onSettings: {})
        Spacer()
    }
    .background(Color(.chimpBackground))
}
