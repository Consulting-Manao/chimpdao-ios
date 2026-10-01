import SwiftUI

/// Carte « tiroir » (Main dans B1, puis les wallets des cartes) : icône, libellé, montant,
/// détail « prêt · en épargne », chevron. Toute la carte est un bouton.
struct ChimpDrawerCard: View {
    /// Libellé en majuscules (« Main »).
    let label: LocalizedStringKey
    /// Montant déjà formaté (« $1,320.00 »).
    let amount: String
    /// Part disponible, déjà formatée (« $820 »). Masquée si `nil`.
    var ready: String?
    /// Part en épargne (Grow), déjà formatée (« $500 »). Masquée si `nil`.
    var growing: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ChimpSpacing.ml) {
                Image(.tileLogo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: ChimpSize.drawerIconLogo)
                    .frame(width: ChimpSize.drawerIcon, height: ChimpSize.drawerIcon)
                    .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.drawerIcon), fill: Color(.chimpAccent))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .chimpFont(.label)
                        .textCase(.uppercase)
                        .foregroundStyle(.chimpTextSecondary)
                    Text(verbatim: amount)
                        .chimpFont(.amountM)
                        .chimpRollingNumber(amount)
                        .foregroundStyle(.chimpTextPrimary)
                    detail
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.chimpTextSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 15 + ChimpBorder.regular)
            .padding(.horizontal, ChimpSpacing.l + ChimpBorder.regular)
        }
        .buttonStyle(ChimpSurfaceButtonStyle(
            shape: RoundedRectangle(cornerRadius: ChimpRadius.panel),
            fill: Color(.chimpSurface),
            shadow: .card
        ))
        .accessibilityElement(children: .combine)
    }

    /// Une seule ligne de texte, qui revient à la ligne naturellement aux grandes tailles.
    @ViewBuilder
    private var detail: some View {
        if let text = detailText {
            text.chimpFont(.captionStrong)
        }
    }

    private var detailText: Text? {
        let readyText = ready.map { Text("\($0) ready").foregroundStyle(.chimpTextSecondary) }
        let growingText = growing.map { Text("\($0) growing").foregroundStyle(.chimpPositive) }
        switch (readyText, growingText) {
        case let (ready?, growing?):
            return ready + Text(verbatim: " · ").foregroundStyle(.chimpTextSecondary) + growing
        case let (ready?, nil):
            return ready
        case let (nil, growing?):
            return growing
        case (nil, nil):
            return nil
        }
    }
}

private struct ChimpDrawerCardPreview: View {
    var body: some View {
        VStack(spacing: ChimpSpacing.xl) {
            ChimpDrawerCard(label: "Main", amount: "$1,320.00", ready: "$820", growing: "$500") {}
            ChimpDrawerCard(label: "Main", amount: "$1,320.00", ready: "$820") {}
            ChimpDrawerCard(label: "Main", amount: "$1,320.00") {}
        }
        .padding(ChimpSpacing.screenMargin)
        .frame(maxHeight: .infinity)
        .background(Color(.chimpBackground))
    }
}

#Preview("Light") {
    ChimpDrawerCardPreview()
}

#Preview("Dark") {
    ChimpDrawerCardPreview()
        .preferredColorScheme(.dark)
}
