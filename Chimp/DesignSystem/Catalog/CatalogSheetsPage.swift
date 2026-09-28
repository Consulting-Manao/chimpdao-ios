#if DESIGN_CATALOG
import SwiftUI

/// Feuilles « approchez la carte » et PIN, présentées en vrai, dans les deux ordres.
struct CatalogSheetsPage: View {
    let settings: CatalogSettings

    @State private var tapStatus: CardTapPinStatus = .ready
    @State private var isTapSheetPresented = false
    @State private var isPinSheetPresented = false
    @State private var isScanning = false
    @State private var blocksDismiss = false
    @State private var pin = ""
    @State private var pinState = ChimpPinState.entering
    /// Démo seulement : dans l'app, les essais restants viennent de la réponse de la puce.
    @State private var demoTriesLeft = 3

    var body: some View {
        CatalogPage("Sheets", settings: settings) {
            Text("The card sheet is shown before the scan. \"Scan my card\" simulates a 2-second scan here: no NFC in the design system.")
                .chimpFont(.body)
                .foregroundStyle(.chimpTextSecondary)

            Toggle(isOn: $blocksDismiss) {
                Text("Block swipe to dismiss").chimpFont(.rowTitle)
            }

            VStack(alignment: .leading, spacing: ChimpSpacing.m) {
                CatalogSectionTitle("Card sheet")
                ChimpButton("Infineon · PIN already typed", kind: .secondary) { presentTapSheet(.ready) }
                ChimpButton("Infineon · PIN after the tap", kind: .secondary) { presentTapSheet(.afterTap) }
                ChimpButton("DUOX · no PIN", kind: .secondary) { presentTapSheet(.notNeeded) }
            }

            VStack(alignment: .leading, spacing: ChimpSpacing.m) {
                CatalogSectionTitle("PIN sheet")
                Text("Demo: 0000 is accepted. Any other PIN is refused, and the third refusal blocks the card.")
                    .chimpFont(.caption)
                    .foregroundStyle(.chimpTextSecondary)
                ChimpButton("PIN sheet (4 digits)", kind: .secondary) {
                    pin = ""
                    pinState = .entering
                    demoTriesLeft = 3
                    isPinSheetPresented = true
                }
            }
        }
        .chimpSheet(
            isPresented: $isTapSheetPresented,
            height: ChimpSize.cardTapSheetHeight,
            isDismissDisabled: blocksDismiss || isScanning
        ) {
            CardTapSheet(
                cardName: "Jungle",
                cardColor: .jungle,
                stepLabel: tapStatus == .afterTap ? "Step 1 of 2" : "Last step",
                what: "Paying Maya $25.00",
                who: "It's from Jungle's wallet, so only that card works.",
                pinStatus: tapStatus,
                isScanning: isScanning,
                onScan: simulateScan,
                onCancel: { isTapSheetPresented = false }
            )
        }
        .chimpSheet(isPresented: $isPinSheetPresented, isDismissDisabled: blocksDismiss) {
            PinSheet(
                stepLabel: "Step 1 of 2 · PIN",
                title: "Jungle's PIN",
                subtitle: "Paying Maya $25.00",
                pin: $pin,
                length: 4,
                state: $pinState
            ) { typed in
                if typed == "0000" {
                    isPinSheetPresented = false
                    return
                }
                demoTriesLeft -= 1
                pinState = demoTriesLeft > 0 ? .wrong(triesLeft: demoTriesLeft) : .blocked
            }
        }
    }

    private func presentTapSheet(_ status: CardTapPinStatus) {
        tapStatus = status
        isScanning = false
        isTapSheetPresented = true
    }

    private func simulateScan() {
        isScanning = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            isScanning = false
            isTapSheetPresented = false
        }
    }
}

#Preview {
    NavigationStack {
        CatalogSheetsPage(settings: CatalogSettings())
    }
}
#endif
