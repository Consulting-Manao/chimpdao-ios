import SwiftUI

/// A3 · New card — what now? Deux variantes :
/// - carte neuve (`enrolled`) : « Fresh card! », créer un compte ou (bientôt) en rejoindre un ;
/// - carte orpheline (`orphan`, retirée d'un compte) : « This card is yours », seulement créer un compte,
///   comme l'écran « orphanCard » du terminal (`LandingScreen.tsx`).
struct CardChoiceView: View {
    let choice: CardChoice
    let onStartNewAccount: () -> Void
    /// « Join an account I already have » (A8) ; `nil` : grisé, « Coming soon ».
    var onJoin: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: headerTitle, subtitle: headerSubtitle)
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.blockGap) {
                    ChimpCard(name: cardName, color: .jungle, number: number, amount: cardAmount, subtitle: cardSubtitle)
                        .frame(width: 220)
                        .rotationEffect(ChimpMotion.Bob.tiltedCardAngle)
                        .chimpBob(duration: 3.2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ChimpSpacing.sm)

                    Text("What should it do?")
                        .chimpFont(.sheetTitle)
                        .foregroundStyle(.chimpTextPrimary)
                        .padding(.top, ChimpSpacing.xs)
                        .accessibilityAddTraits(.isHeader)

                    ChimpChoiceCard(
                        title: "Start a new account",
                        detail: "This card becomes the first key of a brand-new account.",
                        isHighlighted: true,
                        action: onStartNewAccount
                    )
                    if case .fresh = choice.kind {
                        ChimpChoiceCard(
                            title: "Join an account I already have",
                            detail: "You'll tap one of that account's cards next, to let this one in.",
                            isAvailable: onJoin != nil
                        ) { onJoin?() }
                    }
                }
                .padding(.top, ChimpSpacing.xl)
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.bottom, ChimpSpacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)

            ChimpySays(text: chimpy, pose: choice.kind == .fresh ? .sniff : .crawl)
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.top, ChimpSpacing.ml)
                .padding(.bottom, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
    }

    private var number: String {
        choice.tokenID.map { String(format: "%04u", $0) } ?? "····"
    }

    private var cardName: String {
        String(localized: "Card N°\(number)")
    }

    private var headerTitle: LocalizedStringKey {
        if case .orphan = choice.kind { return "This card is yours" }
        return "Fresh card!"
    }

    private var headerSubtitle: LocalizedStringKey {
        switch choice.kind {
        case .fresh: choice.pocketIsEmpty == true ? "N°\(number) · never used" : "N°\(number)"
        case .orphan: "N°\(number) · no account yet"
        }
    }

    /// Montant seulement quand on sait la Pocket vide (« $0.00, empty ») ; sinon rien (prix du XLM : étape 5).
    private var cardAmount: String? {
        choice.pocketIsEmpty == true ? Decimal(0).formatted(.currency(code: "USD").presentation(.narrow)) : nil
    }

    private var cardSubtitle: LocalizedStringKey? {
        switch choice.pocketIsEmpty {
        case true: "empty"
        case false: "has money on it"
        case nil: nil
        }
    }

    private var chimpy: LocalizedStringKey {
        switch choice.kind {
        case .fresh: "Ooh, a fresh one. It still smells like banana."
        case .orphan: "No account yet. What's in its wallet is still on the card."
        }
    }
}

#Preview("Fresh") {
    CardChoiceView(choice: CardChoice(kind: .fresh, card: ChipKeyInfo(kind: .infineon2Go, publicKey: MockChipReader.secp256k1Key, pinActive: false),
                                      tokenID: 7, pocket: nil, pocketIsEmpty: true), onStartNewAccount: {})
}

#Preview("Orphan") {
    CardChoiceView(choice: CardChoice(kind: .orphan(lastKnown: nil), card: ChipKeyInfo(kind: .infineon2Go, publicKey: MockChipReader.secp256k1Key, pinActive: false),
                                      tokenID: 421, pocket: nil, pocketIsEmpty: false), onStartNewAccount: {})
}
