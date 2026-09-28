import SwiftUI

/// Où en est le PIN au moment d'approcher la carte. La feuille ne suppose aucun ordre PIN / tap.
enum CardTapPinStatus {
    /// Carte avec PIN (Infineon), PIN déjà saisi avant ce tap.
    case ready
    /// Carte avec PIN (Infineon), PIN à saisir juste après ce tap.
    case afterTap
    /// Carte sans PIN (DUOX).
    case notNeeded
}

/// Contenu de la feuille « approchez la carte » (« Chimp Sign » dans la maquette), affichée **avant** le scan.
///
/// Elle prépare le moment où iOS affichera sa propre fenêtre NFC (non personnalisable, sauf son texte) :
/// ce qu'on signe, avec quelle carte, où la poser, et où en est le PIN. Le scan ne démarre
/// que quand l'utilisateur touche « Scan my card ». Aucun code NFC ici.
///
/// À présenter avec `.chimpSheet(isPresented:height: ChimpSize.cardTapSheetHeight, ...)`.
struct CardTapSheet: View {
    /// Nom de la carte qui doit signer (donnée locale, affichée telle quelle).
    let cardName: String
    let cardColor: ChimpCardColor
    /// Libellé d'étape (« Last step », « Step 1 of 2 »), en majuscules.
    var stepLabel: LocalizedStringKey?
    /// Titre ; par défaut « Hold your <carte> card to your phone ».
    var title: LocalizedStringKey?
    /// Ce qu'on signe (« Paying Maya $25.00 »). Toujours montré avant la session NFC (règle 8).
    let what: LocalizedStringKey
    /// Qui peut signer et pourquoi (« Only your Jungle card can sign »).
    var who: LocalizedStringKey?
    let pinStatus: CardTapPinStatus
    /// Session NFC en cours d'ouverture : le bouton affiche une roue et ne réagit plus.
    var isScanning = false
    let onScan: () -> Void
    /// Lien « Cancel » affiché seulement si une action est fournie.
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if let stepLabel {
                Text(stepLabel)
                    .chimpFont(.labelWide)
                    .textCase(.uppercase)
                    .foregroundStyle(.chimpTextSecondary)
            }
            Text(title ?? "Hold your \(cardName) card to your phone")
                .chimpFont(.sheetTitle)
                .padding(.top, ChimpSpacing.s)
                .accessibilityAddTraits(.isHeader)
            // Même consigne que le texte de la fenêtre NFC d'iOS (alertMessage), à reprendre dans Core/NFC.
            Text("Place it flat against the top of the back of your iPhone and keep it still.")
                .chimpFont(.bodyS)
                .foregroundStyle(.chimpTextSecondary)
                .padding(.top, ChimpSpacing.xs)

            Spacer(minLength: ChimpSpacing.s)
            ChimpNFCRings {
                ChimpCardThumbnail(color: cardColor)
            }
            .accessibilityHidden(true)
            Spacer(minLength: ChimpSpacing.s)

            Text(what)
                .chimpFont(.body)
                .lineSpacing(4)
                .padding(.vertical, 13 + ChimpBorder.regular)
                .padding(.horizontal, ChimpSpacing.ml + 1 + ChimpBorder.regular)
                .frame(maxWidth: .infinity)
                .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))

            if let who {
                ChimpNoticeBanner(text: who, marker: .card(cardColor))
                    .padding(.top, ChimpSpacing.sm)
            }

            pinLine
                .padding(.top, ChimpSpacing.m)

            ChimpButton("Scan my card", isLoading: isScanning, action: onScan)
                .padding(.top, ChimpSpacing.ml)

            if let onCancel {
                ChimpButton("Cancel", kind: .link, action: onCancel)
                    .padding(.top, ChimpSpacing.xs)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, ChimpSpacing.fullScreenMargin)
    }

    private var pinLine: some View {
        HStack(spacing: ChimpSpacing.xs) {
            Image(systemName: pinIcon)
                .fontWeight(.heavy)
                .foregroundStyle(pinStatus == .ready ? Color(.chimpPositive) : Color(.chimpTextSecondary))
                .accessibilityHidden(true)
            Text(pinText)
                .chimpFont(.caption)
                .foregroundStyle(.chimpTextSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var pinIcon: String {
        switch pinStatus {
        case .ready: "checkmark.circle.fill"
        case .afterTap: "circle.grid.3x3.fill"
        case .notNeeded: "hand.raised.fill"
        }
    }

    private var pinText: LocalizedStringKey {
        switch pinStatus {
        case .ready: "PIN ready"
        case .afterTap: "You'll type your PIN right after."
        case .notNeeded: "No PIN needed. Just hold your card."
        }
    }
}

private struct CardTapSheetPreview: View {
    @State private var isPresented = true
    var pinStatus: CardTapPinStatus

    var body: some View {
        Color(.chimpBackground)
            .ignoresSafeArea()
            .chimpSheet(isPresented: $isPresented, height: ChimpSize.cardTapSheetHeight) {
                CardTapSheet(
                    cardName: "Jungle",
                    cardColor: .jungle,
                    stepLabel: "Last step",
                    what: "Paying Maya $25.00",
                    who: "The money is in your Jungle card's wallet, so only that card can sign.",
                    pinStatus: pinStatus,
                    onScan: {},
                    onCancel: { isPresented = false }
                )
            }
    }
}

#Preview("Infineon · PIN saisi") {
    CardTapSheetPreview(pinStatus: .ready)
}

#Preview("DUOX · sombre") {
    CardTapSheetPreview(pinStatus: .notNeeded)
        .preferredColorScheme(.dark)
}
