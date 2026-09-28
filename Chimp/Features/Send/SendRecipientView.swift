import SwiftUI

/// C1 · « Who's it for? » : adresse collée ou tapée (vérifiée avec sa somme de contrôle), memo ID facultatif,
/// destinataires récents. Aucune carte demandée ici.
///
/// Pas de « Scan QR » ni de « Show their code » : il faut la clé caméra de l'Info.plist (jalon 4b, ROADMAP).
/// Pas de « name » ni de « handle » : la fédération (`maya*chimp.xyz`) est hors référence (DESIGN_NOTES §10, point 12).
struct SendRecipientView: View {
    @Bindable var model: SendFlowModel
    /// Bouton retour affiché seulement si une action est fournie.
    var onBack: (() -> Void)?

    @FocusState private var focusedField: Field?
    @Environment(\.chimpScreenInsets) private var screenInsets

    private enum Field {
        case address
        case memo
    }

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Who's it for?", step: 1, steps: 3, onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    addressField
                    addressMessage
                        .padding(.top, ChimpSpacing.s)
                    if model.acceptsMemoID {
                        memoField
                            .padding(.top, ChimpSpacing.l)
                    }
                    recents
                    ChimpySays(text: "No card needed yet. I'll only ask for it at the very end.", pose: .crawl)
                        .padding(.top, ChimpSpacing.xl)
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.top, ChimpSpacing.xl)
                .padding(.bottom, ChimpSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color(.chimpBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChimpButton("Next") {
                focusedField = nil
                model.continueFromRecipient()
            }
            .disabled(!model.canContinueFromRecipient)
            .padding(.horizontal, ChimpSpacing.bottomBar.leading)
            .padding(.top, ChimpSpacing.bottomBar.top)
            .padding(.bottom, screenInsets.hasHomeIndicator ? ChimpSpacing.bottomBar.bottom : ChimpSpacing.xl)
            .background(Color(.chimpBackground))
        }
        .task { await model.loadIfNeeded() }
        .navigationDestination(isPresented: $model.isAmountPresented) {
            SendAmountView(model: model)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Adresse

    private var addressField: some View {
        ChimpInputField {
            TextField(
                "Recipient's Stellar address",
                text: $model.addressText,
                prompt: Text("Their Stellar address").foregroundStyle(Color(.chimpTextSecondary)),
                axis: .vertical
            )
            .chimpFont(.monoValue)
            .lineLimit(1...3)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .submitLabel(.done)
            .focused($focusedField, equals: .address)
            .onChange(of: model.addressText) { _, newValue in
                // Champ multiligne : la touche Retour ajoute un saut de ligne, qu'on traite comme « Terminé ».
                if newValue.contains("\n") {
                    model.addressText = newValue.replacingOccurrences(of: "\n", with: "")
                    focusedField = nil
                }
            }
        } accessory: {
            if model.addressText.isEmpty {
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in
                        model.pasteAddress(text)
                        focusedField = nil
                    }
                }
                .labelStyle(.titleOnly)
                .buttonBorderShape(.capsule)
                .tint(Color(.chimpOutline))
            } else {
                Button {
                    model.addressText = ""
                    model.memoText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(.chimpTextSecondary)
                        .frame(minWidth: ChimpSize.minimumTouchTarget, minHeight: ChimpSize.minimumTouchTarget)
                }
                .accessibilityLabel(Text("Clear address"))
            }
        }
    }

    /// Erreur, ou confirmation de l'adresse reconnue. Pendant la frappe, une erreur n'apparaît qu'une fois
    /// l'adresse complète (56 caractères) ou le champ quitté, pour ne pas crier à chaque lettre.
    @ViewBuilder
    private var addressMessage: some View {
        switch model.recipientState {
        case .empty:
            ChimpFieldMessage(text: "Paste it from the app or exchange you're paying. Check the first and last characters.")
        case .invalid(let issue):
            if showsIssueWhileTyping(issue) {
                ChimpFieldMessage(text: message(for: issue), kind: .error)
            }
        case .valid(let recipient):
            ChimpFieldMessage(text: confirmation(for: recipient), kind: .success)
        }
    }

    private func showsIssueWhileTyping(_ issue: RecipientIssue) -> Bool {
        if focusedField != .address { return true }
        switch issue {
        case .secretKey, .federation, .ownDrawer:
            return true
        default:
            return StellarAddressParser.clean(model.addressText).count >= StellarAddressParser.standardLength
        }
    }

    private func message(for issue: RecipientIssue) -> LocalizedStringKey {
        switch issue {
        case .secretKey:
            "That's a secret key, not an address! Never share it with anyone. Delete it and ask for their address."
        case .federation:
            "Name*domain addresses aren't supported yet. Ask for their Stellar address: it starts with G, C or M."
        case .xrpl:
            "That's an XRP Ledger address. ChimpDAO only sends on Stellar."
        case .evm:
            "That's an Ethereum-style address. ChimpDAO only sends on Stellar."
        case .typo:
            "One character is off in this address. Copy it again from where you found it."
        case .wrongLength:
            "This address is incomplete. A Stellar address has 56 characters (69 with a memo ID). Copy it again."
        case .notStellar:
            "This isn't a Stellar address. It should start with G, C or M."
        case .ownDrawer(_, isMain: true):
            "That's your Main account. Use Move instead."
        case .ownDrawer(let name, isMain: false):
            "That's \(name). Use Move instead."
        }
    }

    private func confirmation(for recipient: StellarRecipient) -> LocalizedStringKey {
        switch recipient.kind {
        case .account:
            "Valid Stellar address"
        case .contract:
            "Valid Stellar address (smart wallet)"
        case .muxed:
            if let memoID = recipient.memoID {
                "Valid Stellar address. Includes memo ID \(String(memoID))"
            } else {
                "Valid Stellar address"
            }
        }
    }

    // MARK: Memo ID

    private var memoField: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.s) {
            Text("Memo ID · optional")
                .chimpFont(.label)
                .textCase(.uppercase)
                .foregroundStyle(.chimpTextSecondary)
                .accessibilityAddTraits(.isHeader)
            ChimpInputField {
                TextField(
                    "Memo ID, optional",
                    text: $model.memoText,
                    prompt: Text("Only if they gave you one").foregroundStyle(Color(.chimpTextSecondary))
                )
                .chimpFont(.monoValue)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .memo)
            }
            switch model.memoIDState {
            case nil:
                ChimpFieldMessage(text: "Exchanges often ask for one. Numbers only.")
            case .failure(.notANumber):
                ChimpFieldMessage(text: "Numbers only. A word memo can't be sent from ChimpDAO.", kind: .error)
            case .failure(.tooLarge):
                ChimpFieldMessage(text: "This number is too big for a memo ID.", kind: .error)
            case .success:
                ChimpFieldMessage(text: "The memo ID travels inside the address.", kind: .success)
            }
        }
    }

    // MARK: Récents

    @ViewBuilder
    private var recents: some View {
        if !model.recents.isEmpty {
            Text("Recent")
                .chimpFont(.label)
                .textCase(.uppercase)
                .foregroundStyle(.chimpTextSecondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, ChimpSpacing.sectionGap)
            VStack(spacing: ChimpSpacing.listGap) {
                ForEach(model.recents) { contact in
                    ChimpContactRow(
                        name: contact.name,
                        color: contact.color,
                        detail: StellarAddressParser.short(contact.address)
                    ) {
                        focusedField = nil
                        model.choose(contact)
                    }
                }
            }
            .padding(.top, ChimpSpacing.sm)
        }
    }
}

#Preview("Maquette") {
    NavigationStack {
        SendRecipientView(model: SendFlowModel(service: MockSendService()), onBack: {})
            .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview("Sans récents · sombre") {
    NavigationStack {
        SendRecipientView(model: SendFlowModel(service: MockSendService(dataScenario: .noRecents)), onBack: {})
            .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
