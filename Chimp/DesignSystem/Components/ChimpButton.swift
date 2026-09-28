import SwiftUI

/// Apparence d'un bouton.
enum ChimpButtonKind {
    /// Bouton principal : jaune, ombre dure (« Next », « Looks good »).
    case primary
    /// Bouton secondaire : fond `chimpSurface` (« No, stop », « My banana stash »).
    case secondary
    /// Bouton secondaire destructif : texte `chimpNegative` (« Disconnect this phone »).
    case destructive
    /// Bouton secondaire posé sur l'en-tête ou un écran plein (« Where do I get a real one? »).
    case onHeader
    /// Lien texte (« Cancel », « Skip »).
    case link
    /// Lien texte posé sur l'en-tête ou un écran plein (« I don't have a card yet »).
    case linkOnHeader
}

/// Taille d'un bouton.
enum ChimpButtonSize {
    /// Écrans d'accueil et d'onboarding (Luckiest Guy 18).
    case large
    /// Taille par défaut (principal : Luckiest Guy 17 ; secondaire : 15).
    case regular
    /// Boutons côte à côte, ex. Send / Move / Grow de B2 (Luckiest Guy 14, rayon 16, ombre 0 4).
    case compact
}

/// Bouton ChimpDAO, avec ses quatre états : normal, pressé, désactivé (`.disabled(true)`) et chargement.
///
/// En chargement, une roue de la couleur du texte remplace le libellé, le bouton garde sa taille
/// et ne réagit plus. Le bouton principal donne un léger retour haptique à l'appui.
struct ChimpButton: View {
    let title: LocalizedStringKey
    var kind: ChimpButtonKind = .primary
    var size: ChimpButtonSize = .regular
    /// Ajoute l'ombre dure à un bouton secondaire de taille normale (« My banana stash » dans F1).
    var raised = false
    var isLoading = false
    let action: () -> Void

    init(
        _ title: LocalizedStringKey,
        kind: ChimpButtonKind = .primary,
        size: ChimpButtonSize = .regular,
        raised: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.size = size
        self.raised = raised
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button {
            // VoiceOver peut activer un bouton même quand les touchers sont bloqués : on vérifie ici aussi.
            guard !isLoading else { return }
            action()
        } label: {
            Text(title)
        }
        .buttonStyle(ChimpButtonStyle(kind: kind, size: size, raised: raised, isLoading: isLoading))
        .allowsHitTesting(!isLoading)
        .accessibilityValue(isLoading ? String(localized: "Loading") : "")
    }
}

/// Style de bouton ChimpDAO. Utilisable directement avec `.buttonStyle(ChimpButtonStyle(...))`
/// pour un libellé personnalisé ; `ChimpButton` couvre le cas courant.
struct ChimpButtonStyle: ButtonStyle {
    var kind: ChimpButtonKind = .primary
    var size: ChimpButtonSize = .regular
    var raised = false
    var isLoading = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        ChimpButtonFace(
            kind: kind,
            size: size,
            raised: raised,
            isPressed: configuration.isPressed,
            isLoading: isLoading
        ) {
            configuration.label
        }
        .opacity(isEnabled ? 1 : ChimpOpacity.disabled)
        .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, isPressed in
            kind == .primary && isPressed
        }
    }
}

/// Dessin d'un bouton dans un état donné. Séparé du style pour que le catalogue
/// puisse montrer l'état « pressé » sans qu'on appuie dessus.
struct ChimpButtonFace<Label: View>: View {
    let kind: ChimpButtonKind
    let size: ChimpButtonSize
    var raised = false
    var isPressed = false
    var isLoading = false
    @ViewBuilder let label: Label

    var body: some View {
        if isLink {
            linkBody
        } else {
            filledBody
        }
    }

    // MARK: Boutons pleins

    private var filledBody: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let pressedOffset = isPressed ? (shadow?.y ?? 0) : 0
        return labelContent
            .padding(.vertical, verticalPadding + ChimpBorder.regular)
            .padding(.horizontal, ChimpSpacing.l)
            .frame(maxWidth: .infinity, minHeight: ChimpSize.minimumTouchTarget)
            .background { shape.fill(fill) }
            .overlay { shape.strokeBorder(outline, lineWidth: ChimpBorder.regular) }
            // Appui : le bouton descend sur son ombre, qui disparaît. Sans ombre : il pâlit.
            .offset(y: pressedOffset)
            .opacity(isPressed && shadow == nil ? ChimpOpacity.pressed : 1)
            .background {
                if let shadow {
                    shape.fill(Color(.chimpOutline)).offset(x: shadow.x, y: shadow.y)
                }
            }
            .contentShape(shape)
            .animation(.easeOut(duration: ChimpMotion.Press.duration), value: isPressed)
    }

    // MARK: Liens

    private var linkBody: some View {
        labelContent
            .padding(.vertical, ChimpSpacing.xxs)
            .frame(minWidth: ChimpSize.minimumTouchTarget, minHeight: ChimpSize.minimumTouchTarget)
            .contentShape(Rectangle())
            .opacity(isPressed ? ChimpOpacity.pressed : 1)
    }

    // MARK: Contenu commun

    private var labelContent: some View {
        label
            .chimpFont(textStyle)
            .multilineTextAlignment(.center)
            .foregroundStyle(textColor)
            .opacity(isLoading ? 0 : 1)
            .overlay {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(textColor)
                        .accessibilityHidden(true)
                }
            }
    }

    private var isLink: Bool {
        kind == .link || kind == .linkOnHeader
    }

    private var textStyle: ChimpTextStyle {
        switch (kind, size) {
        case (_, .compact): .buttonSmall
        case (.primary, .large): .buttonLarge
        case (.primary, .regular): .button
        default: .buttonSecondary
        }
    }

    private var verticalPadding: CGFloat {
        switch (kind, size) {
        case (.primary, .large): 16
        case (.primary, .regular): 15
        default: 13
        }
    }

    private var cornerRadius: CGFloat {
        size == .compact ? ChimpRadius.key : ChimpRadius.control
    }

    private var shadow: ChimpShadow? {
        switch (kind, size) {
        case (_, .compact): .raised
        case (.primary, _): .button
        case (.secondary, _) where raised: .button
        default: nil
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: Color(.chimpAccent)
        case .secondary, .destructive: Color(.chimpSurface)
        case .onHeader: Color(.chimpHeaderShade)
        case .link, .linkOnHeader: .clear
        }
    }

    private var outline: Color {
        kind == .onHeader ? Color(.chimpOnHeaderPrimary) : Color(.chimpOutline)
    }

    private var textColor: Color {
        switch kind {
        case .primary: Color(.chimpOnAccent)
        case .secondary: Color(.chimpTextPrimary)
        case .destructive: Color(.chimpNegative)
        case .onHeader: Color(.chimpOnHeaderPrimary)
        case .link: Color(.chimpTextSecondary)
        case .linkOnHeader: Color(.chimpOnHeaderSecondary)
        }
    }
}

private struct ChimpButtonPreview: View {
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(spacing: ChimpSpacing.l) {
                ChimpButton("Let's start", size: .large) {}
                ChimpButton("Looks good", isLoading: isLoading) { isLoading = true }
                ChimpButton("Looks good") {}.disabled(true)
                ChimpButton("No, stop", kind: .secondary) {}
                ChimpButton("My banana stash", kind: .secondary, raised: true) {}
                ChimpButton("Disconnect this phone", kind: .destructive) {}
                HStack(spacing: ChimpSpacing.sm) {
                    ChimpButton("Send", size: .compact) {}
                    ChimpButton("Move", kind: .secondary, size: .compact) {}
                    ChimpButton("Grow", kind: .secondary, size: .compact) {}
                }
                ChimpButton("Cancel", kind: .link) {}
                VStack(spacing: ChimpSpacing.m) {
                    ChimpButton("Where do I get a real one?", kind: .onHeader) {}
                    ChimpButton("I don't have a card yet", kind: .linkOnHeader) {}
                }
                .padding(ChimpSpacing.l)
                .background(Color(.chimpHeader))
            }
            .padding(ChimpSpacing.screenMargin)
        }
        .background(Color(.chimpBackground))
    }
}

#Preview("Light") {
    ChimpButtonPreview()
}

#Preview("Dark") {
    ChimpButtonPreview()
        .preferredColorScheme(.dark)
}
