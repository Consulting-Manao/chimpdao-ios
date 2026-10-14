import SwiftUI
import UIKit

/// C1 · « Who's it for? » : adresse collée ou tapée (vérifiée avec sa somme de contrôle), memo ID facultatif,
/// destinataires récents. Aucune carte demandée ici.
///
/// « Scan QR » (maquette) : la caméra lit une adresse ou un lien de paiement SEP-7 (`ScannedCodeParser`). Pas de
/// « Show their code » pour l'instant. Pas de « name » ni de « handle » : la fédération (`maya*chimp.xyz`) est hors référence (DESIGN_NOTES §10, point 12).
struct SendRecipientView: View {
    @Bindable var model: SendFlowModel
    /// Bouton retour affiché seulement si une action est fournie.
    var onBack: (() -> Void)?

    @FocusState private var focusedField: Field?
    /// Bulle de Chimpy tirée au hasard (`ChimpyLines.recipientTips`).
    @State private var seed = ChimpyLines.seed()
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
                    if model.isSendingBack {
                        // « Send back » : l'expéditeur peut être un exchange, qui ne reconnaîtrait pas l'argent renvoyé.
                        ChimpySays(
                            text: "Sending back to where it came from. If it came from an exchange, it may not reach anyone: check with them first.",
                            pose: .teacher
                        )
                        .padding(.top, ChimpSpacing.m)
                    }
                    if model.acceptsMemoID {
                        memoField
                            .padding(.top, ChimpSpacing.l)
                    }
                    recents
                    // En « Send back », une seule bulle : l'avertissement ci-dessus (retour de Barth, 2026-10-14).
                    if !model.isSendingBack {
                        ChimpySays(line: ChimpyLines.pick(ChimpyLines.recipientTips, seed: seed), pose: tipPose)
                            .padding(.top, ChimpSpacing.xl)
                    }
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
        .chimpSound(.error, trigger: model.scanIssue) { _, new in new != nil }
        .fullScreenCover(isPresented: $model.isScannerPresented) {
            QRScannerScreen(onCode: model.scanned) { model.isScannerPresented = false }
        }
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
                HStack(spacing: ChimpSpacing.xs) {
                    pasteButton
                    scanButton
                }
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

    /// « Paste » : pastille claire, même forme que « Scan QR » (retour de Barth du 2026-10-14 : le `PasteButton` d'iOS, gris
    /// et en police système, jurait). Lire le presse-papiers soi-même fait afficher par iOS sa demande d'autorisation.
    private var pasteButton: some View {
        Button {
            guard let text = UIPasteboard.general.string else { return }
            model.pasteAddress(text)
            focusedField = nil
        } label: {
            Text("Paste")
                .chimpFont(.buttonSmall)
                .foregroundStyle(.chimpTextPrimary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.chimpSurface)))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin) }
                .frame(minHeight: ChimpSize.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(ChimpPressableStyle())
        .accessibilityLabel(Text("Paste the address"))
    }

    /// « Scan QR » de la maquette : petite pastille jaune dans le champ.
    private var scanButton: some View {
        Button {
            focusedField = nil
            model.isScannerPresented = true
        } label: {
            Text("Scan QR")
                .chimpFont(.buttonSmall)
                .foregroundStyle(.chimpOnAccent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.chimpAccent)))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin) }
                .frame(minHeight: ChimpSize.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(ChimpPressableStyle())
        .accessibilityLabel(Text("Scan a QR code"))
    }

    /// Erreur, ou confirmation de l'adresse reconnue. Pendant la frappe, une erreur n'apparaît qu'une fois
    /// l'adresse complète (56 caractères) ou le champ quitté, pour ne pas crier à chaque lettre.
    @ViewBuilder
    private var addressMessage: some View {
        if let issue = model.scanIssue {
            ChimpFieldMessage(text: Self.message(for: issue, network: model.scanRules), kind: .error)
        } else {
            recipientMessage
        }
    }

    @ViewBuilder
    private var recipientMessage: some View {
        switch model.recipientState {
        case .empty:
            ChimpFieldMessage(text: "Paste it from the app or exchange you're paying. Check the first and last characters.")
        case .invalid(let issue):
            if showsIssueWhileTyping(issue) {
                ChimpFieldMessage(text: Self.message(for: issue), kind: .error)
            }
        case .valid(let recipient):
            ChimpFieldMessage(text: confirmation(for: recipient), kind: .success)
        }
    }

    /// Bulle du bas : le professeur donne son conseil ; il sort le bâton quand l'adresse ou le code est refusé.
    private var tipPose: ChimpyPose {
        if model.scanIssue != nil { return .stick }
        if case .invalid(let issue) = model.recipientState, showsIssueWhileTyping(issue) { return .stick }
        return .teacher
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

    /// Code QR refusé (textes proposés le 2026-10-01).
    static func message(for issue: ScanIssue, network rules: ScanRules) -> LocalizedStringKey {
        switch issue {
        case .address(let issue): message(for: issue)
        case .signRequest: "This code asks to sign something. ChimpDAO only reads addresses from codes."
        case .callback: "This code wants to hand the payment to a website. ChimpDAO only pays addresses directly."
        case .otherNetwork: rules.isPublicNetwork
            ? "This code is for another Stellar network. Ask for a Stellar address."
            : "This code is for another Stellar network. Ask for a Stellar Testnet address."
        case .wordMemo: "This code needs a word memo. A word memo can't be sent from ChimpDAO."
        case .conflictingMemo: "This code has two different memos. Ask for a new code."
        case .unsupportedAsset(let code): "This code asks for \(code). ChimpDAO sends XLM and USDC only."
        case .notAPaymentCode: "That code isn't a Stellar address."
        }
    }

    static func message(for issue: RecipientIssue) -> LocalizedStringKey {
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
                ForEach(Array(model.recents.enumerated()), id: \.element.id) { index, contact in
                    ChimpContactRow(
                        name: contact.name,
                        color: contact.color,
                        detail: StellarAddressParser.short(contact.address)
                    ) {
                        focusedField = nil
                        model.choose(contact)
                    }
                    .chimpCascadeAppear(index: index)
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
