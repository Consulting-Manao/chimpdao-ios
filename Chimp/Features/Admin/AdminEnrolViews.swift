#if CHIMP_ADMIN
import SwiftUI
import UIKit

/// Clé admin : saisie (champ sécurisé), adresse G affichée, bouton pour l'effacer.
/// La clé secrète n'est jamais affichée ni gardée dans l'état de l'écran après l'enregistrement.
struct AdminKeyPanel: View {
    @Bindable var model: AdminKeyModel
    @State private var input = ""
    @State private var isConfirmingErase = false

    var body: some View {
        AdminPanel(title: "Admin key (testnet)") {
            if let publicKey = model.publicKey {
                Text(verbatim: "Stored in this iPhone's keychain only (no iCloud sync). Signs and pays the enrolment.")
                    .chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
                AdminValue(label: "Admin address", value: publicKey)
                if model.isUnexpectedAdmin {
                    Text(verbatim: "Warning: this is not the contracts' admin (\(model.expectedAdmin)). mint will be refused.")
                        .chimpFont(.caption).foregroundStyle(Color(.chimpNegative))
                }
                ChimpButton(untranslated("Erase the admin key…"), kind: .destructive, size: .compact) {
                    isConfirmingErase = true
                }
            } else {
                Text(verbatim: "Type the testnet admin secret key (S…). It stays in this iPhone's keychain, never in the code, git or logs.")
                    .chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
                SecureField(text: $input) { Text(verbatim: "S…") }
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textContentType(.none)
                    .chimpFont(.address)
                    .padding(ChimpSpacing.m)
                    .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpBackground), border: ChimpBorder.thin)
                ChimpButton(untranslated("Save the admin key"), kind: .secondary, size: .compact) {
                    model.save(input)
                    input = ""
                }
                .disabled(input.isEmpty)
            }
            if let error = model.errorMessage {
                Text(verbatim: error).chimpFont(.caption).foregroundStyle(Color(.chimpNegative))
            }
        }
        .confirmationDialog(Text(verbatim: "Erase the admin key from this iPhone?"), isPresented: $isConfirmingErase, titleVisibility: .visible) {
            Button(role: .destructive) { model.erase() } label: { Text(verbatim: "Erase") }
            Button(role: .cancel) {} label: { Text(verbatim: "Cancel") }
        }
    }
}

/// Enregistrement de la carte lue : vérification sur testnet, ce que la carte va signer, tap 2, résultat.
struct AdminEnrolPanel: View {
    let card: ChipKeyInfo
    @Bindable var model: AdminEnrolModel
    let hasAdminKey: Bool
    @State private var pin = ""

    var body: some View {
        switch model.state {
        case .idle:
            AdminPanel(title: "Enrol on testnet") {
                if hasAdminKey {
                    Text(verbatim: "Reads this card's state on Stellar Testnet. Nothing is written yet.")
                        .chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
                    ChimpButton(untranslated("Check this card on testnet"), kind: .secondary, size: .compact) {
                        Task { await model.check(card) }
                    }
                } else {
                    Text(verbatim: "Enter the admin key above first.").chimpFont(.body)
                }
            }
        case .checking:
            AdminPanel(title: "Checking on testnet…") {
                Text(verbatim: "Reading the card's pocket, token and nonce.").chimpFont(.body)
            }
        case .alreadyEnrolled(let tokenID, let pocket):
            AdminPanel(title: "Already enrolled") {
                Text(verbatim: "This card already has its token. Nothing to write.").chimpFont(.body)
                AdminRow(label: "Token", value: "#\(tokenID)")
                AdminValue(label: "Pocket", value: pocket)
            }
        case .ready(let plan):
            review(plan, isWorking: false)
        case .signing(let plan):
            review(plan, isWorking: true)
        case .submitting:
            AdminPanel(title: "Sending to testnet…") {
                Text(verbatim: "The card has signed. You can lift it. Waiting for the network (up to 60 s).").chimpFont(.body)
            }
        case .enrolled(let result):
            AdminPanel(title: "Card enrolled") {
                AdminRow(label: "Token", value: result.tokenID.map { "#\($0)" } ?? "—")
                AdminValue(label: "Pocket", value: result.pocket)
                if let recoveryID = result.recoveryID {
                    AdminRow(label: "Recovery id", value: "\(recoveryID)")
                }
                AdminValue(label: "Transaction", value: result.transactionHash)
                Link(destination: result.explorerURL) {
                    Text(verbatim: "Open in Stellar Expert").chimpFont(.rowTitle)
                }
            }
        case .failed(let message):
            AdminPanel(title: "Enrolment failed", tone: .negative) {
                Text(verbatim: message).chimpFont(.body).textSelection(.enabled)
                ChimpButton(untranslated("Start over"), kind: .secondary, size: .compact) { model.reset() }
            }
        }
    }

    /// Ce que la carte signe et ce que la transaction fera, affiché avant d'ouvrir la session NFC (règle 8).
    private func review(_ plan: EnrolmentPlan, isWorking: Bool) -> some View {
        AdminPanel(title: "What the card signs") {
            AdminRow(label: "Action", value: "Enrol card (nfc-nft mint)")
            AdminRow(label: "Network", value: "Stellar Testnet")
            AdminValue(label: "Contract (nfc-nft)", value: plan.nfcNft)
            AdminRow(label: "Curve", value: plan.card.curve.rawValue)
            AdminRow(label: "Upgrade policy", value: plan.managed ? "Managed" : "Manual")
            AdminRow(label: "Nonce", value: "\(plan.nonce)")
            AdminValue(label: "Digest signed by the card", value: plan.digest.hexString)
            AdminValue(label: "Pocket that will be created", value: plan.predictedPocket)
            AdminValue(label: "Authorised and paid by (admin)", value: plan.admin)
            if plan.card.pinActive {
                SecureField(text: $pin) { Text(verbatim: "Card PIN") }
                    .keyboardType(.numberPad)
                    .textContentType(.none)
                    .padding(ChimpSpacing.m)
                    .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpBackground), border: ChimpBorder.thin)
            }
            ChimpButton(untranslated("Tap the same card to enrol it"), isLoading: isWorking) {
                let enteredPIN = pin
                pin = ""
                Task { await model.enrol(pin: plan.card.pinActive ? enteredPIN : nil) }
            }
            .disabled(plan.card.pinActive && pin.isEmpty)
        }
    }
}

/// Valeur longue (adresse, hash) sur sa propre ligne, sélectionnable et copiable.
struct AdminValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
            Text(verbatim: label).chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
            Text(verbatim: value)
                .chimpFont(.address)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .contextMenu {
                    Button { UIPasteboard.general.string = value } label: { Text(verbatim: "Copy") }
                }
        }
    }
}
#endif
