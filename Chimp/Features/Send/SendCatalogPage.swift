#if DESIGN_CATALOG
import SwiftUI

/// Catalogue (Debug et Testing) : réglages du parcours Envoyer factice, et accès direct au parcours.
/// Les réglages s'appliquent aussi à la tuile Send du Wallet.
struct SendCatalogPage: View {
    let settings: CatalogSettings
    @AppStorage(SendMockSettings.dataScenarioKey) private var dataScenario = MockSendService.DataScenario.standard
    @AppStorage(SendMockSettings.signingOrderKey) private var signingOrder = SigningOrder.pinThenTap
    @AppStorage(SendMockSettings.cardSetupKey) private var cardSetup = MockSendService.CardSetup.allWithPin
    @AppStorage(SendMockSettings.resultScenarioKey) private var resultScenario = MockSendService.ResultScenario.sent
    @AppStorage(SendMockSettings.tapScenarioKey) private var tapScenario = MockSendService.TapScenario.rightCard
    /// Parcours ouvert. Un drapeau et non `@Environment(\.dismiss)` : lu au-dessus du parcours, `dismiss` changeait à
    /// chaque écran poussé et faisait tourner l'app en boucle (même piège que C2 / C4, corrigé au jalon 7).
    @State private var isShowingDemo = false
    @State private var isShowingMoveDemo = false

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
                    Picker(selection: $resultScenario) {
                        ForEach(MockSendService.ResultScenario.allCases) { scenario in
                            Text(scenario.title).tag(scenario)
                        }
                    } label: {
                        Text("Result").chimpFont(.rowTitle)
                    }
                    Text(resultScenario.detail)
                        .chimpFont(.caption)
                        .foregroundStyle(.chimpTextSecondary)
                } header: {
                    Text("Mock data")
                } footer: {
                    Text("Only for the flow opened here. The Send tile of the Wallet sends for real on testnet.")
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
                    Picker(selection: $tapScenario) {
                        ForEach(MockSendService.TapScenario.allCases) { scenario in
                            Text(scenario.title).tag(scenario)
                        }
                    } label: {
                        Text("Tap").chimpFont(.rowTitle)
                    }
                    Text(tapScenario.detail)
                        .chimpFont(.caption)
                        .foregroundStyle(.chimpTextSecondary)
                } header: {
                    Text("PIN and tap")
                } footer: {
                    Text("Release always uses PIN then tap until the order is decided.")
                }
                .listRowBackground(Color(.chimpSurface))

                Section("Try it") {
                    Button {
                        isShowingDemo = true
                    } label: {
                        Text("Open Send (C1)").chimpFont(.rowTitle)
                    }
                    Button {
                        isShowingMoveDemo = true
                    } label: {
                        Text(verbatim: "Open Move (E1)").chimpFont(.rowTitle)
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
        .navigationDestination(isPresented: $isShowingDemo) {
            SendCatalogDemo(settings: settings) { isShowingDemo = false }
        }
        .navigationDestination(isPresented: $isShowingMoveDemo) {
            SendCatalogDemo(settings: settings, kind: .move) { isShowingMoveDemo = false }
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
    var kind: SendFlowModel.FlowKind = .send
    let onExit: () -> Void

    var body: some View {
        SendFlowRoot(service: SendMockSettings.makeService(), kind: kind, onExit: onExit)
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

private extension MockSendService.TapScenario {
    var title: LocalizedStringKey {
        switch self {
        case .rightCard: "Right card"
        case .otherCard: "Another card first"
        case .unknownCard: "Unknown card first"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .rightCard: "The card tapped can sign."
        case .otherCard: "The first tap is Banana, another card of the account: Wrong banana! (C7). The next tap works."
        case .unknownCard: "The first tap is a card from another account (C7). The next tap works."
        }
    }
}

private extension MockSendService.ResultScenario {
    var title: LocalizedStringKey {
        switch self {
        case .sent: "Sent"
        case .notConfirmedThenSent: "Not confirmed, then sent"
        case .rejectedThenNothingSent: "Not sent, wait, nothing sent"
        case .undetermined: "Can't tell"
        case .withheld: "Held back, Try again"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .sent: "Confirmed at once: Swoosh! and the receipt."
        case .notConfirmedThenSent: "Not confirmed yet; Check again finds it confirmed."
        case .rejectedThenNothingSent: "Refused after signing: a 15-second wait, then Nothing was sent."
        case .undetermined: "Stellar can't tell: Check again and Stellar Expert."
        case .withheld: "The first send is held back: Not sent yet, then Try again sends the same signature (no new tap)."
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
        case .longDecimals: "7-digit balances"
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
        case .longDecimals: "Main holds 999.6196784 XLM, Banana 0.0000042 XLM: 2 decimals at most on screen."
        }
    }
}
#endif
