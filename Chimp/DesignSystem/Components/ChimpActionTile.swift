import SwiftUI

/// Tuile d'action carrée du Wallet (Send, Receive, Move, Swap) : symbole + libellé.
/// La première action (Send) est jaune (`isPrimary`).
struct ChimpActionTile: View {
    let title: LocalizedStringKey
    /// Nom d'un SF Symbol (ex. `arrow.up.right`).
    let systemImage: String
    var isPrimary = false
    let action: () -> Void

    @ScaledMetric(relativeTo: .title3) private var glyphSize = ChimpSize.actionTileGlyph

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: glyphSize, weight: .heavy))
                    .frame(height: glyphSize)
                    .accessibilityHidden(true)
                Text(title)
                    .chimpFont(.tile)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isPrimary ? Color(.chimpOnAccent) : Color(.chimpTextPrimary))
            .padding(.top, 12 + ChimpBorder.regular)
            .padding(.bottom, ChimpSpacing.sm + ChimpBorder.regular)
            .padding(.horizontal, ChimpSpacing.xxs)
            .frame(maxWidth: .infinity, minHeight: ChimpSize.minimumTouchTarget)
        }
        .buttonStyle(ChimpSurfaceButtonStyle(
            shape: RoundedRectangle(cornerRadius: ChimpRadius.control),
            fill: isPrimary ? Color(.chimpAccent) : Color(.chimpSurface),
            shadow: .tile
        ))
        // Quatre tuiles tiennent sur une ligne : au-delà de XXXL, le texte ne grandit plus.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

private struct ChimpActionTilePreview: View {
    var body: some View {
        HStack(spacing: ChimpSize.keypadSpacing) {
            ChimpActionTile(title: "Send", systemImage: "arrow.up.right", isPrimary: true) {}
            ChimpActionTile(title: "Receive", systemImage: "arrow.down.left") {}
            ChimpActionTile(title: "Move", systemImage: "arrow.up.arrow.down") {}.disabled(true)
            ChimpActionTile(title: "Swap", systemImage: "arrow.left.arrow.right") {}
        }
        .padding(ChimpSpacing.screenMargin)
        .frame(maxHeight: .infinity)
        .background(Color(.chimpBackground))
    }
}

#Preview("Light") {
    ChimpActionTilePreview()
}

#Preview("Dark") {
    ChimpActionTilePreview()
        .preferredColorScheme(.dark)
}
