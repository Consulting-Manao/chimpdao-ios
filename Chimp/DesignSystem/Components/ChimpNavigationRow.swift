import SwiftUI

/// Ligne qui mène à un autre écran (« Add money from another chain > », D1) : fond `chimpSurface`,
/// contour 3, rayon 18, titre en Luckiest Guy, sous-titre, chevron. Sans ombre.
struct ChimpNavigationRow: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ChimpSpacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .chimpFont(.buttonSecondary)
                        .foregroundStyle(.chimpTextPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .chimpFont(.captionS)
                            .foregroundStyle(.chimpTextSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.chimpTextSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, ChimpSpacing.m + ChimpBorder.regular)
            .padding(.horizontal, 15 + ChimpBorder.regular)
            .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))
            .contentShape(RoundedRectangle(cornerRadius: ChimpRadius.control))
        }
        .buttonStyle(ChimpPressableStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Étiquette en majuscules (« TESTNET ») : pilule `chimpSurfaceSecondary`, contour 2, Space Mono.
/// Non dessinée dans la maquette (badge réseau validé le 2026-09-28).
struct ChimpTagBadge: View {
    let text: LocalizedStringKey
    var systemImage: String?

    var body: some View {
        HStack(spacing: ChimpSpacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .black))
                    .accessibilityHidden(true)
            }
            Text(text)
                .chimpFont(.label)
                .textCase(.uppercase)
        }
        .foregroundStyle(.chimpTextPrimary)
        .padding(.vertical, ChimpSpacing.xxs + ChimpBorder.thin)
        .padding(.horizontal, ChimpSpacing.sm + ChimpBorder.thin)
        .background(Capsule().fill(Color(.chimpSurfaceSecondary)))
        .overlay(Capsule().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: ChimpSpacing.xl) {
        ChimpTagBadge(text: "Testnet", systemImage: "exclamationmark.triangle.fill")
        ChimpNavigationRow(title: "Add money from another chain", subtitle: "See a live price from NEAR Intents") {}
    }
    .padding(ChimpSpacing.screenMargin)
    .frame(maxHeight: .infinity)
    .background(Color(.chimpBackground))
}
