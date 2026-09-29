#if DESIGN_CATALOG
import SwiftUI

/// Catalogue (Debug et Testing) : réglages du parcours Envoyer factice, et accès direct au parcours.
/// Les réglages s'appliquent aussi à la tuile Send du Wallet.
struct SendCatalogPage: View {
    let settings: CatalogSettings
    @AppStorage(SendMockSettings.dataScenarioKey) private var dataScenario = MockSendService.DataScenario.standard
    @AppStorage(SendMockSettings.signingOrderKey) private var signingOrder = SigningOrder.pinThenTap
    @AppStorage(SendMockSettings.cardSetupKey) private var cardSetup = MockSendService.CardSetup.allWithPin

    var body: some View {
        CatalogPage("Send", settings: settings, scrolls: false) {
            List {
                Section {
                    Picker(selection: $dataScenario) {
                        ForEach(MockSendService.DataScenario.allCases) { scenario in
                            Text(scenario.title).tag(scenario)
                        }
                    } label: {
                        Text("Balances and recents").chimpFont(.rowTitle)
                    }
                    Text(dataScenario.detail)
                        .chimpFont(.caption)
                        .foregroundStyle(.chimpTextSecondary)
                } header: {
                    Text("Mock data")
                } footer: {
                    Text("Also used by the Send tile of the Wallet.")
                }
                .listRowBackground(Color(.chimpSurface))

                Section {
                    Picker(selection: $signingOrder) {
                        ForEach(SigningOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    } label: {
                        Text("Order").chimpFont(.rowTitle)
                    }
                    Text(signingOrder.detail)
                        .chimpFont(.caption)
                        .foregroundStyle(.chimpTextSecondary)
                    Picker(selection: $cardSetup) {
                        ForEach(MockSendService.CardSetup.allCases) { setup in
                            Text(setup.title).tag(setup)
                        }
                    } label: {
                        Text("Cards").chimpFont(.rowTitle)
                    }
                    Text(cardSetup.detail)
                        .chimpFont(.caption)
                        .foregroundStyle(.chimpTextSecondary)
                } header: {
                    Text("PIN and tap")
                } footer: {
                    Text("Release always uses PIN then tap until the order is decided.")
                }
                .listRowBackground(Color(.chimpSurface))

                Section("Try it") {
                    NavigationLink {
                        SendCatalogDemo(settings: settings)
                    } label: {
                        Text("Open Send (C1)").chimpFont(.rowTitle)
                    }
                }
                .listRowBackground(Color(.chimpSurface))

                Section {
                    ForEach(Self.sampleAddresses, id: \.address) { sample in
                        Button {
                            UIPasteboard.general.string = sample.address
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sample.title).chimpFont(.rowTitle)
                                Text(verbatim: sample.address)
                                    .chimpFont(.mono)
                                    .foregroundStyle(.chimpTextSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .foregroundStyle(.chimpTextPrimary)
                        }
                    }
                } header: {
                    Text("Addresses to paste")
                } footer: {
                    Text("Tap one to copy it, then use Paste on C1.")
                }
                .listRowBackground(Color(.chimpSurface))
            }
            .scrollContentBackground(.hidden)
        }
    }

    /// Exemples à copier (tap = copié), pour tester chaque message du champ d'adresse.
    private static let sampleAddresses: [(title: LocalizedStringKey, address: String)] = [
        ("Valid G (Maya)", MockSendService.mayaAddress),
        ("Valid G (exchange, add a memo ID)", MockSendService.exchangeAddress),
        ("Valid M (memo ID 1234567890)", MockSendService.exchangeMuxedAddress),
        ("My Main account", MockReceiveDataSource.mainAddress),
        ("Jungle's wallet", MockReceiveDataSource.jungleAddress),
        ("Typo (last character changed)", String(MockSendService.mayaAddress.dropLast()) + "Q"),
        ("Cut short", String(MockSendService.mayaAddress.prefix(40))),
        ("Secret key (fake)", "SCQF355RQFN77CHM5DHEGK75FWVF26PUES6J6EMQ4U7BAD3E7ORDGXPO"),
        ("XRP Ledger", "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"),
        ("Federation", "maya*chimp.xyz"),
    ]
}

/// Le parcours en plein écran, dans la pile du catalogue.
private struct SendCatalogDemo: View {
    let settings: CatalogSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SendFlowRoot { dismiss() }
            .catalogOverrides(settings)
    }
}

private extension SigningOrder {
    var title: LocalizedStringKey {
        switch self {
        case .pinThenTap: "PIN then tap"
        case .tapThenPin: "Tap then PIN"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .pinThenTap: "Review, PIN, then one tap that checks the card, sends the PIN and signs."
        case .tapThenPin: "Review, a first tap to read the card, PIN, then a second tap to sign."
        }
    }
}

private extension MockSendService.CardSetup {
    var title: LocalizedStringKey {
        switch self {
        case .allWithPin: "All with PIN"
        case .noPin: "No PIN (DUOX)"
        case .mixed: "Mixed"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .allWithPin: "Jungle and Banana are Infineon cards with a PIN."
        case .noPin: "Jungle and Banana are DUOX cards: one tap, never a PIN."
        case .mixed: "Jungle has a PIN, Banana has none. From Main, Jungle is the card tapped."
        }
    }
}

private extension MockSendService.DataScenario {
    var title: LocalizedStringKey {
        switch self {
        case .standard: "Mockup"
        case .emptyBalances: "Empty balances"
        case .mainOnly: "Main only"
        case .noRecents: "No recents"
        case .loadingForever: "Loading"
        case .networkError: "Network error"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .standard: "Main 720 USDC + 400 XLM, Jungle 62.50 USDC, Banana 72.50 USDC + 120 XLM. Three recents."
        case .emptyBalances: "Everything at zero: Max and quick amounts are disabled."
        case .mainOnly: "No drawer to choose: no arrow on From."
        case .noRecents: "The Recent section is hidden."
        case .loadingForever: "Balances never arrive."
        case .networkError: "Balances can't be loaded (Try again on C2)."
        }
    }
}
#endif
