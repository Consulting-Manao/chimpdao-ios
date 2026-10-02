import SwiftUI

/// A1 · Welcome : premier écran de l'app tant qu'aucun compte n'est ouvert sur ce téléphone.
/// « I don't have a card yet » est masqué tant qu'il n'a pas de destination (décision du 2026-09-29).
struct WelcomeView: View {
    let onStart: () -> Void
    /// Roue dentée du catalogue et du mode admin (Debug et Testing) ; `nil` en Release.
    var onDeveloper: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: ChimpSpacing.sm) {
                Image(.tileLogo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36)
                    .accessibilityHidden(true)
                Text(verbatim: "ChimpDAO")
                    .chimpFont(.brand)
                    .foregroundStyle(.chimpOnHeaderPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let onDeveloper {
                    ChimpHeaderSettingsButton(action: onDeveloper)
                }
            }
            .padding(.top, ChimpSpacing.s + ChimpSpacing.headerTopBreathing)
            .padding(.horizontal, ChimpSpacing.fullScreenMargin)

            (Text("Your wallet") + Text(verbatim: "\n") + Text("is a card.").foregroundColor(Color(.chimpAccent)))
                .chimpFont(.welcomeTitle)
                .foregroundStyle(.chimpOnHeaderPrimary)
                .lineSpacing(0)
                .shadow(color: Color(.chimpOutline), radius: 0, x: 3, y: 3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ChimpSpacing.xxxl)
                .padding(.horizontal, ChimpSpacing.fullScreenMargin)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: ChimpSpacing.lg) {
                Spacer(minLength: ChimpSpacing.l)
                ChimpSpeechBubble(text: "Hi, I'm Chimpy! Ready to swing into your jungle?")
                Image(.chimpyWave)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 330)
                    .chimpBob(duration: 4.5)
                    .layoutPriority(-1)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 34)
            .padding(.bottom, ChimpSpacing.xxs)
            .frame(maxWidth: .infinity)

            ChimpButton("Let's start", size: .large, action: onStart)
                .padding(.top, ChimpSpacing.l)
                .padding(.horizontal, ChimpSpacing.fullScreenMargin)
                .padding(.bottom, ChimpSpacing.l)
        }
        .chimpFullScreenBackground()
    }
}

#Preview {
    WelcomeView(onStart: {}, onDeveloper: {})
}
