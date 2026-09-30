import SwiftUI

/// C7 · « Wrong banana! » (maquette) : écran plein sur le fond de l'en-tête, Chimpy debout, la carte tapée (pâle) et la
/// carte attendue (entourée), et un seul bouton pour retaper. Rien n'a été envoyé à la carte tapée après la lecture de
/// sa clé : ni PIN, ni signature. Variantes absentes de la maquette (textes proposés, DESIGN_NOTES §12) : carte qui
/// n'est pas du compte, envoi depuis Main (n'importe quelle carte), second tap de l'ordre « tap puis PIN ».
struct WrongCardView: View {
    let wrongCard: WrongCard
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: ChimpSpacing.l)
            VStack(spacing: 0) {
                Image(.chimpyStand)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 230)
                    .accessibilityHidden(true)
                Text("Wrong banana!")
                    .chimpFont(.displayL)
                    .foregroundStyle(.chimpOnHeaderPrimary)
                    .padding(.top, ChimpSpacing.l)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .chimpFont(.bodyL)
                    .lineSpacing(4)
                    .foregroundStyle(.chimpOnHeaderSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ChimpSpacing.m)
                if let needed = wrongCard.needed {
                    HStack(spacing: 18) {
                        thumbnail(color: wrongCard.tapped?.color ?? .jungle, label: "tapped", isNeeded: false)
                        thumbnail(color: needed.color, label: "needed", isNeeded: true)
                    }
                    .padding(.top, ChimpSpacing.xl)
                    .accessibilityHidden(true)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, ChimpSpacing.xxl + 6)
            Spacer(minLength: ChimpSpacing.l)
            VStack(spacing: ChimpSpacing.xs) {
                ChimpButton(retryTitle, action: onRetry)
                ChimpButton("Cancel", kind: .linkOnHeader, action: onCancel)
            }
            .padding(.horizontal, ChimpSpacing.fullScreenMargin)
            .padding(.bottom, ChimpSpacing.l)
        }
        .frame(maxWidth: .infinity)
        .chimpFullScreenBackground()
    }

    private var message: LocalizedStringKey {
        let tapped = wrongCard.tapped?.name
        let needed = wrongCard.needed?.name ?? ""
        switch (wrongCard.reason, tapped) {
        case (.otherWallet, let tapped?):
            return "You tapped your \(tapped) card. This money is in \(needed)'s wallet, so only that card can sign. Nothing was sent."
        case (.notTheSameCard, let tapped?):
            return "You tapped your \(tapped) card, but your PIN is for \(needed). Nothing was sent."
        case (.notTheSameCard, nil):
            return "That's not the card you started with. Your PIN is for \(needed). Nothing was sent."
        case (_, _) where wrongCard.needed == nil:
            return "That card isn't one of yours. Any card of your account can sign. Nothing was sent."
        default:
            return "That card isn't one of yours. This money is in \(needed)'s wallet, so only that card can sign. Nothing was sent."
        }
    }

    private var retryTitle: LocalizedStringKey {
        if let needed = wrongCard.needed { return "Try again with your \(needed.name) card" }
        return "Try again"
    }

    private func thumbnail(color: ChimpCardColor, label: LocalizedStringKey, isNeeded: Bool) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 10)
                .fill(color.fill)
                .frame(width: 72, height: 46)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isNeeded ? Color(.chimpOnHeaderAccent) : Color(.chimpOutline), lineWidth: 3)
                }
                .background {
                    if isNeeded {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.chimpOnHeaderAccent).opacity(0.35))
                            .padding(-4)
                    }
                }
                .opacity(isNeeded ? 1 : 0.6)
            Text(label)
                .chimpFont(.captionStrong)
                .foregroundStyle(isNeeded ? Color(.chimpOnHeaderAccent) : Color(.chimpOnHeaderSecondary))
        }
    }
}

#Preview("Autre carte du compte") {
    WrongCardView(
        wrongCard: WrongCard(reason: .otherWallet, tapped: KnownCard(name: "Banana", color: .banana), needed: KnownCard(name: "Jungle", color: .jungle)),
        onRetry: {}, onCancel: {}
    )
}

#Preview("Depuis Main, carte inconnue") {
    WrongCardView(wrongCard: WrongCard(reason: .notYours, tapped: nil, needed: nil), onRetry: {}, onCancel: {})
}
