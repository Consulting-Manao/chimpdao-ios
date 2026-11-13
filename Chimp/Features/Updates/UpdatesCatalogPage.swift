#if DESIGN_CATALOG
import SwiftUI

/// Catalogue (Debug et Testing) : Réglages › Updates sur une fausse chaîne, avec chaque état choisi d'avance.
/// Rien ne part : le compte et les wallets « changent de code » en mémoire seulement.
struct UpdatesCatalogPage: View {
    let settings: CatalogSettings
    @State private var scenario = MockUpdatesService.Scenario.accountUpdate
    @State private var isShowingDemo = false
    @State private var isShowingNotice = false

    var body: some View {
        CatalogPage("Updates", settings: settings, scrolls: false) {
            List {
                Section {
                    Picker(selection: $scenario) {
                        ForEach(MockUpdatesService.Scenario.allCases) { scenario in
                            Text(verbatim: scenario.rawValue).tag(scenario)
                        }
                    } label: {
                        Text("Chain").chimpFont(.rowTitle)
                    }
                } header: {
                    Text("Mock chain")
                } footer: {
                    Text("Nothing is sent. The real screen is in Settings › Safety › Updates.")
                }
                .listRowBackground(Color(.chimpSurface))

                Section("Try it") {
                    Button {
                        isShowingDemo = true
                    } label: {
                        Text(verbatim: "Open Updates").chimpFont(.rowTitle)
                    }
                    Button {
                        isShowingNotice = true
                    } label: {
                        Text(verbatim: "The Wallet pop-up").chimpFont(.rowTitle)
                    }
                }
                .listRowBackground(Color(.chimpSurface))
            }
            .scrollContentBackground(.hidden)
        }
        .chimpSheet(isPresented: $isShowingNotice, height: 560, fitsContent: true) {
            UpdateNoticeSheet(count: 1, onUpdate: { isShowingNotice = false }, onLater: { isShowingNotice = false })
        }
        .fullScreenCover(isPresented: $isShowingDemo) {
            UpdatesDemoRoot(scenario: scenario) { isShowingDemo = false }
                .catalogOverrides(settings)
        }
    }
}

/// Les Updates factices dans leur propre pile de navigation, avec un compte et deux cartes en mémoire.
private struct UpdatesDemoRoot: View {
    let scenario: MockUpdatesService.Scenario
    let onClose: () -> Void
    @State private var model: UpdatesModel

    static let account = "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"
    static let bananaPocket = "CDGFNWFN7ZKU4XDPNXOGDQ4JZ7SZCMXLL3PYFESOCCA2L5DM3ZBCPEKC"
    static let leafPocket = "CAOL3K7VQTDZELQMKTAJB3WUQGL5JLXJKZ2Y44F77NH4CZNLW5I755XI"

    init(scenario: MockUpdatesService.Scenario, onClose: @escaping () -> Void) {
        self.scenario = scenario
        self.onClose = onClose
        let session = AppSession(
            store: InMemoryLocalWalletStore(LocalWallet(
                firstName: "Léo", tourSeen: true,
                account: SavedAccount(address: Self.account, cards: [
                    SavedCard(publicKey: MockChipReader.secp256k1Key.hex, chip: "infineon2Go", tokenID: 7, pocket: Self.bananaPocket, name: "Banana", color: "banana"),
                    SavedCard(publicKey: MockChipReader.p256Key.hex, chip: "duox", tokenID: 8, pocket: Self.leafPocket, name: "Leaf", color: "leaf"),
                ])
            )),
            config: .testnet
        )
        _model = State(initialValue: UpdatesModel(
            session: session,
            service: MockUpdatesService(scenario: scenario, manualPockets: scenario == .accountAndCard ? [Self.bananaPocket] : [])
        ))
    }

    private var cards: [CardBalance] {
        [
            CardBalance(id: MockChipReader.secp256k1Key.hex, number: "0421", name: "Card", color: .jungle, assets: [], pocket: Self.bananaPocket, chip: .infineon2Go),
            CardBalance(id: MockChipReader.p256Key.hex, number: "0688", name: "Card", color: .jungle, assets: [], pocket: Self.leafPocket, chip: .duox),
        ]
    }

    var body: some View {
        NavigationStack {
            UpdatesView(model: model, cards: cards, onBack: onClose)
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ChimpButton("Close the demo", kind: .link, action: onClose).padding(ChimpSpacing.bottomBar)
                }
        }
    }
}
#endif
