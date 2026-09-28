import SwiftUI

/// Pilule d'adresse (D1) : l'adresse raccourcie en Space Mono et une pastille jaune « Copy »,
/// qui devient « Copied! » avec une coche. Toute la pilule est le bouton.
///
/// La pilule n'affiche que l'adresse raccourcie : c'est à l'appelant de copier l'adresse **complète**.
struct ChimpAddressPill: View {
    /// Adresse raccourcie, déjà formatée (« CAIO2SJ6…VOX2 »).
    let address: String
    let isCopied: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ChimpSpacing.sm) {
                Text(verbatim: address)
                    .chimpFont(.address)
                    .foregroundStyle(.chimpTextPrimary)
                    .lineLimit(1)
                    .fixedSize()
                copyBadge
            }
            .padding(.vertical, 5 + ChimpBorder.regular)
            .padding(.leading, 15 + ChimpBorder.regular)
            .padding(.trailing, 5 + ChimpBorder.regular)
            .cartoonSurface(Capsule(), fill: Color(.chimpSurface))
            .contentShape(Capsule())
        }
        .buttonStyle(ChimpPressableStyle())
        .animation(.snappy(duration: ChimpMotion.Copied.transition), value: isCopied)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isCopied ? Text("Address copied") : Text("Copy address"))
        .accessibilityValue(Text(verbatim: address))
    }

    private var copyBadge: some View {
        HStack(spacing: ChimpSpacing.xxs) {
            if isCopied {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .black))
                    .transition(.scale.combined(with: .opacity))
            }
            Text(isCopied ? "Copied!" : "Copy")
                .chimpFont(.tile)
                .contentTransition(.opacity)
        }
        .foregroundStyle(.chimpOnAccent)
        .padding(.top, 6 + ChimpBorder.thin)
        .padding(.bottom, ChimpSpacing.xxs + ChimpBorder.thin)
        .padding(.horizontal, 11 + ChimpBorder.thin)
        .background(Capsule().fill(Color(.chimpAccent)))
        .overlay(Capsule().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin))
    }
}

private struct ChimpAddressPillPreview: View {
    @State private var isCopied = false

    var body: some View {
        VStack(spacing: ChimpSpacing.xl) {
            ChimpAddressPill(address: "CAIO2SJ6…AZVOX2", isCopied: isCopied) {
                isCopied.toggle()
            }
            ChimpAddressPill(address: "CAIO2SJ6…AZVOX2", isCopied: true) {}
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.chimpBackground))
    }
}

#Preview("Light") {
    ChimpAddressPillPreview()
}

#Preview("Dark") {
    ChimpAddressPillPreview()
        .preferredColorScheme(.dark)
}
