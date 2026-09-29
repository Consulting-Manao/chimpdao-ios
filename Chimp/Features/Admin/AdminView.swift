#if CHIMP_ADMIN
import CoreNFC
import SwiftUI
import UIKit

/// Mode admin (testnet) : outil de développement, sans maquette, construit avec le design system.
/// Compilé uniquement en Debug et Testing (drapeau `CHIMP_ADMIN`), jamais en Release.
/// Étape A : lecture d'une carte, et génération de la clé d'une Infineon vierge (slot 1 vide, avec confirmation).
/// Étape B : clé admin (trousseau) et enregistrement (mint) de la carte lue sur testnet.
/// Onboarding, étape 1 : « Resolve this card », diagnostic en lecture seule de la carte lue.
/// Étape 5B : « Testnet money », 1000 XLM de testnet vers le Main account et chaque wallet de carte (`FundBlock` du terminal).
///
/// Textes en anglais et **non traduits** : ils restent hors du String Catalog (`Text(verbatim:)`, `untranslated`),
/// sinon Xcode les y ajouterait en Debug puis les supprimerait en Release, où ils n'existent pas.
struct AdminView: View {
    @State private var model = AdminCardReadModel(nfcAvailable: NFCTagReaderSession.readingAvailable)
    @State private var copied = false
    @State private var isConfirmingKeyGeneration = false
    @State private var keyModel = AdminKeyModel(store: KeychainAdminKeyStore(network: .testnet))
    /// Enregistrement de la carte lue ; recréé à chaque lecture.
    @State private var enrolModel: AdminEnrolModel?
    /// Diagnostic en lecture seule de la carte lue (onboarding, arrêt 1) ; recréé à chaque lecture.
    @State private var diagnosticsModel: AdminDiagnosticsModel?
    /// Argent de test (étape 5B) : créé à l'affichage, avec le compte ouvert sur ce téléphone.
    @State private var fundModel: AdminFundModel?
    @Environment(AppSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChimpSpacing.sectionGap) {
                ChimpNoticeBanner(text: untranslated("Admin mode · Stellar Testnet · Debug and Testing builds only"))
                AdminKeyPanel(model: keyModel)
                readerPicker
                ChimpButton(untranslated("Read a card"), isLoading: model.state == .reading) {
                    copied = false
                    enrolModel = nil
                    diagnosticsModel = nil
                    Task {
                        await model.read()
                        prepareEnrolment()
                    }
                }
                .disabled(model.isBusy || (enrolModel?.isBusy ?? false))
                result
                if let card = model.cardForEnrolment, let diagnosticsModel {
                    AdminDiagnosticsPanel(card: card, model: diagnosticsModel)
                }
                if let card = model.cardForEnrolment, let enrolModel {
                    AdminEnrolPanel(card: card, model: enrolModel, hasAdminKey: keyModel.hasKey || isMock)
                }
                if session.hasAccount, let fundModel {
                    AdminFundPanel(model: fundModel, hasAdminKey: keyModel.hasKey || isSimulator, usdcFaucet: ChimpNetworkConfig.testnet.usdcFaucet)
                }
            }
            .padding(ChimpSpacing.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.chimpBackground))
        .onAppear { if fundModel == nil { fundModel = makeFundModel() } }
        .navigationTitle(Text(verbatim: "Admin"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog(
            Text(verbatim: "Generate a key on this card?"),
            isPresented: $isConfirmingKeyGeneration,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                copied = false
                enrolModel = nil
                diagnosticsModel = nil
                Task {
                    await model.generateKey()
                    prepareEnrolment()
                }
            } label: {
                Text(verbatim: "Generate key (irreversible)")
            }
            Button(role: .cancel) {} label: { Text(verbatim: "Cancel") }
        } message: {
            Text(verbatim: "Irreversible. The card creates its private key in slot 1: it can never be read, erased or replaced. "
                + "Only for a blank Infineon card whose slot 1 is empty (6A88); the app checks again on the card before generating.")
        }
    }

    /// Sur simulateur (catalogue), faux financement : aucune requête. Sur iPhone : vrai testnet, clé admin du trousseau.
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private func makeFundModel() -> AdminFundModel? {
        let funder: TestnetFunding
        if isSimulator {
            funder = MockTestnetFunding()
        } else {
            guard let network = try? ChainFundingNetwork(config: .testnet) else { return nil }
            funder = TestnetFunder(keyStore: KeychainAdminKeyStore(network: .testnet), network: network)
        }
        return AdminFundModel(session: session, chain: ChainWalletReader(config: .testnet), funder: funder)
    }

    private var isMock: Bool {
        if case .mock = model.readerChoice { return true }
        return false
    }

    /// Carte lue (ou clé générée) : prépare l'enregistrement, avec les vrais services en NFC et des faux en mode factice.
    private func prepareEnrolment() {
        guard let card = model.cardForEnrolment else { return }
        diagnosticsModel = AdminDiagnosticsModel(service: isMock ? MockCardDiagnostics() : ChainCardDiagnostics(config: .testnet))
        if isMock {
            let signed: ChipSignedDigest = card.curve == .p256
                ? .p256(signature: Data(repeating: 0x11, count: 64), rndB: Data(repeating: 0xAB, count: 16))
                : .secp256k1(signature: Data(repeating: 0x11, count: 64))
            enrolModel = AdminEnrolModel(makeService: { MockCardEnrolmentService() }, signer: MockChipSigner(outcome: .success(signed)))
        } else {
            enrolModel = AdminEnrolModel(
                makeService: { try CardEnrolment(config: .testnet, keyStore: KeychainAdminKeyStore(network: .testnet)) },
                signer: NFCChipSigner()
            )
        }
    }

    private var readerPicker: some View {
        HStack {
            Text(verbatim: "Reader").chimpFont(.rowTitle)
            Spacer()
            Picker(selection: $model.readerChoice) {
                Text(verbatim: "NFC card").tag(AdminCardReadModel.ReaderChoice.nfc)
                ForEach(MockChipReader.Scenario.allCases) { scenario in
                    Text(verbatim: "Mock · \(scenario.label)").tag(AdminCardReadModel.ReaderChoice.mock(scenario))
                }
            } label: {
                Text(verbatim: "Reader")
            }
            .pickerStyle(.menu)
            .disabled(model.isBusy || (enrolModel?.isBusy ?? false))
        }
        .foregroundStyle(.chimpTextPrimary)
    }

    @ViewBuilder
    private var result: some View {
        switch model.state {
        case .idle, .reading:
            EmptyView()
        case .read(let info):
            keyPanel(title: "Card read", info: info)
        case .generated(let info):
            keyPanel(title: "Key generated in slot 1", info: info)
        case .generating:
            AdminPanel(title: "Generating the key…") {
                Text(verbatim: "Keep the card on the iPhone until the NFC sheet closes.").chimpFont(.body)
            }
        case .noKey(let statusWord):
            AdminPanel(title: "Card without a key", tone: .negative) {
                Text(verbatim: "Key slot 1 is empty (status \(statusWord.hexStatus)). This card can't be enrolled until it has a key.")
                    .chimpFont(.body)
                if model.canGenerateKey {
                    Text(verbatim: "Admin mode only: you can generate its key (approved by Pamphile for an empty slot 1).")
                        .chimpFont(.caption)
                        .foregroundStyle(.chimpTextSecondary)
                    ChimpButton(untranslated("Generate a key…"), kind: .destructive) {
                        isConfirmingKeyGeneration = true
                    }
                } else {
                    Text(verbatim: "Only an empty slot 1 (6A88) allows generating a key. Ask Pamphile before doing anything with it.")
                        .chimpFont(.caption)
                        .foregroundStyle(.chimpTextSecondary)
                }
            }
        case .cancelled:
            AdminPanel(title: "Scan cancelled") {
                Text(verbatim: "Nothing was read.").chimpFont(.body)
            }
        case .failed(let message):
            AdminPanel(title: "Couldn't read the card", tone: .negative) {
                Text(verbatim: message).chimpFont(.body).textSelection(.enabled)
            }
        }
    }
}

extension AdminView {
    /// Résultat d'une lecture ou d'une génération : puce, courbe, PIN et clé publique copiable.
    fileprivate func keyPanel(title: String, info: ChipKeyInfo) -> some View {
        AdminPanel(title: title) {
            AdminRow(label: "Chip", value: info.kind.displayName)
            AdminRow(label: "Curve", value: info.curve.rawValue)
            AdminRow(label: "PIN", value: info.kind == .duox ? "None on this chip" : (info.pinActive ? "Set" : "Not set"))
            VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                Text(verbatim: "Public key (65 bytes)").chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
                Text(verbatim: info.publicKey.hex)
                    .chimpFont(.address)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                ChimpButton(untranslated(copied ? "Copied!" : "Copy key"), kind: .secondary, size: .compact) {
                    UIPasteboard.general.string = info.publicKey.hex
                    copied = true
                }
            }
        }
    }
}

/// Clé de texte construite à l'exécution : Xcode ne l'extrait pas vers le String Catalog.
/// Pour les composants du design system qui attendent une `LocalizedStringKey`.
func untranslated(_ text: String) -> LocalizedStringKey {
    LocalizedStringKey(text)
}

/// Encadré d'un résultat du mode admin.
struct AdminPanel<Content: View>: View {
    enum Tone { case neutral, negative }

    let title: String
    var tone: Tone = .neutral
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.listGap) {
            Text(verbatim: title)
                .chimpFont(.displayS)
                .foregroundStyle(tone == .negative ? Color(.chimpNegative) : Color(.chimpTextPrimary))
            content
        }
        .foregroundStyle(.chimpTextPrimary)
        .padding(ChimpSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface), shadow: .card)
    }
}

/// Ligne « libellé : valeur » du mode admin.
struct AdminRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: label).chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
            Spacer()
            Text(verbatim: value).chimpFont(.rowTitle).multilineTextAlignment(.trailing)
        }
    }
}
#endif
