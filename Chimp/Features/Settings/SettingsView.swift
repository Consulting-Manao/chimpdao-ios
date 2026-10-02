import SwiftUI

/// I2 · Settings (maquette) : prénom, changement de compte (I6), nom et couleur des cartes, devise (I3), apparence,
/// réseau (affichage seulement), Face ID pour ouvrir l'app, visite, « Disconnect », « Erase everything on this phone », liens (licences, aide),
/// version. Les lignes de la maquette pas encore faisables (paranoid mode, shop mode, raw signing) ne sont pas affichées :
/// aucune ligne sans destination. « Terms » et « Privacy » sont marqués « to add » tant que leurs URLs manquent (décision
/// de Barth du 2026-09-30). « Network » montre le réseau de la configuration de build, jamais un interrupteur
/// (2026-09-30). En Debug et Testing, une section « Developer » ouvre le catalogue et le mode admin.
struct SettingsView: View {
    @Bindable var model: SettingsModel
    let onBack: () -> Void
    var onDeveloper: (() -> Void)?
    @State private var isShowingLicenses = false
    /// Carte dont on change le PIN.
    @State private var pinCard: PINCard?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppLock.self) private var lock
    /// L'activation de Face ID n'a pas abouti (pas de code sur l'iPhone, échec technique). Rien pour une annulation.
    @State private var lockProblem: (message: LocalizedStringKey, details: String?)?

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Settings", subtitle: "No card needed here", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("You")
                    ChimpGroupedBox {
                        you
                        ChimpSettingsRow(title: "Switch account", value: model.accountName) {
                            model.isShowingAccounts = true
                        }
                    }
                    .padding(.top, ChimpSpacing.s)

                    sectionLabel("Your cards")
                        .padding(.top, ChimpSpacing.sectionGap)
                    cards
                        .padding(.top, ChimpSpacing.s)
                    Text("Names and colours stay on this phone. Nothing is written on the card.")
                        .chimpFont(.caption)
                        .foregroundStyle(.chimpTextSecondary)
                        .padding(.top, ChimpSpacing.s)

                    // Maquette : « SAFETY » (paranoid mode masqué, session dédiée) ; on y range aussi le changement de PIN.
                    sectionLabel("Safety")
                        .padding(.top, ChimpSpacing.sectionGap)
                    ChimpGroupedBox {
                        faceIDRow
                        ForEach(model.pinCards) { card in
                            ChimpSettingsRow(title: "Change PIN", value: card.name) { pinCard = card }
                        }
                    }
                    .padding(.top, ChimpSpacing.s)
                    if let problem = lockProblem {
                        VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
                            ChimpFieldMessage(text: problem.message, kind: .error)
                            if let details = problem.details { ChimpTechnicalDetails(details: details) }
                        }
                        .padding(.top, ChimpSpacing.s)
                    }

                    sectionLabel("Display")
                        .padding(.top, ChimpSpacing.sectionGap)
                    ChimpGroupedBox {
                        ChimpSettingsRow(title: "Currency", value: model.currency.settingsValue) {
                            model.isChoosingCurrency = true
                        }
                        ChimpSettingsControlRow(title: "Look") {
                            ChimpSegmentedPicker(segments: Self.lookSegments, selection: $model.look)
                        }
                        soundsRow
                    }
                    .padding(.top, ChimpSpacing.s)

                    sectionLabel("More")
                        .padding(.top, ChimpSpacing.sectionGap)
                    ChimpGroupedBox {
                        ChimpSettingsControlRow(title: "Network") {
                            networkPicker
                        }
                        ChimpSettingsRow(title: "How ChimpDAO works", value: String(localized: "Replay the tour")) {
                            model.isReplayingTour = true
                        }
                    }
                    .padding(.top, ChimpSpacing.s)
                    if model.isShowingNetworkBubble {
                        ChimpySays(text: "Real bananas are coming soon!", pose: .banana)
                            .padding(.top, ChimpSpacing.m)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if let onDeveloper {
                        sectionLabel("Developer")
                            .padding(.top, ChimpSpacing.sectionGap)
                        ChimpNavigationRow(title: "Design system and admin mode", subtitle: "Debug and Testing builds only", action: onDeveloper)
                            .padding(.top, ChimpSpacing.s)
                    }

                    ChimpButton(disconnectButtonTitle, kind: .destructive) { model.isConfirmingDisconnect = true }
                        .padding(.top, ChimpSpacing.sectionGap)
                    Button { model.isConfirmingErase = true } label: {
                        Text("Erase everything on this phone")
                            .chimpFont(.link)
                            .foregroundStyle(.chimpNegative)
                            .frame(maxWidth: .infinity, minHeight: ChimpSize.minimumTouchTarget)
                    }
                    .buttonStyle(ChimpPressableStyle())
                    .padding(.top, ChimpSpacing.s)

                    if let error = model.saveError, !model.isEditingFirstName {
                        VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
                            ChimpFieldMessage(text: "This phone couldn't save it. Try again.", kind: .error)
                            ChimpTechnicalDetails(details: error)
                        }
                        .padding(.top, ChimpSpacing.m)
                    }

                    links
                        .padding(.top, ChimpSpacing.xxl)
                    footer
                        .padding(.top, ChimpSpacing.l)
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.vertical, ChimpSpacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(.chimpBackground))
        .alert(disconnectTitle, isPresented: $model.isConfirmingDisconnect) {
            if model.hasPendingPayment {
                Button("OK", role: .cancel) {}
            } else {
                Button("Disconnect", role: .destructive, action: model.disconnect)
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text(disconnectMessage)
        }
        .alert(eraseTitle, isPresented: $model.isConfirmingErase) {
            if model.hasPendingPayment {
                Button("OK", role: .cancel) {}
            } else {
                Button("Erase", role: .destructive, action: model.eraseEverything)
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text(eraseMessage)
        }
        .chimpSheet(isPresented: $model.isShowingAccounts, height: 600, onDismiss: model.accountsSheetDismissed) {
            AccountsSheet(model: model)
                .task { await model.loadAccountSummaries() }
        }
        .fullScreenCover(isPresented: $model.isAddingAccount) {
            AddAccountFlow(model: model.makeAddAccountModel()) { model.isAddingAccount = false }
        }
        .alert("Not yet", isPresented: $model.isShowingPendingNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A payment is still being checked. Open Send to see how it ended, then you can switch accounts.")
        }
        .fullScreenCover(isPresented: $model.isReplayingTour) {
            TourReplayView { model.isReplayingTour = false }
        }
        .navigationDestination(item: $pinCard) { card in
            ChangePINScreen(card: card) { pinCard = nil }
        }
        .navigationDestination(isPresented: $isShowingLicenses) {
            LicensesView { isShowingLicenses = false }
                .toolbar(.hidden, for: .navigationBar)
        }
        .chimpSheet(isPresented: $model.isEditingFirstName, height: 380) {
            firstNameSheet
        }
        .chimpSheet(isPresented: $model.isChoosingCurrency, height: 500, fitsContent: true) {
            CurrencySheet(selection: model.currency, onChoose: model.choose)
        }
        .navigationDestination(item: Binding(
            get: { model.editingCard },
            set: { if $0 == nil { model.cancelEditing() } }
        )) { _ in
            CardRenameView(model: model)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Sections

    /// « Look » : la maquette montre Yellow banana et Jungle night ; « Auto » (comme l'iPhone, par défaut) est ajouté en
    /// premier (décision de Barth du 2026-09-30).
    static let lookSegments: [ChimpSegment<ChimpLook>] = [
        ChimpSegment(value: .auto, title: "Auto", accessibilityTitle: "Same as my iPhone"),
        ChimpSegment(value: .yellowBanana, title: "Yellow banana"),
        ChimpSegment(value: .jungleNight, title: "Jungle night"),
    ]

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .chimpFont(.label)
            .textCase(.uppercase)
            .foregroundStyle(.chimpTextSecondary)
            .accessibilityAddTraits(.isHeader)
    }

    private var you: some View {
        HStack(spacing: ChimpSpacing.m) {
            Image(.tileHead)
                .resizable()
                .scaledToFit()
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Chimpy calls you")
                    .chimpFont(.captionS)
                    .foregroundStyle(.chimpTextSecondary)
                Text(verbatim: model.firstName ?? "—")
                    .chimpFont(.rowTitle)
                    .foregroundStyle(.chimpTextPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ChimpPillButton("Edit", action: model.editFirstName)
        }
        .padding(.vertical, ChimpSpacing.m)
        .padding(.horizontal, 15)
        .accessibilityElement(children: .combine)
    }

    private var cards: some View {
        VStack(spacing: ChimpSpacing.listGap) {
            ForEach(model.cards) { card in
                Button { model.edit(card) } label: {
                    HStack(spacing: ChimpSpacing.m) {
                        ChimpDrawerIconView(icon: .card(card.color), size: CGSize(width: 34, height: 24), cornerRadius: 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: card.displayName)
                                .chimpFont(.rowTitle)
                                .foregroundStyle(.chimpTextPrimary)
                            Text("N°\(card.number) · Rename & colour")
                                .chimpFont(.captionS)
                                .foregroundStyle(.chimpTextSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(.chimpTextSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, ChimpSpacing.m + ChimpBorder.regular)
                    .padding(.horizontal, 15 + ChimpBorder.regular)
                    .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))
                    .contentShape(RoundedRectangle(cornerRadius: ChimpRadius.control))
                }
                .buttonStyle(ChimpPressableStyle())
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: ChimpSpacing.s) {
            Image(.tileBanana)
                .resizable()
                .scaledToFit()
                .frame(width: 26)
                .accessibilityHidden(true)
            Text("ChimpDAO \(SettingsModel.versionText) · made with bananas")
                .chimpFont(.caption)
                .foregroundStyle(.chimpTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Face ID

    /// « Face ID to open the app » (I2) : activer demande un Face ID réussi ; désactiver est immédiat (l'app est ouverte).
    private var faceIDRow: some View {
        Toggle(isOn: Binding(
            get: { lock.isEnabled },
            set: { isOn in
                lockProblem = nil
                if isOn {
                    Task {
                        switch await lock.enable() {
                        case .enabled, .cancelled: break
                        case .needsPasscode: lockProblem = ("Set a passcode on your iPhone first.", nil)
                        case .failed(let details): lockProblem = ("Face ID didn't work. Try again.", details)
                        }
                    }
                } else if let details = lock.disable() {
                    lockProblem = ("This phone couldn't save it. Try again.", details)
                }
            }
        )) {
            Text(verbatim: Self.lockTitle(lock.kind))
                .chimpFont(.rowTitle)
                .foregroundStyle(.chimpTextPrimary)
        }
        .toggleStyle(ChimpToggleStyle())
        .disabled(lock.isAuthenticating)
        .padding(.vertical, 11)
        .padding(.horizontal, 15)
        .frame(minHeight: ChimpSize.minimumTouchTarget)
    }

    /// « Sounds » : la tête de Chimpy, à gauche, fait office d'interrupteur (singe joyeux : activés ; singe « chut » : coupés). Toute
    /// la ligne se touche. Pour VoiceOver, c'est un interrupteur : « Sounds, activé ». Le bouton silencieux de l'iPhone
    /// coupe aussi les sons.
    private var soundsRow: some View {
        Button {
            model.soundsEnabled.toggle()
        } label: {
            HStack(spacing: ChimpSpacing.m) {
                ChimpSoundHead(isOn: model.soundsEnabled)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sounds")
                        .chimpFont(.rowTitle)
                        .foregroundStyle(.chimpTextPrimary)
                    Text(model.soundsEnabled ? "On · muted when your iPhone is on silent" : "Off")
                        .chimpFont(.captionS)
                        .foregroundStyle(.chimpTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, ChimpSpacing.s)
            .padding(.horizontal, 15)
            .frame(minHeight: ChimpSize.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChimpPressableStyle())
        .sensoryFeedback(.selection, trigger: model.soundsEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sounds"))
        .accessibilityValue(model.soundsEnabled ? Text("On") : Text("Off"))
        .accessibilityHint(Text("Muted when your iPhone is on silent"))
        .accessibilityAddTraits(.isToggle)
    }

    /// Libellé selon l'iPhone (maquette : « Face ID to open the app »).
    static func lockTitle(_ kind: DeviceLockKind) -> String {
        switch kind {
        case .faceID, .unavailable: String(localized: "Face ID to open the app")
        case .touchID: String(localized: "Touch ID to open the app")
        case .opticID: String(localized: "Optic ID to open the app")
        case .passcode: String(localized: "Passcode to open the app")
        }
    }

    // MARK: Network

    /// Affichage seulement : le segment choisi est toujours le réseau de l'app. Un segment grisé ne change rien, il
    /// montre la bulle de Chimpy quelques secondes.
    private var networkPicker: some View {
        let row = model.networkRow
        return ChimpSegmentedPicker(
            segments: row.options.map { network in
                ChimpSegment(
                    value: network,
                    title: LocalizedStringKey(network.shortName),
                    isEnabled: !row.comingSoon.contains(network),
                    lockedHint: row.comingSoon.contains(network) ? "Coming soon" : nil
                )
            },
            selection: .constant(row.current),
            onDisabledTap: { _ in showNetworkBubble() }
        )
        .task(id: model.isShowingNetworkBubble) {
            guard model.isShowingNetworkBubble else { return }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { model.isShowingNetworkBubble = false }
        }
    }

    private func showNetworkBubble() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { model.isShowingNetworkBubble = true }
        AccessibilityNotification.Announcement(String(localized: "Real bananas are coming soon!")).post()
    }

    // MARK: Liens (maquette : « Terms Privacy Licenses Help »)

    private var links: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ChimpSpacing.l) { linkItems }
            VStack(spacing: ChimpSpacing.s) { linkItems }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var linkItems: some View {
        // TODO(avant l'App Store et les testeurs externes) : URLs des conditions et de la politique de confidentialité.
        toAdd("Terms")
        toAdd("Privacy")
        Button { isShowingLicenses = true } label: { linkLabel("Licenses") }
            .buttonStyle(ChimpPressableStyle())
        if let help = SettingsModel.helpURL {
            Link(destination: help) { linkLabel("Help") }
                .accessibilityHint(Text("Writes an email to \(SettingsModel.helpEmail)"))
        }
    }

    private func linkLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .chimpFont(.buttonSmall)
            .underline()
            .foregroundStyle(.chimpTextPrimary)
            .frame(minHeight: ChimpSize.minimumTouchTarget)
    }

    /// Lien prévu dont l'URL manque encore : affiché pour qu'on y pense, pas un bouton.
    private func toAdd(_ title: LocalizedStringKey) -> some View {
        (Text(title) + Text(verbatim: " · ") + Text("to add"))
            .chimpFont(.captionS)
            .foregroundStyle(.chimpTextSecondary)
            .frame(minHeight: ChimpSize.minimumTouchTarget)
    }

    // MARK: Disconnect this phone

    /// « Disconnect this phone » avec un seul compte ; « Disconnect Léo's account » s'il y en a plusieurs (décision de
    /// Barth du 2026-09-30 : le libellé dit ce qu'il fait).
    private var disconnectButtonTitle: LocalizedStringKey {
        Self.disconnectTitle(severalAccounts: model.hasSeveralAccounts, firstName: model.firstName)
    }

    static func disconnectTitle(severalAccounts: Bool, firstName: String?, asQuestion: Bool = false) -> LocalizedStringKey {
        guard severalAccounts else { return asQuestion ? "Disconnect this phone?" : "Disconnect this phone" }
        guard let firstName, !firstName.isEmpty else { return asQuestion ? "Disconnect this account?" : "Disconnect this account" }
        return asQuestion ? "Disconnect \(firstName)'s account?" : "Disconnect \(firstName)'s account"
    }

    private var disconnectTitle: LocalizedStringKey {
        if model.hasPendingPayment { return "Not yet" }
        return Self.disconnectTitle(severalAccounts: model.hasSeveralAccounts, firstName: model.firstName, asQuestion: true)
    }

    private var disconnectMessage: LocalizedStringKey {
        if model.hasPendingPayment {
            return "A payment is still being checked. Open Send to see how it ended, then you can disconnect."
        }
        return model.hasSeveralAccounts
            ? "I only close this account on this phone. Your money stays on its cards, promise. Your other accounts stay open. Tap any card of this account to come back."
            : "I only close your account on this phone. Your money stays on your cards, promise. Tap any card of your account to come back."
    }

    // MARK: Erase everything on this phone

    private var eraseTitle: LocalizedStringKey {
        model.hasPendingPayment ? "Not yet" : "Erase everything on this phone?"
    }

    private var eraseMessage: LocalizedStringKey {
        model.hasPendingPayment
            ? "A payment is still being checked. Open Send to see how it ended, then you can erase."
            : "Your account, names, colours and history leave this phone, for good. Your money stays on your cards. To come back, tap a card of your account. A card that was added to an account may need one of the account's other cards to find it again."
    }

    // MARK: Prénom

    private var firstNameSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What should I call you?")
                .chimpFont(.sheetTitle)
                .foregroundStyle(.chimpTextPrimary)
                .accessibilityAddTraits(.isHeader)
            ChimpInputField {
                TextField("Your name", text: $model.editedFirstName, prompt: Text("Léo").foregroundStyle(Color(.chimpTextSecondary)))
                    .chimpFont(.fieldL)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(model.saveFirstName)
            }
            .padding(.top, ChimpSpacing.l)
            if model.trimmedFirstName.count > SettingsModel.maximumFirstNameLength {
                ChimpFieldMessage(text: "That's a bit long. \(SettingsModel.maximumFirstNameLength) characters at most.", kind: .error)
                    .padding(.top, ChimpSpacing.s)
            }
            if model.saveError != nil {
                ChimpFieldMessage(text: "This phone couldn't save it. Try again.", kind: .error)
                    .padding(.top, ChimpSpacing.s)
            }
            Spacer(minLength: ChimpSpacing.l)
            ChimpButton("Save", action: model.saveFirstName)
                .disabled(!model.canSaveFirstName)
        }
        .padding(.horizontal, ChimpSpacing.xxl)
        .padding(.bottom, ChimpSpacing.l)
    }
}

/// I6 · Switch account (maquette) : les comptes ouverts sur ce téléphone, « + Add an account · tap one of its cards »,
/// bulle de Chimpy et « Disconnect ». Passer à un autre compte ne demande aucune carte.
struct AccountsSheet: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Switch account")
                .chimpFont(.sheetTitle)
                .foregroundStyle(.chimpTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Each account has its own Main and its own cards.")
                .chimpFont(.bodyM)
                .foregroundStyle(.chimpTextSecondary)
                .padding(.top, ChimpSpacing.xxs)
            ScrollView {
                VStack(spacing: ChimpSpacing.listGap) {
                    ForEach(model.accountRows) { row in
                        accountRow(row)
                    }
                    Button(action: model.addAccount) {
                        Text("+ Add an account · tap one of its cards")
                            .chimpFont(.buttonSmall)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.chimpTextSecondary)
                            .frame(maxWidth: .infinity, minHeight: ChimpSize.minimumTouchTarget)
                            .padding(.horizontal, ChimpSpacing.ml)
                            .padding(.vertical, ChimpSpacing.xxs)
                            .overlay(
                                RoundedRectangle(cornerRadius: ChimpRadius.control)
                                    .strokeBorder(Color(.chimpTextSecondary), style: StrokeStyle(lineWidth: ChimpBorder.regular, dash: [8, 6]))
                            )
                            .contentShape(RoundedRectangle(cornerRadius: ChimpRadius.control))
                    }
                    .buttonStyle(ChimpPressableStyle())
                }
                .padding(.top, ChimpSpacing.ml)
                .padding(.bottom, ChimpSpacing.m)
            }
            .scrollBounceBehavior(.basedOnSize)
            ChimpySays(text: "I only forget this phone. Your money stays on your cards, promise.", pose: .unsure)
            ChimpButton(disconnectTitle, kind: .destructive, action: model.disconnectFromAccounts)
            .padding(.top, ChimpSpacing.m)
            .padding(.bottom, ChimpSpacing.l)
        }
        .padding(.horizontal, ChimpSpacing.xxl)
    }

    private var disconnectTitle: LocalizedStringKey {
        SettingsView.disconnectTitle(severalAccounts: model.hasSeveralAccounts, firstName: model.firstName)
    }

    private func accountRow(_ row: SettingsModel.AccountRow) -> some View {
        let shape = RoundedRectangle(cornerRadius: ChimpRadius.control)
        return Button { model.switchAccount(to: row.id) } label: {
            HStack(spacing: ChimpSpacing.m) {
                Image(.tileHead)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: row.name)
                        .chimpFont(.optionTitle)
                    Text(verbatim: Self.detail(row))
                        .chimpFont(.captionS)
                        .foregroundStyle(row.isCurrent ? Color(.chimpOnAccent) : Color(.chimpTextSecondary))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ChimpRadio(isSelected: row.isCurrent)
            }
            .foregroundStyle(row.isCurrent ? Color(.chimpOnAccent) : Color(.chimpTextPrimary))
            .padding(.vertical, 12 + ChimpBorder.regular)
            .padding(.horizontal, ChimpSpacing.ml + ChimpBorder.regular)
        }
        .buttonStyle(ChimpSurfaceButtonStyle(
            shape: shape,
            fill: row.isCurrent ? Color(.chimpAccent) : Color(.chimpSurface),
            shadow: row.isCurrent ? .tile : ChimpShadow(x: 0, y: 0)
        ))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    /// « 3 cards · $1,485.00 », ou le nombre de cartes seul tant que le total n'est pas lu.
    static func detail(_ row: SettingsModel.AccountRow) -> String {
        let cards = row.cardCount == 1 ? String(localized: "1 card") : String(localized: "\(row.cardCount) cards")
        guard let total = row.total else { return cards }
        return "\(cards) · \(total)"
    }
}

/// I3 · Currency (maquette) : « Show amounts in ». La devise ne change que l'affichage du Wallet et des pages de tiroir ;
/// l'Activity, Envoyer et les montants signés gardent les actifs réellement bougés.
struct CurrencySheet: View {
    let selection: DisplayCurrency
    let onChoose: (DisplayCurrency) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Show amounts in")
                .chimpFont(.sheetTitle)
                .foregroundStyle(.chimpTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Only changes how numbers look. Your coins stay the same.")
                .chimpFont(.bodyM)
                .foregroundStyle(.chimpTextSecondary)
                .padding(.top, ChimpSpacing.xxs)
            // La feuille s'ajuste à la liste et fait elle-même défiler aux grandes tailles de texte.
            ChimpGroupedBox {
                ForEach(DisplayCurrency.allCases) { currency in
                    ChimpChoiceListRow(badge: currency.badge, title: currency.title, isSelected: currency == selection) {
                        onChoose(currency)
                    }
                }
            }
            .padding(.top, ChimpSpacing.ml)
        }
        .padding(.horizontal, ChimpSpacing.xxl)
    }
}

/// « Rename & colour » (lien de B3 dans la maquette, écran non dessiné) : même mise en page qu'A5.
struct CardRenameView: View {
    @Bindable var model: SettingsModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Rename & colour", subtitle: subtitle, onBack: model.cancelEditing)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ChimpCard(
                        name: model.trimmedName.isEmpty ? String(localized: "Jungle") : model.trimmedName,
                        color: model.editedColor,
                        number: model.editingCard?.number ?? "····"
                    )
                    .frame(width: 250)
                    .frame(maxWidth: .infinity)
                    .animation(.easeInOut(duration: 0.2), value: model.editedColor)

                    Text("Name")
                        .chimpFont(.label)
                        .textCase(.uppercase)
                        .foregroundStyle(.chimpTextSecondary)
                        .padding(.top, ChimpSpacing.xxxl)
                    ChimpInputField {
                        TextField("Card name", text: $model.editedName, prompt: Text("Jungle").foregroundStyle(Color(.chimpTextSecondary)))
                            .chimpFont(.fieldM)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .focused($isFocused)
                    }
                    .padding(.top, ChimpSpacing.s)
                    if model.trimmedName.count > SettingsModel.maximumCardNameLength {
                        ChimpFieldMessage(text: "Keep it short: \(SettingsModel.maximumCardNameLength) characters at most.", kind: .error)
                            .padding(.top, ChimpSpacing.s)
                    }

                    Text("Colour")
                        .chimpFont(.label)
                        .textCase(.uppercase)
                        .foregroundStyle(.chimpTextSecondary)
                        .padding(.top, ChimpSpacing.xl)
                    ChimpColorSwatchPicker(selection: $model.editedColor)
                        .padding(.top, ChimpSpacing.xs)

                    Text("You'll see this name every time the app asks for a card, so you always know which one to grab. It stays on this phone.")
                        .chimpFont(.bodyM)
                        .lineSpacing(4)
                        .foregroundStyle(.chimpTextSecondary)
                        .padding(.top, ChimpSpacing.lg)

                    if let error = model.saveError {
                        VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
                            ChimpFieldMessage(text: "This phone couldn't save it. Try again.", kind: .error)
                            ChimpTechnicalDetails(details: error)
                        }
                        .padding(.top, ChimpSpacing.m)
                    }
                }
                .padding(.top, ChimpSpacing.xxl)
                .padding(.horizontal, ChimpSpacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            ChimpButton("Save") { model.saveCard() }
                .disabled(!model.canSaveCard)
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.top, ChimpSpacing.ml)
                .padding(.bottom, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
    }

    private var subtitle: LocalizedStringKey? {
        guard let card = model.editingCard else { return nil }
        return "Card N°\(card.number)"
    }
}
