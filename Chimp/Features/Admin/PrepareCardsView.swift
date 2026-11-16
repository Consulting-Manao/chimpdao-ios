#if CHIMP_ADMIN
import CoreNFC
import SwiftUI

/// « Prepare cards » (Chimp Admin, testnet) : un assistant pas à pas, un écran par étape et une seule action par écran
/// (refonte demandée par Barth le 2026-10-20). Textes en anglais et non traduits, comme tout le mode admin.
struct PrepareCardsView: View {
    @State private var model: PrepareCardsModel
    @State private var isConfirmingStart = false
    @State private var hasConfirmed = false
    @State private var isShowingAllCards = false
    @State private var isCheckingCard = false
    let hasAdminKey: Bool

    init(model: PrepareCardsModel, hasAdminKey: Bool) {
        _model = State(initialValue: model)
        self.hasAdminKey = hasAdminKey
    }

    /// Les vrais services sur iPhone ; des faux sur un appareil sans NFC (simulateur).
    static func live(nfcAvailable: Bool = NFCTagReaderSession.readingAvailable) -> PrepareCardsModel? {
        guard let store = try? FilePreparedCardsStore() else { return nil }
        if nfcAvailable {
            let wallets = ChainWalletReader(config: .testnet)
            return PrepareCardsModel(
                reader: NFCChipReader(), generator: NFCChipKeyGenerator(), signer: NFCChipSigner(),
                makeService: { try CardEnrolment(config: .testnet, keyStore: KeychainAdminKeyStore(network: .testnet)) },
                store: store,
                funder: (try? ChainFundingNetwork(config: .testnet)).map {
                    TestnetFunder(keyStore: KeychainAdminKeyStore(network: .testnet), network: $0)
                },
                readXLM: { wallet in
                    try await wallets.balances(of: wallet).first { $0.code == "XLM" }?.amount ?? 0
                }
            )
        }
        return PrepareCardsModel(
            reader: MockChipReader(scenario: .infineon), generator: MockChipKeyGenerator(scenario: .noKey),
            signer: MockChipSigner(outcome: .success(.secp256k1(signature: Data(repeating: 0x11, count: 64)))),
            makeService: { MockCardEnrolmentService() }, store: MemoryPreparedCardsStore(), funder: MockTestnetFunding(),
            readXLM: { _ in
                try await Task.sleep(for: .milliseconds(400))
                return 50
            }
        )
    }

    var body: some View {
        content
            .animation(.easeInOut(duration: 0.2), value: model.step)
            .background(Color(.chimpBackground))
            .navigationTitle(Text(verbatim: "Cards"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .navigationBarBackButtonHidden(model.isBusy)
            .navigationDestination(isPresented: $isShowingAllCards) {
                PreparedCardsListView(model: model)
            }
            .navigationDestination(isPresented: $isCheckingCard) {
                CheckCardView(model: model)
            }
            .confirmationDialog(Text(verbatim: "Prepare cards?"), isPresented: $isConfirmingStart, titleVisibility: .visible) {
                Button(role: .destructive) {
                    hasConfirmed = true
                    Task { await model.startCard() }
                } label: { Text(verbatim: "Start (key creation is irreversible)") }
                Button(role: .cancel) {} label: { Text(verbatim: "Cancel") }
            } message: {
                Text(verbatim: "A blank Infineon card creates its private key in slot 1: it can never be read, erased or replaced. "
                    + "The app checks slot 1 on each card first, and never overwrites a key. No PIN is ever set.")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .home:
            home
        case .tapCard, .reading, .checking, .readFailed:
            tapCard
        case .cannotPrepare(let reason):
            cannotPrepare(reason)
        case .alreadyReady(let entry):
            alreadyReady(entry)
        case .identify(let draft):
            PrepareIdentityStep(model: model, draft: draft)
                .id(draft.entry.publicKey)
        case .startingMoney(let draft):
            PrepareMoneyStep(model: model, draft: draft)
                .id(draft.entry.publicKey)
        case let .finishing(draft, finishing):
            finishingStep(draft, finishing)
        case .ready(let entry):
            ready(entry)
        }
    }

    // MARK: Accueil

    private var home: some View {
        PrepareStepScreen(overline: "Stellar Testnet", title: "Cards",
                          lead: "Each card gets its key, is registered, and receives a little test money. Then it's ready to give away.") {
            VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                // Pas de taille de lot (Barth, 2026-10-23) : seulement les cartes prêtes, sans limite.
                Text(verbatim: "\(model.readyCount)").chimpFont(.displayXL)
                Text(verbatim: model.readyCount == 1 ? "card ready" : "cards ready").chimpFont(.bodyL).foregroundStyle(.chimpTextSecondary)
            }
            .padding(ChimpSpacing.lg + ChimpBorder.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface), shadow: .card)
            .accessibilityElement(children: .combine)
            CardDesignPicker(
                designs: model.designs, isLoading: model.isLoadingDesigns,
                selection: Binding(get: { model.design }, set: { model.design = $0 })
            )
            if !hasAdminKey {
                ChimpNoticeBanner(text: untranslated("No admin key on this iPhone yet."), marker: .error)
            }
            if let error = model.saveError {
                ChimpNoticeBanner(text: untranslated("The journal couldn't be saved: \(error)"), marker: .error)
            }
        } actions: {
            ChimpButton(untranslated("Prepare a card"), size: .large) { prepareCard() }
                .disabled(!hasAdminKey)
            ChimpButton(untranslated("Check a card"), kind: .secondary) {
                model.resetCheck()
                isCheckingCard = true
            }
            ChimpButton(untranslated("See all cards"), kind: .link) { isShowingAllCards = true }
        }
        .task { await designTask() }
    }

    private func designTask() async { await model.loadDesigns() }

    private func prepareCard() {
        if hasConfirmed {
            Task { await model.startCard() }
        } else {
            isConfirmingStart = true
        }
    }

    // MARK: Étape 1

    private var tapCard: some View {
        PrepareStepScreen(overline: "Step 1 of 4", title: "Tap the card", lead: tapLead) {
            ChimpNFCRings(size: 220) {
                ChimpCardThumbnail(color: nil)
            }
            .frame(maxWidth: .infinity)
            if case .readFailed(let message) = model.step {
                ChimpNoticeBanner(text: untranslated("The card couldn't be read. Nothing was written. Try again."), marker: .error)
                ChimpTechnicalDetails(details: message)
            }
        } actions: {
            ChimpButton(untranslated(model.isBusy ? "Reading…" : "Scan the card"), size: .large, isLoading: model.isBusy) {
                Task { await model.scan() }
            }
            .disabled(model.isBusy)
            ChimpButton(untranslated("Cancel"), kind: .link) { model.backHome() }
                .disabled(model.isBusy)
        }
    }

    private var tapLead: String {
        switch model.step {
        case .reading: "Keep the card still on the top of the iPhone. A blank card creates its key in this same tap."
        case .checking: "Checking the card on Stellar testnet…"
        default: "Hold the card flat on the top of the iPhone. A blank card creates its key in this same tap."
        }
    }

    private func cannotPrepare(_ reason: String) -> some View {
        PrepareStepScreen(overline: "Step 1 of 4", title: "This card can't be prepared", lead: reason) {
            ChimpNoticeBanner(text: untranslated("Nothing was written on this card. Put it aside."), marker: .error)
        } actions: {
            ChimpButton(untranslated("Next card"), size: .large) { Task { await model.startCard() } }
            ChimpButton(untranslated("Back to the start"), kind: .link) { model.backHome() }
        }
    }

    private func alreadyReady(_ entry: PreparedCard) -> some View {
        PrepareStepScreen(overline: "Already ready", title: "Card \(entry.numberText) is already ready",
                          lead: "It was registered before. Nothing was written on it again.") {
            PrepareFacts(rows: facts(for: entry, balance: true))
                .task(id: entry.wallet) { await model.loadBalance(of: entry.wallet, force: true) }
        } actions: {
            if entry.needsFunding {
                ChimpButton(untranslated("Send the test money (\(entry.fundingXLM) XLM)"), size: .large, isLoading: model.isSendingMoney) {
                    Task { await model.sendMoneyFromSheet() }
                }
                ChimpButton(untranslated("Prepare another card"), kind: .link) { Task { await model.startCard() } }
                    .disabled(model.isBusy)
            } else {
                ChimpButton(untranslated("Prepare another card"), size: .large) { Task { await model.startCard() } }
                ChimpButton(untranslated("Back to the start"), kind: .link) { model.backHome() }
            }
        }
    }

    // MARK: Étape 4

    private func finishingStep(_ draft: PrepareCardsModel.Draft, _ finishing: PrepareCardsModel.Finishing) -> some View {
        PrepareStepScreen(overline: "Step 4 of 4", title: "Tap the card again to finish",
                          lead: "The card signs its own registration on Stellar testnet. No PIN is set: its owner will choose one.") {
            Text(verbatim: summary(draft.entry)).chimpFont(.rowTitle).foregroundStyle(.chimpTextPrimary)
            ChimpProgressSteps(steps: [
                ChimpProgressStep(id: 0, label: Text(verbatim: "Key created"), state: .done),
                ChimpProgressStep(id: 1, label: Text(verbatim: "Card registered"), state: registerState(finishing)),
                ChimpProgressStep(id: 2, label: Text(verbatim: moneyLabel(draft.entry)), state: moneyState(draft.entry, finishing)),
            ])
            switch finishing {
            case .registerFailed(let message):
                ChimpNoticeBanner(
                    text: untranslated("The card wasn't registered. Tap it again: the app checks Stellar first, so it's never registered twice."),
                    marker: .error
                )
                ChimpTechnicalDetails(details: message)
            case .moneyFailed(let message):
                ChimpNoticeBanner(
                    text: untranslated("The card is registered, but the test money wasn't sent. Send it again: no need to tap the card."),
                    marker: .error
                )
                ChimpTechnicalDetails(details: message)
            default:
                if let plan = draft.plan {
                    ChimpTechnicalDetails(details: "The card signs: nfc-nft mint · nonce \(plan.nonce) · managed · contract \(plan.nfcNft) · "
                        + "wallet \(plan.predictedPocket) · no PIN")
                }
            }
        } actions: {
            switch finishing {
            case .waitingForTap:
                ChimpButton(untranslated("Tap the card"), size: .large) { Task { await model.signAndRegister() } }
            case .signing, .registering, .sendingMoney:
                ChimpButton(untranslated(finishing == .signing ? "The card is signing…" : "Finishing…"), size: .large, isLoading: true) {}
                    .disabled(true)
            case .registerFailed:
                ChimpButton(untranslated("Tap the card again"), size: .large) { Task { await model.retryRegistration() } }
            case .moneyFailed:
                ChimpButton(untranslated("Send the test money again"), size: .large) { Task { await model.retryMoney() } }
            }
            if finishing == .waitingForTap {
                ChimpButton(untranslated("Cancel"), kind: .link) { model.backHome() }
            }
        }
    }

    private func registerState(_ finishing: PrepareCardsModel.Finishing) -> ChimpProgressStep.State {
        switch finishing {
        case .waitingForTap: .todo
        case .signing, .registering: .current
        case .registerFailed: .failed
        case .sendingMoney, .moneyFailed: .done
        }
    }

    private func moneyState(_ entry: PreparedCard, _ finishing: PrepareCardsModel.Finishing) -> ChimpProgressStep.State {
        if entry.funding == .declined { return .done }
        switch finishing {
        case .sendingMoney: return .current
        case .moneyFailed: return .failed
        default: return entry.isFunded ? .done : .todo
        }
    }

    private func moneyLabel(_ entry: PreparedCard) -> String {
        entry.funding == .declined ? "No test money (None chosen)" : "Test money sent (\(entry.fundingXLM) XLM)"
    }

    private func summary(_ entry: PreparedCard) -> String {
        [entry.numberText, entry.note].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Étape 5

    private func ready(_ entry: PreparedCard) -> some View {
        PrepareStepScreen(overline: "Done", title: "Card \(entry.numberText) is ready!",
                          lead: "Its owner creates an account by tapping it, and chooses the PIN.") {
            PrepareFacts(rows: facts(for: entry, balance: false))
        } actions: {
            ChimpButton(untranslated("Prepare the next card"), size: .large) { Task { await model.startCard() } }
            ChimpButton(untranslated("Back to the start"), kind: .link) { model.backHome() }
        }
    }

    private func facts(for entry: PreparedCard, balance: Bool) -> [(String, String)] {
        var rows: [(String, String)] = [("Number", entry.numberText)]
        if let note = entry.note { rows.append(("Note", note)) }
        if balance { rows.append(("Balance", PreparedCardsListView.balanceText(model.balances[entry.wallet]))) }
        rows.append(("Test money", entry.funding == nil ? "not sent yet" : entry.fundingText))
        rows.append(("Wallet", entry.wallet))
        if let hash = entry.transactionHash { rows.append(("Registration", hash)) }
        return rows
    }
}

// MARK: - Étapes 2 et 3

/// Étape 2 : « Which card is it? » (numéro imprimé, note facultative).
private struct PrepareIdentityStep: View {
    let model: PrepareCardsModel
    let draft: PrepareCardsModel.Draft
    @State private var numberText: String
    @State private var note: String
    @FocusState private var focus: Field?

    private enum Field { case number, note }

    init(model: PrepareCardsModel, draft: PrepareCardsModel.Draft) {
        self.model = model
        self.draft = draft
        _numberText = State(initialValue: String(format: "%03d", draft.entry.number))
        _note = State(initialValue: draft.entry.note ?? "")
    }

    private var problem: String? { model.numberProblem(Int(numberText), for: draft) }

    var body: some View {
        PrepareStepScreen(overline: draft.plan == nil ? "Already registered" : "Step 2 of 4", title: "Which card is it?",
                          lead: "Check the number printed on the card. The next free number is suggested.") {
            VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                Text(verbatim: "Number on the card").chimpFont(.captionStrong).foregroundStyle(.chimpTextSecondary)
                ChimpInputField {
                    HStack(spacing: ChimpSpacing.xs) {
                        Text(verbatim: "#").chimpFont(.fieldM)
                        TextField(text: $numberText) { Text(verbatim: "001") }
                            .keyboardType(.numberPad)
                            .chimpFont(.fieldM)
                            .focused($focus, equals: .number)
                    }
                }
                if let problem {
                    ChimpFieldMessage(text: untranslated(problem), kind: .error)
                }
            }
            VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                Text(verbatim: "Note (optional)").chimpFont(.captionStrong).foregroundStyle(.chimpTextSecondary)
                ChimpInputField {
                    TextField(text: $note) { Text(verbatim: "Pamphile's demo card") }
                        .chimpFont(.fieldM)
                        .submitLabel(.done)
                        .focused($focus, equals: .note)
                }
                ChimpFieldMessage(text: untranslated("Only in Chimp Admin and the CSV. The card's owner never sees it."))
            }
        } actions: {
            ChimpButton(untranslated(draft.plan == nil ? "Save" : "Next"), size: .large) {
                focus = nil
                model.confirmIdentity(number: Int(numberText), note: note)
            }
            .disabled(problem != nil)
            ChimpButton(untranslated("Cancel"), kind: .link) { model.backHome() }
        }
    }
}

/// Étape 3 : « Starting money » (None, 50 XLM, un autre montant).
private struct PrepareMoneyStep: View {
    let model: PrepareCardsModel
    let draft: PrepareCardsModel.Draft
    @State private var isTypingAmount = false
    @State private var amountText = ""

    private var problem: String? { model.amountProblem(Int(amountText)) }
    private var lastChoice: Int? { model.lastStartingXLM }
    private var defaultXLM: Int { PrepareCardsModel.defaultStartingXLM }

    var body: some View {
        PrepareStepScreen(overline: "Step 3 of 4", title: "Starting money",
                          lead: "Test XLM sent from the admin key to the card's wallet, so its owner can send money right away.") {
            ChimpChoiceCard(title: untranslated("None"), detail: untranslated("The card's wallet stays empty."),
                            isHighlighted: lastChoice == nil && !isTypingAmount) {
                model.chooseStartingMoney(nil)
            }
            ChimpChoiceCard(title: untranslated("\(defaultXLM) XLM"), detail: untranslated("The usual amount (default)."),
                            isHighlighted: lastChoice == defaultXLM && !isTypingAmount) {
                model.chooseStartingMoney(defaultXLM)
            }
            ChimpChoiceCard(title: untranslated(anotherTitle), detail: untranslated("Between 1 and 1000 XLM."),
                            isHighlighted: isTypingAmount || isOtherAmount) {
                isTypingAmount = true
                if amountText.isEmpty, let lastChoice, lastChoice != defaultXLM { amountText = String(lastChoice) }
            }
            if isTypingAmount {
                ChimpInputField {
                    HStack {
                        TextField(text: $amountText) { Text(verbatim: "100") }
                            .keyboardType(.numberPad)
                            .chimpFont(.fieldM)
                        Text(verbatim: "XLM").chimpFont(.fieldM).foregroundStyle(.chimpTextSecondary)
                    }
                }
                if !amountText.isEmpty, let problem {
                    ChimpFieldMessage(text: untranslated(problem), kind: .error)
                }
            }
        } actions: {
            if isTypingAmount {
                ChimpButton(untranslated("Next"), size: .large) { model.chooseStartingMoney(Int(amountText)) }
                    .disabled(problem != nil)
            }
            ChimpButton(untranslated("Back"), kind: .link) { model.backToIdentity() }
        }
    }

    private var isOtherAmount: Bool { lastChoice != nil && lastChoice != defaultXLM }

    private var anotherTitle: String {
        if isOtherAmount, let lastChoice, !isTypingAmount { return "Another amount (last: \(lastChoice) XLM)" }
        return "Another amount"
    }
}

// MARK: - « See all cards »

/// La liste du journal : numéro, note, solde, statut ; export CSV.
struct PreparedCardsListView: View {
    let model: PrepareCardsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChimpSpacing.blockGap) {
                if model.cards.isEmpty {
                    Text(verbatim: "No card yet.").chimpFont(.body).foregroundStyle(.chimpTextSecondary)
                }
                ForEach(model.cards.sorted { $0.number < $1.number }) { card in
                    row(card)
                }
            }
            .padding(ChimpSpacing.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.chimpBackground))
        .navigationTitle(Text(verbatim: "All cards (\(model.cards.count))"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let file = csvFile() {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: file) { Text(verbatim: "Export CSV") }
                }
            }
        }
        .task { await model.loadAllBalances() }
        .refreshable {
            for card in model.cards { await model.loadBalance(of: card.wallet, force: true) }
        }
    }

    private func row(_ card: PreparedCard) -> some View {
        HStack(alignment: .top, spacing: ChimpSpacing.m) {
            VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
                HStack(spacing: ChimpSpacing.s) {
                    Text(verbatim: card.numberText).chimpFont(.mono).foregroundStyle(.chimpTextPrimary)
                    if let note = card.note {
                        Text(verbatim: note).chimpFont(.rowTitle).foregroundStyle(.chimpTextPrimary).lineLimit(1)
                    }
                }
                Text(verbatim: Self.status(card)).chimpFont(.caption)
                    .foregroundStyle(card.isDone && !card.needsFunding ? Color(.chimpPositive) : Color(.chimpNegative))
            }
            Spacer(minLength: ChimpSpacing.s)
            Text(verbatim: Self.balanceText(model.balances[card.wallet])).chimpFont(.mono).foregroundStyle(.chimpTextSecondary)
        }
        .padding(ChimpSpacing.ml)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))
        .accessibilityElement(children: .combine)
    }

    /// En langage simple, sans détail technique (le message d'erreur complet reste dans le CSV).
    static func status(_ card: PreparedCard) -> String {
        let state: String = switch card.status {
        case .prepared, .alreadyReady: "Ready"
        case .pending, .failed: "Not registered yet · tap it in Prepare a card to finish"
        }
        guard card.isDone else { return state }
        switch card.funding {
        case .funded: return "\(state) · \(card.fundingText) sent"
        case .failed: return "\(state) · test money not sent"
        case .declined, nil: return state
        }
    }

    static func balanceText(_ read: PrepareCardsModel.BalanceRead?) -> String {
        switch read {
        case .xlm(let amount): "\(amount.formatted(.number.precision(.fractionLength(0...2)))) XLM"
        case .failed: "unavailable"
        case .loading, nil: "…"
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

// MARK: - « Check a card »

/// « Check a card » : tap d'une carte (lecture seule), puis sa fiche en langage simple et une seule action,
/// « Send test money ».
struct CheckCardView: View {
    let model: PrepareCardsModel

    var body: some View {
        content
            .animation(.easeInOut(duration: 0.2), value: model.check)
            .background(Color(.chimpBackground))
            .navigationTitle(Text(verbatim: "Check a card"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .navigationBarBackButtonHidden(model.isChecking)
    }

    @ViewBuilder
    private var content: some View {
        switch model.check {
        case .idle, .reading, .checking, .failed:
            tap
        case .result(let result):
            sheet(result)
        }
    }

    private var tap: some View {
        PrepareStepScreen(overline: "Check a card", title: "Tap the card", lead: tapLead) {
            ChimpNFCRings(size: 220) { ChimpCardThumbnail(color: nil) }
                .frame(maxWidth: .infinity)
            if case .failed(let message) = model.check {
                ChimpNoticeBanner(text: untranslated("The card couldn't be read. Try again."), marker: .error)
                ChimpTechnicalDetails(details: message)
            }
        } actions: {
            ChimpButton(untranslated(model.isChecking ? "Reading…" : "Scan the card"), size: .large, isLoading: model.isChecking) {
                Task { await model.checkCard() }
            }
            .disabled(model.isChecking)
        }
    }

    private var tapLead: String {
        model.check == .checking
            ? "Looking the card up on Stellar testnet…"
            : "Hold the card flat on the top of the iPhone. Nothing is written on it."
    }

    private func sheet(_ result: PrepareCardsModel.CardCheck) -> some View {
        PrepareStepScreen(overline: "Check a card", title: Self.title(result), lead: Self.verdict(result.readiness)) {
            PrepareFacts(rows: rows(result))
            switch result.sent {
            case .sent(let xlm):
                ChimpNoticeBanner(text: untranslated("\(xlm) test XLM sent to this card's wallet."), marker: .success)
            case .failed(let message):
                ChimpNoticeBanner(text: untranslated("The test money wasn't sent. Try again."), marker: .error)
                ChimpTechnicalDetails(details: message)
            case nil:
                EmptyView()
            }
        } actions: {
            if result.canReceiveMoney {
                ChimpButton(untranslated("Send test money (\(PrepareCardsModel.defaultStartingXLM) XLM)"), size: .large,
                            isLoading: model.isSendingCheckMoney) {
                    Task { await model.sendTestMoneyToCheckedCard() }
                }
            }
            ChimpButton(untranslated("Check another card"), kind: result.canReceiveMoney ? .link : .primary,
                        size: result.canReceiveMoney ? .regular : .large) {
                model.resetCheck()
                Task { await model.checkCard() }
            }
            .disabled(model.isChecking)
        }
    }

    private func rows(_ result: PrepareCardsModel.CardCheck) -> [(String, String)] {
        var rows: [(String, String)] = [("Number", result.entry?.numberText ?? "Not in this iPhone's list")]
        if let note = result.entry?.note { rows.append(("Note", note)) }
        rows.append(("Ready", result.readiness == .ready ? "Yes" : "No"))
        if result.readiness == .ready, let wallet = result.wallet {
            rows.append(("Balance", PreparedCardsListView.balanceText(model.balances[wallet])))
        }
        return rows
    }

    static func title(_ result: PrepareCardsModel.CardCheck) -> String {
        result.entry.map { "Card \($0.numberText)" } ?? "This card"
    }

    static func verdict(_ readiness: PrepareCardsModel.CardCheck.Readiness) -> String {
        switch readiness {
        case .ready: "Ready to give away. Its owner creates an account by tapping it."
        case .notPrepared: "Not prepared yet. Use Prepare a card to finish it."
        case .blank: "Blank: it has no key yet. Use Prepare a card."
        case .hasPIN: "It already has a PIN, so someone is using it. It can't be prepared."
        case .otherChip(let name): "This is a \(name) card. Only Infineon cards are used here."
        }
    }
}

// MARK: - Mise en page commune

/// Un écran d'étape : surtitre, titre, phrase, contenu, puis les actions en bas.
struct PrepareStepScreen<Content: View, Actions: View>: View {
    let overline: String
    let title: String
    let lead: String
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChimpSpacing.sectionGap) {
                VStack(alignment: .leading, spacing: ChimpSpacing.s) {
                    Text(verbatim: overline).chimpFont(.overline).textCase(.uppercase).foregroundStyle(.chimpTextSecondary)
                    Text(verbatim: title).chimpFont(.displayL).foregroundStyle(.chimpTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: lead).chimpFont(.bodyL).foregroundStyle(.chimpTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: ChimpSpacing.blockGap) { content }
            }
            .padding(ChimpSpacing.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: ChimpSpacing.xs) { actions }
                .padding(.horizontal, ChimpSpacing.screenMargin)
                .padding(.top, ChimpSpacing.s)
                .padding(.bottom, ChimpSpacing.s)
                .background(Color(.chimpBackground))
        }
    }
}

/// La fiche d'une carte : libellé à gauche, valeur à droite.
struct PrepareFacts: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            ForEach(rows, id: \.0) { label, value in
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: label).chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
                    Spacer(minLength: ChimpSpacing.s)
                    Text(verbatim: value).chimpFont(.mono).foregroundStyle(.chimpTextPrimary).lineLimit(1).truncationMode(.middle)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(ChimpSpacing.lg + ChimpBorder.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface), shadow: .card)
    }
}

/// Le dessin donné aux cartes enregistrées ici (Chimp Admin, décision de Barth du 2026-11-16). Les dessins viennent de
/// la campagne elle-même : ce sont ceux déjà imprimés sur de vraies cartes. « No design » garde l'image par défaut.
///
/// Le dessin fait partie de ce que la carte signe : il est choisi **avant** le premier tap, et le changer refait la
/// préparation (une carte déjà enregistrée ne change jamais de dessin).
struct CardDesignPicker: View {
    let designs: [CardDesign]
    let isLoading: Bool
    @Binding var selection: CardDesign?

    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.s) {
            HStack {
                Text(untranslated("Design of the next cards"))
                    .chimpFont(.label)
                    .textCase(.uppercase)
                    .foregroundStyle(.chimpTextSecondary)
                    .accessibilityAddTraits(.isHeader)
                if isLoading { ProgressView().padding(.leading, ChimpSpacing.xs) }
            }
            if designs.isEmpty {
                Text(untranslated(isLoading ? "Reading the campaign…" : "No design on this campaign yet: cards keep the default image."))
                    .chimpFont(.captionS)
                    .foregroundStyle(.chimpTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ChimpSpacing.m) {
                        tile(nil, title: untranslated("No design"), subtitle: untranslated("Default image"))
                        ForEach(designs) { design in
                            tile(design, title: untranslated(design.name),
                                 subtitle: untranslated(design.count == 1 ? "1 card" : "\(design.count) cards"))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func tile(_ design: CardDesign?, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        let isSelected = selection?.uri == design?.uri
        return Button {
            selection = design
        } label: {
            VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
                Group {
                    if let image = design?.image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Color(.chimpSurfaceSecondary)
                            .overlay { Image(systemName: design == nil ? "square.slash" : "photo").foregroundStyle(.chimpTextSecondary) }
                    }
                }
                .frame(width: 132, height: 132 / ChimpSize.cardAspectRatio)
                .clipShape(RoundedRectangle(cornerRadius: ChimpRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: ChimpRadius.control)
                        .strokeBorder(isSelected ? Color(.chimpAccent) : Color(.chimpOutline), lineWidth: isSelected ? 4 : ChimpBorder.regular)
                }
                Text(title).chimpFont(.captionStrong).foregroundStyle(.chimpTextPrimary).lineLimit(1)
                Text(subtitle).chimpFont(.captionS).foregroundStyle(.chimpTextSecondary).lineLimit(1)
            }
            .frame(width: 132, alignment: .leading)
        }
        .buttonStyle(ChimpPressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
#endif
