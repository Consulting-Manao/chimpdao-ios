#if CHIMP_ADMIN
import CoreNFC
import SwiftUI
import UIKit

/// Mode admin (testnet) : outil de développement, sans maquette, construit avec le design system.
/// Compilé uniquement en Debug et Testing (drapeau `CHIMP_ADMIN`), jamais en Release.
/// Étape A : lecture d'une carte. L'enregistrement (mint) arrive à l'étape B.
///
/// Textes en anglais et **non traduits** : ils restent hors du String Catalog (`Text(verbatim:)`, `untranslated`),
/// sinon Xcode les y ajouterait en Debug puis les supprimerait en Release, où ils n'existent pas.
struct AdminView: View {
    @State private var model = AdminCardReadModel(nfcAvailable: NFCTagReaderSession.readingAvailable)
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChimpSpacing.sectionGap) {
                ChimpNoticeBanner(text: untranslated("Admin mode · Stellar Testnet · Debug and Testing builds only"))
                readerPicker
                ChimpButton(untranslated("Read a card"), isLoading: model.isReading) {
                    copied = false
                    Task { await model.read() }
                }
                result
            }
            .padding(ChimpSpacing.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.chimpBackground))
        .navigationTitle(Text(verbatim: "Admin"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
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
            .disabled(model.isReading)
        }
        .foregroundStyle(.chimpTextPrimary)
    }

    @ViewBuilder
    private var result: some View {
        switch model.state {
        case .idle, .reading:
            EmptyView()
        case .read(let info):
            AdminPanel(title: "Card read") {
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
        case .noKey(let statusWord):
            AdminPanel(title: "Card without a key", tone: .negative) {
                Text(verbatim: "Key slot 1 is empty (status \(statusWord.hexStatus)). This card can't be enrolled.")
                    .chimpFont(.body)
                Text(verbatim: "ChimpDAO never generates a key on a card. Ask Pamphile before doing anything with it.")
                    .chimpFont(.caption)
                    .foregroundStyle(.chimpTextSecondary)
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
