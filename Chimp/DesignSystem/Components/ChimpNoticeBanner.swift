import SwiftUI

/// Repère affiché à gauche d'un bandeau.
enum ChimpNoticeMarker {
    /// Information neutre.
    case info
    /// Erreur (réseau, refus…).
    case error
    /// Réussite (vérifications passées).
    case success
    /// Pastille à la couleur d'une carte (« qui peut signer »).
    case card(ChimpCardColor)
}

/// Bandeau d'information (fond `chimpSurfaceSecondary`, contour 3, rayon 16) : repère, texte,
/// et une action facultative à droite (ex. : « Retry »).
struct ChimpNoticeBanner<Accessory: View>: View {
    let text: LocalizedStringKey
    var marker: ChimpNoticeMarker = .info
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: ChimpSpacing.sm) {
            markerView
                .accessibilityHidden(true)
            Text(text)
                .chimpFont(.caption)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .foregroundStyle(.chimpTextPrimary)
        .padding(.vertical, ChimpSpacing.sm + ChimpBorder.regular)
        .padding(.horizontal, 13 + ChimpBorder.regular)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.key), fill: Color(.chimpSurfaceSecondary))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var markerView: some View {
        switch marker {
        case .info:
            Image(systemName: "info.circle.fill")
                .fontWeight(.heavy)
                .foregroundStyle(.chimpTextSecondary)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .fontWeight(.heavy)
                .foregroundStyle(.chimpNegative)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .fontWeight(.heavy)
                .foregroundStyle(.chimpPositive)
        case .card(let color):
            RoundedRectangle(cornerRadius: 4)
                .fill(color.fill)
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin) }
                .frame(width: ChimpSize.signerSwatch, height: ChimpSize.signerSwatch)
        }
    }
}

extension ChimpNoticeBanner where Accessory == EmptyView {
    init(text: LocalizedStringKey, marker: ChimpNoticeMarker = .info) {
        self.init(text: text, marker: marker) { EmptyView() }
    }
}

private struct ChimpNoticeBannerPreview: View {
    var body: some View {
        VStack(spacing: ChimpSpacing.l) {
            ChimpNoticeBanner(text: "It's from Jungle's wallet, so only that card works.", marker: .card(.jungle))
            ChimpNoticeBanner(text: "Couldn't refresh. Balances from 10:42.", marker: .error) {
                ChimpPillButton("Retry") {}
            }
            ChimpNoticeBanner(text: "Looking is free. Moving money takes a tap.")
        }
        .padding(ChimpSpacing.screenMargin)
        .frame(maxHeight: .infinity)
        .background(Color(.chimpBackground))
    }
}

#Preview("Light") {
    ChimpNoticeBannerPreview()
}

#Preview("Dark") {
    ChimpNoticeBannerPreview()
        .preferredColorScheme(.dark)
}
