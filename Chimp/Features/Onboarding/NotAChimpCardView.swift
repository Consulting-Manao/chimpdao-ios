import SwiftUI

/// H3 · Not a real Chimp card : carte non enregistrée par ChimpDAO, carte sans clé, ou puce inconnue.
/// « Where do I get a real one? » est masqué tant qu'il n'a pas de destination (comme le lien d'A1).
struct NotAChimpCardView: View {
    let onTryAnother: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer(minLength: ChimpSpacing.l)
                Image(.chimpyStink)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 230)
                    .layoutPriority(-1)
                    .accessibilityHidden(true)
                Text("Hmm, this card\nsmells fake")
                    .chimpFont(.displayL)
                    .foregroundStyle(.chimpOnHeaderPrimary)
                    .padding(.top, ChimpSpacing.lg)
                    .accessibilityAddTraits(.isHeader)
                Text("Real Chimp cards are switched on at our workshop before they ship. This one wasn't, so it can't hold money.")
                    .chimpFont(.bodyL)
                    .lineSpacing(6)
                    .foregroundStyle(.chimpOnHeaderSecondary)
                    .padding(.top, ChimpSpacing.m)
                Spacer(minLength: ChimpSpacing.l)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 28)
            .frame(maxHeight: .infinity)

            ChimpButton("Try another card", size: .regular, action: onTryAnother)
                .padding(.horizontal, ChimpSpacing.fullScreenMargin)
                .padding(.bottom, ChimpSpacing.xl)
        }
        .chimpFullScreenBackground(patternOpacity: 0.12)
    }
}

#Preview {
    NotAChimpCardView(onTryAnother: {})
}
