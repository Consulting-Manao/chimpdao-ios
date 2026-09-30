import SwiftUI

/// I2 · Settings (maquette) : prénom, nom et couleur des cartes, apparence, visite, « Disconnect this phone », « Erase
/// everything on this phone », liens (licences, aide), version. Les lignes de la maquette pas encore faisables (changer de
/// compte, paranoid mode, Face ID, devise, shop mode, raw signing) ne sont pas affichées : aucune ligne sans
/// destination. « Terms » et « Privacy » sont marqués « to add » tant que leurs URLs manquent (décision de Barth du
/// 2026-09-30). Pas de choix du réseau (décision du 2026-09-28). En Debug et Testing, une section « Developer » ouvre le
/// catalogue et le mode admin.
struct SettingsView: View {
    @Bindable var model: SettingsModel
    let onBack: () -> Void
    var onDeveloper: (() -> Void)?
    @State private var isShowingLicenses = false
    /// Carte dont on change le PIN.
    @State private var pinCard: PINCard?

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Settings", subtitle: "No card needed here", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("You")
                    you
                        .padding(.top, ChimpSpacing.s)

                    sectionLabel("Your cards")
                        .padding(.top, ChimpSpacing.sectionGap)
                    cards
                        .padding(.top, ChimpSpacing.s)
                    Text("Names and colours stay on this phone. Nothing is written on the card.")
                        .chimpFont(.caption)
                        .foregroundStyle(.chimpTextSecondary)
                        .padding(.top, ChimpSpacing.s)

                    if !model.pinCards.isEmpty {
                        // Maquette : « SAFETY » (paranoid mode et Face ID, masqués) ; on y range le changement de PIN.
                        sectionLabel("Safety")
                            .padding(.top, ChimpSpacing.sectionGap)
                        ChimpGroupedList(rows: model.pinCards.map { card in
                            ChimpGroupedRow(id: card.id, title: "Change PIN", value: card.name) { pinCard = card }
                        })
                        .padding(.top, ChimpSpacing.s)
                    }

                    sectionLabel("Display")
                        .padding(.top, ChimpSpacing.sectionGap)
                    ChimpGroupedBox {
                        ChimpSettingsControlRow(title: "Look") {
                            ChimpSegmentedPicker(segments: Self.lookSegments, selection: $model.look)
                        }
                    }
                    .padding(.top, ChimpSpacing.s)

                    sectionLabel("More")
                        .padding(.top, ChimpSpacing.sectionGap)
                    ChimpGroupedBox {
                        ChimpSettingsRow(title: "How ChimpDAO works", value: String(localized: "Replay the tour")) {
                            model.isReplayingTour = true
                        }
                    }
                    .padding(.top, ChimpSpacing.s)

                    if let onDeveloper {
                        sectionLabel("Developer")
                            .padding(.top, ChimpSpacing.sectionGap)
                        ChimpNavigationRow(title: "Design system and admin mode", subtitle: "Debug and Testing builds only", action: onDeveloper)
                            .padding(.top, ChimpSpacing.s)
                    }

                    ChimpButton("Disconnect this phone", kind: .destructive) { model.isConfirmingDisconnect = true }
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
        .padding(.vertical, ChimpSpacing.m + ChimpBorder.regular)
        .padding(.horizontal, 15 + ChimpBorder.regular)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))
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

    private var disconnectTitle: LocalizedStringKey {
        model.hasPendingPayment ? "Not yet" : "Disconnect this phone?"
    }

    private var disconnectMessage: LocalizedStringKey {
        model.hasPendingPayment
            ? "A payment is still being checked. Open Send to see how it ended, then you can disconnect."
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
