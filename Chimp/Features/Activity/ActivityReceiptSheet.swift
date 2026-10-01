import SwiftUI

/// Détail d'un mouvement (maquette I1.1d, « Details — mix: I1 slip + printed receipt ») : le reçu imprimé, l'adresse de
/// l'autre partie copiable, puis « Pay again » (envoi) ou « Send back » (paiement reçu), qui ouvrent Envoyer prérempli
/// (adresse, actif, montant ; C4 toujours), et « Share ».
struct ActivityReceiptSheet: View {
    let receipt: ActivityReceipt
    let model: ActivityViewModel
    var onSend: (SendPrefill) -> Void = { _ in }

    /// La feuille (`chimpSheet(fitsContent:)`) fait défiler le contenu s'il dépasse l'écran.
    var body: some View {
        ActivityReceiptContent(receipt: receipt, model: model, onSend: onSend)
            .padding(.horizontal, ChimpSpacing.xxl)
            .padding(.top, ChimpSpacing.xs)
    }
}

/// Le reçu et ses boutons, sans la vue défilante.
struct ActivityReceiptContent: View {
    let receipt: ActivityReceipt
    let model: ActivityViewModel
    var onSend: (SendPrefill) -> Void = { _ in }

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: ChimpSpacing.ml) {
            slip
            buttons
        }
        .sensoryFeedback(.success, trigger: model.copyCount)
        .onChange(of: model.copyCount) {
            switch model.copied {
            case .address: AccessibilityNotification.Announcement(String(localized: "Address copied")).post()
            case .hash, nil: AccessibilityNotification.Announcement(String(localized: "Transaction copied")).post()
            }
        }
    }

    private var slip: some View {
        ChimpReceiptSlip(
            header: receipt.header, number: receipt.number, title: receipt.title, total: receipt.total,
            totalColor: receipt.totalTone == .positive ? Color(.chimpStampReceived) : Color(.chimpTicketInk),
            stamp: receipt.stamp.text, stampColor: receipt.stamp.color,
            onExplorer: receipt.explorerURL.map { url in { openURL(url) } }
        ) {
            ForEach(receipt.lines) { line in
                if let counterparty = receipt.counterparty, counterparty.lineID == line.id {
                    ChimpReceiptLine(label: line.label) {
                        value(line.value)
                            .accessibilityLabel(Text(verbatim: counterparty.address))
                    } accessory: {
                        copyButton(copied: model.copied == .address(counterparty.address), label: Text("Copy the address")) {
                            model.copyAddress(counterparty.address)
                        }
                    }
                } else {
                    ChimpReceiptLine(label: line.label) { value(line.value) }
                }
            }
            ChimpReceiptLine(label: "Tx") {
                Text(receipt.shortHash)
                    .accessibilityLabel(Text("Transaction \(receipt.hash)"))
            } accessory: {
                copyButton(copied: model.copied == .hash(receipt.hash), label: Text("Copy the transaction")) {
                    model.copyHash(receipt.hash)
                }
            }
        }
    }

    @ViewBuilder
    private func value(_ value: ActivityReceipt.Line.Value) -> some View {
        switch value {
        case .text(let text):
            Text(text)
        case .positive(let text):
            Text(text).foregroundStyle(Color(.chimpStampReceived))
        case .drawer(let name, let swatch):
            HStack(spacing: 6) {
                switch swatch {
                case .main: ChimpReceiptSwatch(color: Color(.chimpAccent))
                case .card(let color): ChimpReceiptSwatch(color: color.fill)
                }
                Text(name)
            }
        }
    }

    private func copyButton(copied: Bool, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(copied ? "Copied!" : "Copy")
                .chimpFont(.receiptLink)
                .foregroundStyle(Color(.chimpTicketInk))
                .padding(.horizontal, 9)
                .padding(.vertical, 1)
                .overlay { Capsule().strokeBorder(Color(.chimpTicketInk), lineWidth: ChimpBorder.thin) }
                .frame(minHeight: ChimpSize.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(ChimpPressableStyle())
        .accessibilityLabel(copied ? Text("Copied!") : label)
    }

    @ViewBuilder
    private var buttons: some View {
        if let send = receipt.send {
            HStack(spacing: ChimpSpacing.sm) {
                ChimpButton(send.origin == .sendBack ? "Send back" : "Pay again") { onSend(send) }
                share.frame(width: 96)
            }
        } else {
            share
        }
    }

    private var share: some View {
        ShareLink(item: receipt.shareText) {
            Text("Share").frame(maxWidth: .infinity)
        }
        .buttonStyle(ChimpButtonStyle(kind: .secondary, raised: true))
    }
}
