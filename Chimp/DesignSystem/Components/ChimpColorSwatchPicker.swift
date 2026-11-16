import SwiftUI

/// Choix de l'allure d'une carte (A5, G1b) : une pastille de 52 pt par couleur, celle qui est choisie
/// entourée d'un anneau jaune de 4 pt.
///
/// Quand la carte a un dessin (son NFT), une pastille de plus le propose **à la place** de la couleur (demande de
/// Barth du 2026-11-16). La couleur reste choisie en dessous : repasser sur une couleur la retrouve telle quelle.
struct ChimpColorSwatchPicker: View {
    @Binding var selection: ChimpCardColor
    /// Le dessin imprimé de la carte, s'il y en a un : sans lui, le choix se limite aux couleurs.
    var design: CardArt?
    /// `true` : c'est le dessin qui est choisi. `nil` (le défaut) : l'écran ne propose pas ce choix.
    var designSelection: Binding<Bool>?

    /// Le dessin est choisi, et il est bien là.
    private var showsDesign: Bool { design != nil && designSelection?.wrappedValue == true }

    var body: some View {
        HStack(spacing: ChimpSpacing.m) {
            ForEach(ChimpCardColor.allCases) { color in
                let isSelected = color == selection && !showsDesign
                let shape = RoundedRectangle(cornerRadius: ChimpRadius.control - 2)
                Button {
                    selection = color
                    designSelection?.wrappedValue = false
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
            if let design, let designSelection {
                designSwatch(design, isSelected: showsDesign, selection: designSelection)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .sensoryFeedback(.selection, trigger: designSelection?.wrappedValue ?? false)
    }
}

private extension ChimpColorSwatchPicker {
    /// La pastille du dessin : le dessin lui-même, rogné dans la pastille, pour qu'on voie ce qu'on choisit.
    @ViewBuilder
    func designSwatch(_ design: CardArt, isSelected: Bool, selection: Binding<Bool>) -> some View {
        let shape = RoundedRectangle(cornerRadius: ChimpRadius.control - 2)
        Button {
            selection.wrappedValue = true
        } label: {
            Image(uiImage: design.image)
                .resizable()
                .scaledToFill()
                .frame(width: ChimpSize.colorSwatch, height: ChimpSize.colorSwatch)
                .clipShape(shape)
                .overlay { shape.strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
                .padding(ChimpBorder.thick)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: ChimpRadius.control + 2)
                            .strokeBorder(Color(.chimpAccent), lineWidth: ChimpBorder.thick)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(design.design.map { Text("\($0) design") } ?? Text("Card design"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
