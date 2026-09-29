import SwiftUI

/// Choix de la couleur d'une carte (A5, G1b) : une pastille de 52 pt par couleur, la couleur choisie
/// entourée d'un anneau jaune de 4 pt.
struct ChimpColorSwatchPicker: View {
    @Binding var selection: ChimpCardColor

    var body: some View {
        HStack(spacing: ChimpSpacing.m) {
            ForEach(ChimpCardColor.allCases) { color in
                let isSelected = color == selection
                let shape = RoundedRectangle(cornerRadius: ChimpRadius.control - 2)
                Button {
                    selection = color
                } label: {
                    shape
                        .fill(color.fill)
                        .overlay { shape.strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
                        .frame(width: ChimpSize.colorSwatch, height: ChimpSize.colorSwatch)
                        .padding(ChimpBorder.thick)
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: ChimpRadius.control + 2)
                                    .strokeBorder(Color(.chimpAccent), lineWidth: ChimpBorder.thick)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(color.accessibilityName))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

extension ChimpCardColor {
    /// Nom lu par VoiceOver.
    var accessibilityName: LocalizedStringKey {
        switch self {
        case .jungle: "Brown"
        case .banana: "Yellow"
        case .leaf: "Green"
        case .pink: "Pink"
        }
    }
}

#Preview {
    @Previewable @State var color = ChimpCardColor.jungle
    ChimpColorSwatchPicker(selection: $color)
        .padding()
        .background(Color(.chimpBackground))
}
