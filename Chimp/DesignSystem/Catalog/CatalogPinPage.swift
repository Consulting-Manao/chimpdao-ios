#if DESIGN_CATALOG
import SwiftUI

/// Saisie du PIN (longueur réglable, erreur, carte bloquée) et pavé en mode montant.
struct CatalogPinPage: View {
    let settings: CatalogSettings
    @State private var length = 4
    @State private var pin = ""
    @State private var state = ChimpPinState.entering
    @State private var completedCount = 0
    @State private var amount = ""

    var body: some View {
        CatalogPage("Keypad and PIN", settings: settings) {
            VStack(alignment: .leading, spacing: ChimpSpacing.m) {
                CatalogSectionTitle("PIN")
                Stepper(value: $length, in: 4...8) {
                    Text("PIN length: \(length)").chimpFont(.rowTitle)
                }
                .onChange(of: length) { pin = ""; state = .entering }

                HStack(spacing: ChimpSpacing.sm) {
                    ChimpButton("Wrong, 2 left", kind: .secondary, size: .compact) { state = .wrong(triesLeft: 2) }
                    ChimpButton("Wrong", kind: .secondary, size: .compact) { state = .wrong(triesLeft: nil) }
                }
                HStack(spacing: ChimpSpacing.sm) {
                    ChimpButton("Blocked", kind: .secondary, size: .compact) { state = .blocked }
                    ChimpButton("Reset", kind: .secondary, size: .compact) { state = .entering; pin = "" }
                }
                Text("Completed PINs: \(completedCount). The PIN is only kept in this screen's memory.")
                    .chimpFont(.caption)
                    .foregroundStyle(.chimpTextSecondary)

                ChimpPinPad(pin: $pin, length: length, state: $state) { _ in
                    completedCount += 1
                }
                .frame(height: 420)
            }

            VStack(alignment: .leading, spacing: ChimpSpacing.m) {
                CatalogSectionTitle("Keypad · amount")
                Text("The decimal key follows the phone's language.")
                    .chimpFont(.caption)
                    .foregroundStyle(.chimpTextSecondary)
                Text(verbatim: amount.isEmpty ? "0" : amount)
                    .chimpFont(.amountL)
                    .frame(maxWidth: .infinity)
                ChimpKeypad(mode: .amount) { key in
                    switch key {
                    case .digit(let value): amount.append(String(value))
                    case .decimal: amount.append(Locale.current.decimalSeparator ?? ".")
                    case .delete: if !amount.isEmpty { amount.removeLast() }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CatalogPinPage(settings: CatalogSettings())
    }
}
#endif
