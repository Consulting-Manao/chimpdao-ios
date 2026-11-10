import SwiftUI

/// Mode du pavé numérique.
enum ChimpKeypadMode {
    /// Code PIN : pas de touche décimale (un simple espace à sa place).
    case pin
    /// Montant : touche décimale, qui suit la langue du téléphone (« , » en français).
    case amount
}

/// Touche du pavé numérique.
enum ChimpKeypadKey: Hashable {
    case digit(Int)
    case decimal
    case delete
}

/// Pavé numérique (« Chimp Keypad ») : grille 3 × 4, touches de 52 pt de haut.
///
/// Le pavé ne fait qu'annoncer la touche appuyée : c'est l'écran qui décide quoi en faire.
/// Pour un montant, la conversion du texte saisi en montant on-chain devra être indépendante
/// de la langue du téléphone (voir ROADMAP, points ouverts, jalon 5).
struct ChimpKeypad: View {
    var mode: ChimpKeypadMode = .pin
    /// Touches moins hautes (environ 48 pt au lieu de 56), pour les petits écrans (iPhone SE).
    var isCompact = false
    /// Les dix chiffres dans l'ordre d'affichage : les neuf premiers sur la grille, le dernier à la place du 0.
    var digits = Self.standardDigits
    let onKey: (ChimpKeypadKey) -> Void

    static let standardDigits = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]

    /// Un ordre aléatoire des dix chiffres (générateur système, cryptographique sur iOS).
    static func shuffledDigits<Generator: RandomNumberGenerator>(using generator: inout Generator) -> [Int] {
        standardDigits.shuffled(using: &generator)
    }

    static func shuffledDigits() -> [Int] {
        var generator = SystemRandomNumberGenerator()
        return shuffledDigits(using: &generator)
    }

    @Environment(\.locale) private var locale

    private var decimalSeparator: String {
        locale.decimalSeparator ?? "."
    }

    var body: some View {
        Grid(horizontalSpacing: ChimpSize.keypadSpacing, verticalSpacing: ChimpSize.keypadSpacing) {
            ForEach(0..<3) { row in
                GridRow {
                    ForEach(1...3, id: \.self) { column in
                        digit(digits[row * 3 + column - 1])
                    }
                }
            }
            GridRow {
                switch mode {
                case .pin:
                    Color.clear
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                        .accessibilityHidden(true)
                case .amount:
                    ChimpKeyButton(accessibilityLabel: Text("Decimal separator"), isCompact: isCompact) {
                        onKey(.decimal)
                    } label: {
                        Text(verbatim: decimalSeparator)
                    }
                }
                digit(digits[9])
                ChimpKeyButton(accessibilityLabel: Text("Delete"), isCompact: isCompact) {
                    onKey(.delete)
                } label: {
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 22, weight: .heavy))
                }
            }
        }
    }

    private func digit(_ value: Int) -> some View {
        ChimpKeyButton(accessibilityLabel: Text(verbatim: "\(value)"), isCompact: isCompact) {
            onKey(.digit(value))
        } label: {
            Text(verbatim: "\(value)")
        }
    }
}

/// Une touche : fond `chimpSurface`, contour 3, rayon 16, Luckiest Guy 24. Pâlit à l'appui.
private struct ChimpKeyButton<Label: View>: View {
    let accessibilityLabel: Text
    var isCompact = false
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ChimpRadius.key)
        Button(action: action) {
            label
                .chimpFont(.key)
                .foregroundStyle(.chimpTextPrimary)
                .padding(.vertical, (isCompact ? ChimpSize.keyVerticalPaddingCompact : ChimpSize.keyVerticalPadding) + ChimpBorder.regular)
                .frame(maxWidth: .infinity, minHeight: ChimpSize.minimumTouchTarget)
                .cartoonSurface(shape, fill: Color(.chimpSurface))
                .contentShape(shape)
        }
        .buttonStyle(ChimpPressableStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ChimpKeypadPreview: View {
    @State private var typed = ""
    var mode: ChimpKeypadMode

    var body: some View {
        VStack(spacing: ChimpSpacing.xl) {
            Text(verbatim: typed.isEmpty ? "–" : typed).chimpFont(.amountL)
            ChimpKeypad(mode: mode) { key in
                switch key {
                case .digit(let value): typed.append(String(value))
                case .decimal: typed.append(",")
                case .delete: if !typed.isEmpty { typed.removeLast() }
                }
            }
        }
        .padding(ChimpSpacing.xxl)
        .frame(maxHeight: .infinity)
        .background(Color(.chimpBackground))
    }
}

#Preview("PIN") {
    ChimpKeypadPreview(mode: .pin)
}

#Preview("Montant · sombre") {
    ChimpKeypadPreview(mode: .amount)
        .preferredColorScheme(.dark)
}
