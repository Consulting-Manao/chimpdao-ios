import SwiftUI

/// Contenu de la feuille de saisie du PIN (C6, F8) : étape, titre, rappel de l'action, puis `ChimpPinPad`.
///
/// Indépendante de l'ordre PIN / tap : elle peut venir avant `CardTapSheet` (PIN puis tap)
/// ou après une première lecture de la carte (tap puis PIN, suivi d'un second tap pour signer).
/// Pas de bandeau « la carte reste posée » (C6) : impossible sur iPhone, la fenêtre NFC d'iOS
/// couvre l'écran pendant la lecture.
///
/// À présenter avec `.chimpSheet(isPresented:...)` (hauteur par défaut : 560 pt).
struct PinSheet: View {
    /// Libellé d'étape (« Step 1 of 2 · PIN », « Last step · PIN »), en majuscules.
    var stepLabel: LocalizedStringKey?
    /// « Jungle's PIN », « Your card's PIN ».
    let title: LocalizedStringKey
    /// Rappel de ce qu'on signe (« Paying Maya $25.00 »).
    var subtitle: LocalizedStringKey?
    @Binding var pin: String
    let length: Int
    @Binding var state: ChimpPinState
    /// Paiement : « … Nothing was sent. » après un PIN faux.
    var saysNothingWasSent = false
    var onComplete: (String) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            if let stepLabel {
                Text(stepLabel)
                    .chimpFont(.labelWide)
                    .textCase(.uppercase)
                    .foregroundStyle(.chimpTextSecondary)
            }
            Text(title)
                .chimpFont(.sheetTitle)
                .padding(.top, ChimpSpacing.s)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .chimpFont(.bodyS)
                    .foregroundStyle(.chimpTextSecondary)
                    .padding(.top, ChimpSpacing.xxs)
            }
            ChimpPinPad(pin: $pin, length: length, state: $state, saysNothingWasSent: saysNothingWasSent, onComplete: onComplete)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, ChimpSpacing.xxl)
    }
}

private struct PinSheetPreview: View {
    @State private var isPresented = true
    @State private var pin = ""
    @State private var state = ChimpPinState.entering

    var body: some View {
        Color(.chimpBackground)
            .ignoresSafeArea()
            .chimpSheet(isPresented: $isPresented) {
                PinSheet(
                    stepLabel: "Step 1 of 2 · PIN",
                    title: "Jungle's PIN",
                    subtitle: "Paying Maya $25.00",
                    pin: $pin,
                    length: 4,
                    state: $state
                )
            }
    }
}

#Preview("Light") {
    PinSheetPreview()
}

#Preview("Dark") {
    PinSheetPreview()
        .preferredColorScheme(.dark)
}
