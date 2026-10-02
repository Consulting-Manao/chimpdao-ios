import SwiftUI

/// A2 · Reading the card : écran plein pendant que la feuille NFC d'iOS lit la carte, puis pendant la vérification
/// en ligne. États ajoutés à la maquette (DESIGN_NOTES §11) : attente d'un nouveau scan, vérification, problème
/// (message de Chimpy + détails techniques). Rien n'est signé ni payé.
///
/// H2 · New phone (« Look who's back! ») : même écran, quand ce téléphone a déjà ouvert un compte fermé depuis par
/// « Disconnect this phone » (`isReturning`) : titre, phrase et bulle de Chimpy de la maquette.
struct CardReadingView: View {
    let state: OnboardingModel.ReadingState
    var isReturning = false
    /// « + Add an account » (I6) : un lien « Cancel » ramène aux réglages.
    var onCancel: (() -> Void)?
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

            if showsReturningText {
                Text("Tap any card from your account to open it on this phone.")
                    .chimpFont(.bodyL)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.chimpOnHeaderSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ChimpSpacing.sm)
                    .padding(.horizontal, 30)
            }

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
                    .padding(.bottom, onCancel == nil ? ChimpSpacing.lg : ChimpSpacing.xs)
            }

            if let onCancel {
                // « + Add an account » (I6) : « Cancel » à la place du bandeau (place comptée sur iPhone SE).
                Button(action: onCancel) {
                    Text("Cancel")
                        .chimpFont(.link)
                        .foregroundStyle(.chimpOnHeaderSecondary)
                        .frame(maxWidth: .infinity, minHeight: ChimpSize.minimumTouchTarget)
                }
                .buttonStyle(ChimpPressableStyle())
                .opacity(state == .checking || state == .scanning ? 0 : 1)
                .disabled(state == .checking || state == .scanning)
                .padding(.bottom, ChimpSpacing.l)
            } else if showsReturningText {
                ChimpySays(text: "Just once. After that, peek at your bananas anytime, no card.", pose: .wave)
                    .padding(.horizontal, ChimpSpacing.fullScreenMargin)
                    .padding(.bottom, ChimpSpacing.xl)
            } else {
                ChimpFullScreenBanner(text: "Nothing is moved yet. I'm just saying hello to the card.")
            }
        }
        .chimpFullScreenBackground(patternOpacity: 0.12)
        .blocksSwipeBack(state == .scanning || state == .checking)
    }

    private var title: LocalizedStringKey {
        if state == .checking { return "Checking your card…" }
        return isReturning ? "Look who's back!" : "Hold the card to the top of your phone"
    }

    /// Phrase et bulle d'H2, tant qu'aucun problème ne prend la place de la bulle.
    private var showsReturningText: Bool {
        guard isReturning else { return false }
        if case .failed = state { return false }
        return state != .checking
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
        case .wrongCard: "That's not the card you started with. Tap the same card."
        case .notInAnAccount: "This card isn't in an account yet. Tap a card that already has one."
        case .alreadyOpen: "That card belongs to the account you're in. Tap a card of the other account."
        }
    }
}

#Preview("Scanning") {
    CardReadingView(state: .scanning, onScan: {})
}

#Preview("H2 · New phone") {
    CardReadingView(state: .idle, isReturning: true, onScan: {})
}

#Preview("Problem") {
    CardReadingView(state: .failed(.init(kind: .couldntCheck, technicalDetails: "Stellar RPC error: timeout")), onScan: {})
}
