#if CHIMP_ADMIN
import CoreNFC
import SwiftUI

/// « Prepare cards » (Chimp Admin, testnet) : un lot de cartes Infineon à la suite, sans revenir en arrière.
/// Textes en anglais et non traduits, comme tout le mode admin.
struct PrepareCardsView: View {
    @State private var model: PrepareCardsModel
    @State private var isConfirmingStart = false
    @State private var hasConfirmed = false
    @State private var numberText = ""
    let hasAdminKey: Bool

    init(model: PrepareCardsModel, hasAdminKey: Bool) {
        _model = State(initialValue: model)
        self.hasAdminKey = hasAdminKey
    }

    /// Les vrais services sur iPhone ; des faux sur un appareil sans NFC (simulateur).
    static func live(nfcAvailable: Bool = NFCTagReaderSession.readingAvailable) -> PrepareCardsModel? {
        guard let store = try? FilePreparedCardsStore() else { return nil }
        if nfcAvailable {
            return PrepareCardsModel(
                reader: NFCChipReader(), generator: NFCChipKeyGenerator(), signer: NFCChipSigner(),
                makeService: { try CardEnrolment(config: .testnet, keyStore: KeychainAdminKeyStore(network: .testnet)) },
                store: store,
                funder: (try? ChainFundingNetwork(config: .testnet)).map {
                    TestnetFunder(keyStore: KeychainAdminKeyStore(network: .testnet), network: $0)
                }
            )
        }
        return PrepareCardsModel(
            reader: MockChipReader(scenario: .infineon), generator: MockChipKeyGenerator(scenario: .noKey),
            signer: MockChipSigner(outcome: .success(.secp256k1(signature: Data(repeating: 0x11, count: 64)))),
            makeService: { MockCardEnrolmentService() }, store: MemoryPreparedCardsStore(), funder: MockTestnetFunding()
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                ChimpNoticeBanner(text: untranslated(
                    "Stellar Testnet · blank Infineon cards get their key, are registered, then get \(PrepareCardsModel.fundingXLM) test XLM on their wallet. No PIN is ever set: the user picks it."
                ))
                if !hasAdminKey {
                    ChimpNoticeBanner(text: untranslated("No admin key on this iPhone. Enter it in Admin first."), marker: .error)
                }
                counters
                numberField
                current
                actions
                journal
            }
            .padding(ChimpSpacing.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.chimpBackground))
        .navigationTitle(Text(verbatim: "Prepare cards"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear { numberText = String(model.nextNumber) }
        .onChange(of: model.nextNumber) { numberText = String(model.nextNumber) }
        .confirmationDialog(Text(verbatim: "Prepare a batch of cards?"), isPresented: $isConfirmingStart, titleVisibility: .visible) {
            Button(role: .destructive) {
                hasConfirmed = true
                Task { await model.scan() }
            } label: { Text(verbatim: "Start (key generation is irreversible)") }
            Button(role: .cancel) {} label: { Text(verbatim: "Cancel") }
        } message: {
            Text(verbatim: "A blank Infineon card creates its private key in slot 1: it can never be read, erased or replaced. "
                + "The app checks slot 1 on each card before generating, and never overwrites an existing key. Then the card is registered on testnet.")
        }
    }

    private var counters: some View {
        HStack(spacing: ChimpSpacing.l) {
            counter("\(model.preparedCount)", "ready")
            counter("\(model.fundedCount)", "funded")
            counter("\(model.failedCount)", "to retry")
            counter("\(model.cards.count)", "in the journal")
        }
    }

    private func counter(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value).chimpFont(.amountM).foregroundStyle(.chimpTextPrimary)
            Text(verbatim: label).chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
        }
    }

    private var numberField: some View {
        HStack {
            Text(verbatim: "Next card number").chimpFont(.rowTitle)
            Spacer()
            Text(verbatim: "#").chimpFont(.mono)
            TextField(text: $numberText) { Text(verbatim: "001") }
                .keyboardType(.numberPad)
                .chimpFont(.mono)
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
                .onChange(of: numberText) {
                    if let number = Int(numberText), number > 0 { model.nextNumber = number }
                }
                .disabled(model.isBusy)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))
    }

    @ViewBuilder
    private var current: some View {
        switch model.step {
        case .idle:
            Text(verbatim: "Put the next card on the top of the iPhone, then scan it.").chimpFont(.body).foregroundStyle(.chimpTextSecondary)
        case .reading:
            progress("Reading the card (and creating its key if it's blank)…")
        case .checking(let number):
            progress("\(number) · checking it on testnet…")
        case let .readyToSign(entry, plan):
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "\(entry.numberText) · ready to register").chimpFont(.sheetTitle)
                line("Card key", String(entry.publicKey.prefix(18)) + "…")
                line("Its wallet", entry.wallet)
                line("The card signs", "nfc-nft mint · nonce \(plan.nonce) · managed")
                line("PIN", "none (the user picks it later)")
            }
        case .signing(let entry):
            progress("\(entry.numberText) · the card is signing…")
        case .submitting(let entry):
            progress("\(entry.numberText) · registering on testnet…")
        case .funding(let entry):
            progress("\(entry.numberText) · sending \(PrepareCardsModel.fundingXLM) test XLM to its wallet…")
        case .done(let entry):
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "\(entry.numberText) · \(entry.statusText)").chimpFont(.sheetTitle)
                    .foregroundStyle(entry.isDone ? Color(.chimpPositive) : Color(.chimpNegative))
                line("Its wallet", entry.wallet)
                if let hash = entry.transactionHash { line("Transaction", hash) }
                if entry.funding != nil {
                    line("Test money", entry.fundingText)
                        .foregroundStyle(entry.isFunded ? Color(.chimpPositive) : Color(.chimpNegative))
                }
                if entry.needsFunding(true), case .failed = entry.funding {
                    Text(verbatim: "Tap the card again to retry the test money. It won't be registered twice.")
                        .chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
                }
            }
        case .problem(let message):
            ChimpNoticeBanner(text: untranslated(message), marker: .error)
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: ChimpSpacing.s) {
            ProgressView()
            Text(verbatim: text).chimpFont(.body).foregroundStyle(.chimpTextPrimary)
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: label).chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
            Spacer(minLength: ChimpSpacing.s)
            Text(verbatim: value).chimpFont(.mono).foregroundStyle(.chimpTextPrimary).lineLimit(1).truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch model.step {
        case .readyToSign:
            ChimpButton(untranslated("Tap the same card again to register it")) { Task { await model.signAndRegister() } }
            ChimpButton(untranslated("Skip this card"), kind: .link) { model.skip() }
        default:
            ChimpButton(untranslated("Scan card \(PreparedCard.numberText(model.nextNumber))"), isLoading: model.isBusy) {
                if hasConfirmed {
                    Task { await model.scan() }
                } else {
                    isConfirmingStart = true
                }
            }
            .disabled(model.isBusy || !hasAdminKey)
        }
    }

    private var journal: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.s) {
            HStack {
                Text(verbatim: "Journal").chimpFont(.displayS)
                Spacer()
                if let file = csvFile() {
                    ShareLink(item: file) { Text(verbatim: "Export CSV").chimpFont(.buttonSmall) }
                }
            }
            if let error = model.saveError {
                ChimpNoticeBanner(text: untranslated("The journal couldn't be saved: \(error)"), marker: .error)
            }
            ForEach(model.cards.sorted { $0.number > $1.number }) { card in
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: card.numberText).chimpFont(.mono)
                    Text(verbatim: card.isFunded ? "\(card.statusText) · funded" : card.statusText).chimpFont(.caption)
                        .foregroundStyle(card.isDone && card.isFunded ? Color(.chimpPositive) : Color(.chimpNegative))
                    Spacer()
                    Text(verbatim: String(card.wallet.prefix(6)) + "…" + String(card.wallet.suffix(4))).chimpFont(.mono)
                        .foregroundStyle(.chimpTextSecondary)
                }
            }
        }
    }

    /// Le CSV dans un fichier temporaire, pour la feuille de partage (AirDrop, Fichiers, mail).
    private func csvFile() -> URL? {
        guard !model.cards.isEmpty else { return nil }
        let day = Date.now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appending(path: "chimp-prepared-cards-\(day).csv")
        do {
            try model.csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
#endif
