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
                    ChimpHeaderBackButton(action: onBack)
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
        // Un écran apparaît (en avançant comme en revenant) : un froissement de feuillage (retour du 2026-10-02).
        .onAppear { ChimpSoundPlayer.shared.rustle() }
    }
}

/// Bouton retour de l'en-tête : le disque en bois et sa flèche en bambou (2026-10-02), sans fond, contour ni ombre.
/// Décalé de 6 pt vers la gauche pour paraître aligné sur le bord.
struct ChimpHeaderBackButton: View {
    let action: () -> Void

    var body: some View {
        ChimpHeaderImageButton(image: .headerBack, edge: .leading, action: action)
            .accessibilityLabel(Text("Back"))
    }
}

/// Bouton réglages de l'en-tête : la roue dentée en bois (2026-10-02), même traitement que le retour, décalée de 2 pt
/// vers la droite (6 pt la collaient au coin, retour de Barth).
struct ChimpHeaderSettingsButton: View {
    let action: () -> Void

    var body: some View {
        ChimpHeaderImageButton(image: .headerSettings, edge: .trailing, action: action)
            .accessibilityLabel(Text("Settings"))
    }
}

/// L'image est le bouton entier. Elle s'affiche à sa taille (40 pt de haut, `ChimpSize.headerButton`) et ne rétrécit
/// jamais, même avec un titre long ; zone tactile d'au moins 44 × 44 pt, sans changer la mise en page.
private struct ChimpHeaderImageButton: View {
    let image: ImageResource
    /// Bord de l'écran vers lequel l'image est décalée.
    let edge: HorizontalEdge
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(image)
                .fixedSize()
                .frame(minWidth: ChimpSize.minimumTouchTarget, minHeight: ChimpSize.minimumTouchTarget)
                .contentShape(Rectangle())
                .padding(-touchInset)
        }
        .buttonStyle(ChimpPressableStyle())
        .fixedSize()
        .padding(edge == .leading ? .leading : .trailing, edge == .leading ? -ChimpSize.headerBackEdgeOffset : -ChimpSize.headerSettingsEdgeOffset)
    }

    /// Ce que la zone tactile ajoute autour de l'image, retiré de la mise en page (comme `expandedTouchTarget`).
    private var touchInset: CGFloat { max(0, (ChimpSize.minimumTouchTarget - ChimpSize.headerButton) / 2) }
}

/// Appui sur un élément sans ombre : il pâlit (non spécifié par la maquette).
struct ChimpPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? ChimpOpacity.pressed : 1)
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
