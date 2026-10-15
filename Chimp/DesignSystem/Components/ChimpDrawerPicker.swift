import SwiftUI

/// Icône d'un tiroir : le logo pour Main, une petite carte de sa couleur pour le wallet d'une carte.
enum ChimpDrawerIcon: Equatable {
    case main
    case card(ChimpCardColor)
}

/// Dessin de l'icône d'un tiroir, dans un cadre de la taille demandée.
struct ChimpDrawerIconView: View {
    let icon: ChimpDrawerIcon
    let size: CGSize
    var border: CGFloat = ChimpBorder.regular
    var cornerRadius: CGFloat = 7

    var body: some View {
        Group {
            switch icon {
            case .main:
                Image(.tileLogo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width)
            case .card(let color):
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(color.fill)
                    .overlay { RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color(.chimpOutline), lineWidth: border) }
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

/// Sélecteur de tiroir en haut d'un écran (« INTO Main account ▾ », D1 ; « FROM Main account $820 → $770 ▾ », C2) :
/// fond `chimpSurfaceSecondary`, contour 3, rayon 16. Sans action (un seul tiroir possible), la flèche disparaît
/// et la ligne n'est plus un bouton. Le solde (« avant → après ») est toujours sous le nom, sur une seule ligne.
struct ChimpDrawerPicker: View {
    /// Libellé court en majuscules (« Into », « From »).
    let label: LocalizedStringKey
    let icon: ChimpDrawerIcon
    /// Nom du tiroir (« Main account », « Jungle's wallet »).
    let title: String
    /// Solde actuel, déjà formaté (C2). Masqué si `nil`.
    var balance: String?
    /// Solde après l'opération, déjà formaté, affiché après une flèche (« → 695 USDC »).
    var balanceAfter: String?
    var accessibilityHint: LocalizedStringKey = "Choose where the money lands"
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { row(showsChevron: true) }
                .buttonStyle(ChimpPressableStyle())
                .accessibilityHint(Text(accessibilityHint))
        } else {
            row(showsChevron: false)
        }
    }

    private func row(showsChevron: Bool) -> some View {
        HStack(spacing: ChimpSpacing.sm) {
            Text(label)
                .chimpFont(.label)
                .textCase(.uppercase)
                .foregroundStyle(.chimpTextSecondary)
            ChimpDrawerIconView(
                icon: icon,
                size: icon == .main
                    ? CGSize(width: ChimpSize.drawerPickerIcon, height: ChimpSize.drawerPickerIcon)
                    : CGSize(width: ChimpSize.drawerPickerIcon, height: 15),
                border: ChimpBorder.thin,
                cornerRadius: 4
            )
            // Avec un solde : toujours deux lignes, le solde sur une seule (réduit s'il le faut). La hauteur ne change
            // donc jamais pendant la saisie du montant (retour du 2026-10-01 : la ligne passait de 1 à 3 lignes).
            VStack(alignment: .leading, spacing: 2) {
                titleText
                balanceText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.chimpTextPrimary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, ChimpSpacing.sm + ChimpBorder.regular)
        .padding(.horizontal, 13 + ChimpBorder.regular)
        .frame(minHeight: ChimpSize.minimumTouchTarget)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.key), fill: Color(.chimpSurfaceSecondary))
        .contentShape(RoundedRectangle(cornerRadius: ChimpRadius.key))
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        Text(verbatim: title)
            .chimpFont(.rowTitle)
            .foregroundStyle(.chimpTextPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var balanceText: some View {
        if let balance {
            HStack(spacing: ChimpSpacing.xxs) {
                Text(verbatim: balance)
                    .foregroundStyle(.chimpTextSecondary)
                    .chimpRollingNumber(balance)
                if let balanceAfter {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.chimpTextSecondary)
                        .accessibilityLabel(Text("then"))
                    Text(verbatim: balanceAfter)
                        .foregroundStyle(.chimpTextPrimary)
                        .chimpRollingNumber(balanceAfter)
                }
            }
            .chimpFont(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }
}

/// Ligne de choix d'un tiroir dans une feuille (C3 « Where should it come from? », D1) :
/// icône du tiroir, nom, sous-titre, bouton radio.
struct ChimpDrawerOptionRow: View {
    let icon: ChimpDrawerIcon
    let title: String
    /// Solde (C3) ou règle de dépense (D1), déjà formaté. Masqué si `nil`.
    var subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        ChimpOptionRow(title: title, subtitle: subtitle, isSelected: isSelected, action: action) {
            ChimpDrawerIconView(
                icon: icon,
                size: icon == .main
                    ? CGSize(width: ChimpSize.drawerOptionIcon.width, height: ChimpSize.drawerOptionIcon.width)
                    : ChimpSize.drawerOptionIcon
            )
        }
    }
}

/// Ligne de choix dans une feuille (tiroir, actif…) : icône, titre, sous-titre, bouton radio.
/// La ligne choisie est jaune, avec une ombre.
struct ChimpOptionRow<Icon: View>: View {
    let title: String
    /// Ce que c'est, sous le titre (« Mexican government bonds, by Etherfuse », maquette E3p). Masqué si `nil`.
    var detail: String? = nil
    /// Sous-titre déjà formaté. Masqué si `nil`.
    var subtitle: String?
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ChimpRadius.control)
        Button(action: action) {
            HStack(spacing: ChimpSpacing.m) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title)
                        .chimpFont(.optionTitle)
                    if let detail {
                        Text(verbatim: detail)
                            .chimpFont(.captionS)
                            .fontWeight(.heavy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .chimpFont(.captionS)
                            .foregroundStyle(isSelected ? Color(.chimpOnAccent) : Color(.chimpTextSecondary))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                radio
            }
            .foregroundStyle(isSelected ? Color(.chimpOnAccent) : Color(.chimpTextPrimary))
            .padding(.vertical, 13 + ChimpBorder.regular)
            .padding(.horizontal, ChimpSpacing.ml + ChimpBorder.regular)
        }
        .buttonStyle(ChimpSurfaceButtonStyle(
            shape: shape,
            fill: isSelected ? Color(.chimpAccent) : Color(.chimpSurface),
            shadow: isSelected ? .tile : ChimpShadow(x: 0, y: 0)
        ))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Rond vide, ou rond plein avec un anneau intérieur jaune (maquette : `inset 0 0 0 4px #FFD11E`).
    private var radio: some View {
        Circle()
            .fill(isSelected ? Color(.chimpOutline) : .clear)
            .padding(isSelected ? ChimpBorder.regular + 4 : 0)
            .overlay { Circle().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
            .frame(width: ChimpSize.radio, height: ChimpSize.radio)
            .accessibilityHidden(true)
    }
}

private struct ChimpDrawerPickerPreview: View {
    @State private var selection = "main"

    var body: some View {
        VStack(spacing: ChimpSpacing.listGap) {
            ChimpDrawerPicker(label: "Into", icon: .main, title: "Main account") {}
            ChimpDrawerPicker(label: "Into", icon: .card(.jungle), title: "Jungle's wallet")
                .padding(.bottom, ChimpSpacing.xl)
            ChimpDrawerOptionRow(icon: .main, title: "Main account", subtitle: "$820", isSelected: selection == "main") {
                selection = "main"
            }
            ChimpDrawerOptionRow(icon: .card(.jungle), title: "Jungle's wallet", subtitle: "$62.50", isSelected: selection == "jungle") {
                selection = "jungle"
            }
            ChimpDrawerOptionRow(icon: .card(.banana), title: "Banana's wallet", subtitle: "$102.50", isSelected: selection == "banana") {
                selection = "banana"
            }
        }
        .padding(ChimpSpacing.screenMargin)
        .frame(maxHeight: .infinity)
        .background(Color(.chimpBackground))
    }
}

#Preview("Light") {
    ChimpDrawerPickerPreview()
}

#Preview("Dark") {
    ChimpDrawerPickerPreview()
        .preferredColorScheme(.dark)
}
