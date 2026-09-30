import SwiftUI

/// Boîte groupée des réglages (I2) : fond `chimpSurface`, contour 3, rayon 18, lignes séparées par un trait
/// `chimpSurfaceSecondary` de 2 pt. Comme `ChimpGroupedList`, mais chaque ligne est une vue libre (interrupteur,
/// sélecteur à segments, ligne avec chevron).
struct ChimpGroupedBox<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.element.id) { index, subview in
                    if index > 0 {
                        Rectangle()
                            .fill(Color(.chimpSurfaceSecondary))
                            .frame(height: ChimpBorder.thin)
                            .accessibilityHidden(true)
                    }
                    subview
                }
            }
        }
        .padding(ChimpBorder.regular)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))
    }
}

/// Ligne cliquable d'une `ChimpGroupedBox` : titre, valeur facultative, chevron « > » (maquette I2 : « Currency USD $ > »).
struct ChimpSettingsRow: View {
    let title: LocalizedStringKey
    var value: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ChimpSpacing.sm) {
                Text(title)
                    .chimpFont(.rowTitle)
                    .foregroundStyle(.chimpTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let value {
                    Text(verbatim: value)
                        .chimpFont(.captionS)
                        .foregroundStyle(.chimpTextSecondary)
                        .multilineTextAlignment(.trailing)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.chimpTextSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 15)
            .frame(minHeight: ChimpSize.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChimpPressableStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Ligne d'une `ChimpGroupedBox` avec un contrôle à droite (sélecteur à segments, interrupteur). Si le contrôle ne tient
/// pas à côté du titre (petit écran, grands textes), il passe sous le titre.
struct ChimpSettingsControlRow<Control: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let control: Control

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ChimpSpacing.sm) {
                titleText
                    .frame(maxWidth: .infinity, alignment: .leading)
                control
            }
            VStack(alignment: .leading, spacing: ChimpSpacing.s) {
                titleText
                control
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, ChimpSpacing.xs)
        .padding(.horizontal, 15)
        .frame(minHeight: ChimpSize.minimumTouchTarget)
    }

    private var titleText: some View {
        Text(title)
            .chimpFont(.rowTitle)
            .foregroundStyle(.chimpTextPrimary)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }
}

/// Un segment de `ChimpSegmentedPicker`.
struct ChimpSegment<Value: Hashable>: Identifiable {
    let value: Value
    let title: LocalizedStringKey
    /// Titre lu par VoiceOver, s'il doit être plus clair que le titre affiché (« Auto » → « Same as my iPhone »).
    var accessibilityTitle: LocalizedStringKey?
    /// Segment grisé, qu'on ne peut pas choisir (Mainnet).
    var isEnabled = true
    /// Segment pas encore prêt : un petit cadenas après le titre, et ce texte lu par VoiceOver (« Coming soon »). Pas
    /// d'étiquette écrite : elle doublait la hauteur de la ligne (retour de Barth du 2026-09-30).
    var lockedHint: LocalizedStringKey?

    var id: Value { value }
}

/// Sélecteur à segments de la maquette (I2 « Look », « Network ») : fond `chimpSurfaceSecondary`, contour 2, rayon 11 ;
/// segment choisi jaune banane avec son contour, les autres en texte secondaire. Un toucher sur un segment grisé ne change
/// rien, mais prévient `onDisabledTap` (bulle de Chimpy).
struct ChimpSegmentedPicker<Value: Hashable>: View {
    let segments: [ChimpSegment<Value>]
    @Binding var selection: Value
    var onDisabledTap: ((Value) -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments) { segment in
                Button {
                    if segment.isEnabled {
                        selection = segment.value
                    } else {
                        onDisabledTap?(segment.value)
                    }
                } label: {
                    label(segment)
                }
                .buttonStyle(ChimpPressableStyle())
                .accessibilityLabel(Text(segment.accessibilityTitle ?? segment.title))
                .accessibilityValue(segment.lockedHint.map { Text($0) } ?? Text(verbatim: ""))
                .accessibilityAddTraits(segment.value == selection ? .isSelected : [])
            }
        }
        // Largeur idéale imposée : jamais de segment tronqué, `ChimpSettingsControlRow` passe alors sous le titre.
        .fixedSize()
        .padding(2 + ChimpBorder.thin)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color(.chimpSurfaceSecondary)))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin))
    }

    private func label(_ segment: ChimpSegment<Value>) -> some View {
        let isSelected = segment.value == selection
        let shape = RoundedRectangle(cornerRadius: ChimpRadius.segment)
        return HStack(spacing: 3) {
            Text(segment.title)
                .chimpFont(.segment)
            if segment.lockedHint != nil {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .accessibilityHidden(true)
            }
        }
        .lineLimit(1)
        .foregroundStyle(isSelected ? Color(.chimpOnAccent) : Color(.chimpTextSecondary))
        .opacity(segment.isEnabled ? 1 : ChimpOpacity.disabled)
        .padding(.vertical, 4 + ChimpBorder.thin)
        .padding(.horizontal, 9 + ChimpBorder.thin)
        .frame(maxHeight: .infinity)
        .background(shape.fill(isSelected ? Color(.chimpAccent) : Color.clear))
        .overlay(shape.strokeBorder(isSelected ? Color(.chimpOutline) : Color.clear, lineWidth: ChimpBorder.thin))
        .frame(minHeight: 32)
        .contentShape(shape)
    }
}

#Preview {
    @Previewable @State var look = "auto"
    @Previewable @State var network = "testnet"
    VStack(spacing: ChimpSpacing.l) {
        ChimpGroupedBox {
            ChimpSettingsRow(title: "Currency", value: "USD $") {}
            ChimpSettingsControlRow(title: "Look") {
                ChimpSegmentedPicker(segments: [
                    ChimpSegment(value: "auto", title: "Auto"),
                    ChimpSegment(value: "light", title: "Yellow banana"),
                    ChimpSegment(value: "dark", title: "Jungle night"),
                ], selection: $look)
            }
        }
        ChimpGroupedBox {
            ChimpSettingsControlRow(title: "Network") {
                ChimpSegmentedPicker(segments: [
                    ChimpSegment(value: "testnet", title: "Testnet"),
                    ChimpSegment(value: "mainnet", title: "Mainnet", isEnabled: false, lockedHint: "Coming soon"),
                ], selection: $network)
            }
        }
    }
    .padding(ChimpSpacing.screenMargin)
    .frame(maxHeight: .infinity)
    .background(Color(.chimpBackground))
}

/// Ligne à choix unique d'une `ChimpGroupedBox` (I3 « Show amounts in ») : pastille carrée (jaune si choisie), titre,
/// rond de sélection.
struct ChimpChoiceListRow: View {
    let badge: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ChimpSpacing.sm) {
                Text(verbatim: badge)
                    .chimpFont(Self.badgeStyle(badge))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Color(.chimpOnAccent))
                    .frame(width: 34 - 2 * ChimpBorder.thin, height: 34 - 2 * ChimpBorder.thin)
                    .padding(ChimpBorder.thin)
                    .background(RoundedRectangle(cornerRadius: 11).fill(isSelected ? Color(.chimpAccent) : Color(.chimpSurfaceSecondary)))
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin))
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .chimpFont(.optionTitle)
                    .foregroundStyle(.chimpTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ChimpRadio(isSelected: isSelected)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 13)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChimpPressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Luckiest Guy 14 pour des lettres (« XLM »), comme la maquette. Un symbole seul y est plus petit que des
    /// capitales : « $ » passe à 18 pt, et « € », « £ », « ¥ » (dessinés minuscules dans Luckiest Guy) en Nunito 900.
    static func badgeStyle(_ badge: String) -> ChimpTextStyle {
        guard badge.count == 1 else { return .buttonSmall }
        return badge == "$" ? .displayS : .lead
    }
}

/// Rond de sélection : vide, ou plein avec un anneau intérieur jaune (maquette : `inset 0 0 0 4px #FFD11E`).
struct ChimpRadio: View {
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(isSelected ? Color(.chimpOutline) : .clear)
            .padding(isSelected ? ChimpBorder.regular + 4 : 0)
            .background { if isSelected { Circle().fill(Color(.chimpAccent)) } }
            .overlay { Circle().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
            .frame(width: ChimpSize.radio, height: ChimpSize.radio)
            .accessibilityHidden(true)
    }
}

/// Interrupteur de la maquette (I2 « Face ID to open the app ») : 44 × 26, contour 3 ; vert feuille quand il est mis,
/// `chimpSurfaceSecondary` sinon ; rond blanc de 16 pt au contour 2.
struct ChimpToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: ChimpSpacing.sm) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                Capsule()
                    .fill(configuration.isOn ? Color(.chimpCardLeaf) : Color(.chimpSurfaceSecondary))
                    .overlay(Capsule().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular))
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(Color.white)
                            .overlay(Circle().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin))
                            .frame(width: 16, height: 16)
                            .padding(.horizontal, ChimpBorder.regular + 2)
                    }
                    .frame(width: 44, height: 26)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ChimpPressableStyle())
        .opacity(isEnabled ? 1 : ChimpOpacity.disabled)
        .accessibilityElement(children: .combine)
        .accessibilityValue(configuration.isOn ? Text("On") : Text("Off"))
        .accessibilityAddTraits(.isToggle)
    }
}
