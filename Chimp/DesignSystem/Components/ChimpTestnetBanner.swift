import SwiftUI

/// Avertissement « testnet » de Chimp Test, publiée sur l'App Store en testnet (demande de Barth du 2026-10-21) : le même
/// texte dans la fenêtre du premier lancement et sur l'écran Recevoir.
enum TestnetNotice {
    static let title: LocalizedStringKey = "Test money only"
    static let message: LocalizedStringKey =
        "This app runs on the Stellar testnet. Money here has no value. Never send real money to this wallet: it would be lost."
    static let accept: LocalizedStringKey = "I understand"
}

/// Bandeau permanent « TESTNET » du Wallet : jaune, contour noir, jamais refermable.
struct ChimpTestnetBanner: View {
    var body: some View {
        HStack(spacing: ChimpSpacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .heavy))
                .accessibilityHidden(true)
            Text("TESTNET")
                .chimpFont(.labelWide)
            Text("Test money, no real value")
                .chimpFont(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.chimpOnAccent)
        .padding(.vertical, ChimpSpacing.s + ChimpBorder.regular)
        .padding(.horizontal, ChimpSpacing.ml + ChimpBorder.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.key), fill: Color(.chimpAccent))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: ChimpSpacing.l) {
        ChimpTestnetBanner()
        ChimpNoticeBanner(text: TestnetNotice.message, marker: .error)
    }
    .padding(ChimpSpacing.screenMargin)
    .frame(maxHeight: .infinity)
    .background(Color(.chimpBackground))
}
