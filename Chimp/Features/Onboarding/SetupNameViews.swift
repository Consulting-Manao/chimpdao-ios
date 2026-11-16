import SwiftUI

/// A4 · Your name (étape 1 sur 3) : le prénom, gardé seulement sur le téléphone, pour dire bonjour.
struct YourNameView<Model: FirstNameEditing>: View {
    @Bindable var model: Model
    var step = 1
    var steps = 3
    let onBack: () -> Void
    let onContinue: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "What should I call you?", step: step, steps: steps, onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ChimpySays(text: "I'm Chimpy. And you are...?", pose: .head)
                    Text("Your name")
                        .chimpFont(.label)
                        .textCase(.uppercase)
                        .foregroundStyle(.chimpTextSecondary)
                        .padding(.top, 28)
                    ChimpInputField {
                        TextField("Your name", text: $model.firstName, prompt: Text("Léo").foregroundStyle(Color(.chimpTextSecondary)))
                            .chimpFont(.fieldL)
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.continue)
                            .focused($isFocused)
                            .onSubmit { if model.canContinueFromName { onContinue() } }
                    }
                    .padding(.top, ChimpSpacing.s)
                    Text("A first name or a nickname. It's only used to say hi, and you can change it in Settings.")
                        .chimpFont(.bodyM)
                        .lineSpacing(4)
                        .foregroundStyle(.chimpTextSecondary)
                        .padding(.top, ChimpSpacing.m)
                    if model.trimmedFirstName.count > AccountSetupModel.maximumFirstNameLength {
                        ChimpFieldMessage(text: "That's a bit long. \(AccountSetupModel.maximumFirstNameLength) characters at most.", kind: .error)
                            .padding(.top, ChimpSpacing.s)
                    }
                }
                .padding(.top, 26)
                .padding(.horizontal, ChimpSpacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            ChimpButton("Nice to meet you", action: onContinue)
                .disabled(!model.canContinueFromName)
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.top, ChimpSpacing.ml)
                .padding(.bottom, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
        .onAppear { isFocused = model.firstName.isEmpty }
    }
}

/// A5 · Name your card (étape 2 sur 3) : nom et couleur, données locales, affichés chaque fois qu'une carte est demandée.
struct NameYourCardView<Model: CardNaming>: View {
    @Bindable var model: Model
    /// G1b (ajout d'une carte) : « Name your new card » · « Before you let it in ».
    var title: LocalizedStringKey = "Name your card"
    var subtitle: LocalizedStringKey?
    var step = 2
    var steps = 3
    let onBack: () -> Void
    let onContinue: () -> Void
    @FocusState private var isFocused: Bool
    @Environment(\.chimpCardArtStore) private var artStore

    /// Le dessin du NFT de cette carte, s'il en a un en forme de carte : sans lui, l'écran ne propose que les couleurs.
    private var design: CardArt? { model.namedCardKey.flatMap { artStore?.art(forKey: $0.hex) } }

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: title, subtitle: subtitle, step: step, steps: steps, onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ChimpCard(
                        name: model.trimmedCardName.isEmpty ? String(localized: "Jungle") : model.trimmedCardName,
                        color: model.cardColor,
                        number: model.cardNumber,
                        amount: model.pocketIsEmpty == true ? Decimal(0).formatted(.currency(code: "USD").presentation(.narrow)) : nil,
                        subtitle: model.pocketIsEmpty == true ? "on card" : nil,
                        cardKey: model.usesCardDesign ? model.namedCardKey?.hex : nil
                    )
                    .frame(width: 250)
                    .frame(maxWidth: .infinity)
                    .animation(.easeInOut(duration: 0.2), value: model.cardColor)
                    .animation(.easeInOut(duration: 0.2), value: model.usesCardDesign)

                    Text("Name")
                        .chimpFont(.label)
                        .textCase(.uppercase)
                        .foregroundStyle(.chimpTextSecondary)
                        .padding(.top, ChimpSpacing.xxxl)
                    ChimpInputField {
                        TextField("Card name", text: $model.cardName, prompt: Text("Jungle").foregroundStyle(Color(.chimpTextSecondary)))
                            .chimpFont(.fieldM)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .focused($isFocused)
                    }
                    .padding(.top, ChimpSpacing.s)
                    if model.trimmedCardName.count > AccountSetupModel.maximumCardNameLength {
                        ChimpFieldMessage(text: "Keep it short: \(AccountSetupModel.maximumCardNameLength) characters at most.", kind: .error)
                            .padding(.top, ChimpSpacing.s)
                    }

                    Text(design == nil ? "Colour" : "Colour & design")
                        .chimpFont(.label)
                        .textCase(.uppercase)
                        .foregroundStyle(.chimpTextSecondary)
                        .padding(.top, ChimpSpacing.xl)
                    ChimpColorSwatchPicker(
                        selection: $model.cardColor, design: design,
                        designSelection: design == nil ? nil : $model.usesCardDesign
                    )
                    .padding(.top, ChimpSpacing.xs)

                    Text("You'll see this name every time the app asks for a card, so you always know which one to grab.")
                        .chimpFont(.bodyM)
                        .lineSpacing(4)
                        .foregroundStyle(.chimpTextSecondary)
                        .padding(.top, ChimpSpacing.lg)
                }
                .padding(.top, ChimpSpacing.xxl)
                .padding(.horizontal, ChimpSpacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            ChimpButton("Next", action: onContinue)
                .disabled(!model.canContinueFromCard)
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.top, ChimpSpacing.ml)
                .padding(.bottom, ChimpSpacing.l)
        }
        .background(Color(.chimpBackground))
        // Après la session NFC, jamais pendant : une lecture réseau qui ne bloque rien. La pastille apparaît si elle
        // aboutit, et l'écran reste celui d'avant si elle échoue.
        .task(id: model.namedCardKey?.hex) {
            guard let key = model.namedCardKey else { return }
            await artStore?.load(cards: [key])
        }
    }
}
