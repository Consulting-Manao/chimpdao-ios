import SwiftUI

/// A2 · Reading the card : écran plein pendant que la feuille NFC d'iOS lit la carte, puis pendant la vérification
/// en ligne. États ajoutés à la maquette (DESIGN_NOTES §11) : attente d'un nouveau scan, vérification, problème
/// (message de Chimpy + détails techniques). Rien n'est signé ni payé.
struct CardReadingView: View {
    let state: OnboardingModel.ReadingState
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .chimpFont(.displayL)
                .multilineTextAlignment(.center)
                .foregroundStyle(.chimpOnHeaderPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ChimpSpacing.xxxl)
                .padding(.horizontal, 30)
                .accessibilityAddTraits(.isHeader)
                .animation(nil, value: state)

            ChimpNFCRings(config: ChimpMotion.Ring.fullScreen, size: 290) {
                Image(.tileHead)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150)
                    .shadow(color: .black.opacity(0.3), radius: 0, x: 5, y: 6)
                    .accessibilityHidden(true)
            }
            .frame(maxHeight: .infinity)
            .layoutPriority(-1)

            if case .failed(let problem) = state {
                VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                    ChimpySays(text: Self.message(for: problem.kind), pose: .head)
                    ChimpTechnicalDetails(details: problem.technicalDetails, onDarkBackground: true)
                }
                .padding(.horizontal, ChimpSpacing.fullScreenMargin)
                .padding(.bottom, ChimpSpacing.m)
            }

            if showsScanButton {
                ChimpButton(scanTitle, size: .large, action: onScan)
                    .padding(.horizontal, ChimpSpacing.fullScreenMargin)
                    .padding(.bottom, ChimpSpacing.lg)
            }

            ChimpFullScreenBanner(text: "Nothing is moved yet. I'm just saying hello to the card.")
        }
        .chimpFullScreenBackground(patternOpacity: 0.12)
        .blocksSwipeBack(state == .scanning || state == .checking)
    }

    private var title: LocalizedStringKey {
        state == .checking ? "Checking your card…" : "Hold the card to the top of your phone"
    }

    private var showsScanButton: Bool {
        switch state {
        case .idle: true
        case .failed(let problem): problem.kind != .nfcUnavailable
        case .scanning, .checking: false
        }
    }

    private var scanTitle: LocalizedStringKey {
        if case .failed = state { return "Try again" }
        return "Scan my card"
    }

    /// Messages de Chimpy (textes proposés pour les états absents de la maquette, DESIGN_NOTES §11.2).
    static func message(for kind: OnboardingProblem.Kind) -> LocalizedStringKey {
        switch kind {
        case .nfcUnavailable: "This iPhone can't read cards. You'll need an iPhone that can tap cards."
        case .timeout: "The card took too long to answer. Let's try again."
        case .cardMoved: "The card moved away too soon. Hold it still at the top of your phone."
        case .multipleCards: "I see more than one card. Tap just one."
        case .couldntCheck: "I read the card but couldn't check it online. Check your connection and tap again."
        case .readFailed: "Something went wrong reading the card. Let's try again."
        }
    }
}

#Preview("Scanning") {
    CardReadingView(state: .scanning, onScan: {})
}

#Preview("Problem") {
    CardReadingView(state: .failed(.init(kind: .couldntCheck, technicalDetails: "Stellar RPC error: timeout")), onScan: {})
}
