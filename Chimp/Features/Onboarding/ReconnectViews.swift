import SwiftUI

/// Reconnexion d'une Infineon avec PIN (écran absent de la maquette, textes proposés, DESIGN_NOTES §12) :
/// le PIN de la carte lue en A2, puis la feuille « Tap the same card again » : la carte vérifie le PIN (VERIFY PIN).
/// Rien n'est signé ni payé. Même enchaînement que l'ordre « tap puis PIN » d'Envoyer.
struct ReconnectPINView: View {
    @Bindable var model: ReconnectModel
    let onBack: () -> Void
    let onScan: () -> Void
    let onOtherCard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Your card's PIN", subtitle: "Card N°\(model.cardNumber)", onBack: model.isScanning ? nil : onBack)
            ChimpPinPad(pin: $model.pinEntry, length: ReconnectModel.pinLength, state: $model.pinState, onComplete: model.pinCompleted) {
                ChimpySays(text: chimpy, pose: .banana)
                    .padding(.top, ChimpSpacing.xl)
            }
            .disabled(model.isScanning)
            .padding(.horizontal, ChimpSpacing.lg)
            ChimpButton("Use another card", kind: .link, action: onOtherCard)
                .disabled(model.isScanning)
                .padding(.top, ChimpSpacing.s)
                .padding(.bottom, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
        .blocksSwipeBack(model.isScanning)
        .chimpSheet(
            isPresented: Binding(
                get: { model.isShowingTapSheet },
                set: { isPresented in if !isPresented { model.cancelTap() } }
            ),
            height: ChimpSize.cardTapSheetHeight,
            isDismissDisabled: model.isScanning
        ) {
            CardTapSheet(
                cardName: model.trimmedCardName,
                cardColor: model.cardColor,
                stepLabel: "Step 2 of 2 · Tap",
                title: "Tap the same card again",
                what: "Opening your account on this phone. Nothing is signed or moved.",
                who: "The card checks your PIN.",
                pinStatus: .ready,
                isScanning: model.isScanning,
                problem: model.tapProblem.map { CardReadingView.message(for: $0.kind) },
                problemDetails: model.tapProblem?.technicalDetails,
                onScan: onScan,
                onCancel: model.isScanning ? nil : { model.cancelTap() }
            )
        }
    }

    private var chimpy: LocalizedStringKey {
        switch model.pinState {
        case .blocked: "This card is locked. Try another card of your account."
        default: "Found your account! Type this card's PIN, then tap the card once more."
        }
    }
}

/// « Welcome back! » (écran absent de la maquette, décision de Barth du 2026-09-29, textes proposés) : le prénom, le nom
/// et la couleur de la carte ne sont gardés que sur le téléphone ; à la reconnexion, on redemande ceux qui manquent.
struct WelcomeBackView: View {
    @Bindable var model: ReconnectModel
    let onBack: () -> Void
    let onFinish: () -> Void
    @FocusState private var focusedField: Field?

    private enum Field { case firstName, cardName }

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Welcome back!", subtitle: "Your account is open again", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ChimpySays(text: "Your money never left your cards. Names stay on each phone, so tell me again.", pose: .banana)

                    if model.asksFirstName {
                        label("Your name")
                            .padding(.top, 28)
                        ChimpInputField {
                            TextField("Your name", text: $model.firstName, prompt: Text("Léo").foregroundStyle(Color(.chimpTextSecondary)))
                                .chimpFont(.fieldL)
                                .textContentType(.givenName)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.next)
                                .focused($focusedField, equals: .firstName)
                                .onSubmit { focusedField = model.asksCard ? .cardName : nil }
                        }
                        .padding(.top, ChimpSpacing.s)
                        if model.trimmedFirstName.count > AccountSetupModel.maximumFirstNameLength {
                            ChimpFieldMessage(text: "That's a bit long. \(AccountSetupModel.maximumFirstNameLength) characters at most.", kind: .error)
                                .padding(.top, ChimpSpacing.s)
                        }
                    }

                    if model.asksCard {
                        ChimpCard(
                            name: model.trimmedCardName.isEmpty ? String(localized: "Jungle") : model.trimmedCardName,
                            color: model.cardColor,
                            number: model.cardNumber
                        )
                        .frame(width: 210)
                        .frame(maxWidth: .infinity)
                        .animation(.easeInOut(duration: 0.2), value: model.cardColor)
                        .padding(.top, ChimpSpacing.xxl)

                        label("This card's name")
                            .padding(.top, ChimpSpacing.xl)
                        ChimpInputField {
                            TextField("Card name", text: $model.cardName, prompt: Text("Jungle").foregroundStyle(Color(.chimpTextSecondary)))
                                .chimpFont(.fieldM)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .focused($focusedField, equals: .cardName)
                        }
                        .padding(.top, ChimpSpacing.s)
                        if model.trimmedCardName.count > AccountSetupModel.maximumCardNameLength {
                            ChimpFieldMessage(text: "Keep it short: \(AccountSetupModel.maximumCardNameLength) characters at most.", kind: .error)
                                .padding(.top, ChimpSpacing.s)
                        }

                        label("Colour")
                            .padding(.top, ChimpSpacing.xl)
                        ChimpColorSwatchPicker(selection: $model.cardColor)
                            .padding(.top, ChimpSpacing.xs)
                    }

                    if let error = model.saveError {
                        VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
                            ChimpFieldMessage(text: "This phone couldn't save it. Try again.", kind: .error)
                            ChimpTechnicalDetails(details: error)
                        }
                        .padding(.top, ChimpSpacing.l)
                    }
                }
                .padding(.top, ChimpSpacing.xl)
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.bottom, ChimpSpacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            ChimpButton("Let's swing", action: onFinish)
                .disabled(!model.canSave)
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.top, ChimpSpacing.ml)
                .padding(.bottom, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
        .onAppear { focusedField = model.asksFirstName && model.firstName.isEmpty ? .firstName : nil }
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .chimpFont(.label)
            .textCase(.uppercase)
            .foregroundStyle(.chimpTextSecondary)
    }
}
