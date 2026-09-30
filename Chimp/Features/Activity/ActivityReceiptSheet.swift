import SwiftUI

/// Détail d'un mouvement (maquette I1.1d, « Details — mix: I1 slip + printed receipt ») : le reçu imprimé, puis
/// « Pay again » (seulement pour un envoi : Envoyer s'ouvre avec l'adresse collée en C1) et « Share ».
struct ActivityReceiptSheet: View {
    let receipt: ActivityReceipt
    let model: ActivityViewModel
    var onPayAgain: (String) -> Void = { _ in }

    /// La feuille (`chimpSheet(fitsContent:)`) fait défiler le contenu s'il dépasse l'écran.
    var body: some View {
        ActivityReceiptContent(receipt: receipt, model: model, onPayAgain: onPayAgain)
            .padding(.horizontal, ChimpSpacing.xxl)
            .padding(.top, ChimpSpacing.xs)
    }
}

/// Le reçu et ses boutons, sans la vue défilante.
struct ActivityReceiptContent: View {
    let receipt: ActivityReceipt
    let model: ActivityViewModel
    var onPayAgain: (String) -> Void = { _ in }

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: ChimpSpacing.ml) {
            slip
            buttons
        }
        .sensoryFeedback(.success, trigger: model.copyCount)
        .onChange(of: model.copyCount) {
            AccessibilityNotification.Announcement(String(localized: "Transaction copied")).post()
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
                ChimpReceiptLine(label: line.label) { value(line.value) }
            }
            ChimpReceiptLine(label: "Tx") {
                Text(receipt.shortHash)
                    .accessibilityLabel(Text("Transaction \(receipt.hash)"))
            } accessory: {
                copyButton
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

    private var copyButton: some View {
        let copied = model.copiedHash == receipt.hash
        return Button {
            model.copyHash(receipt.hash)
        } label: {
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
        .accessibilityLabel(copied ? Text("Copied!") : Text("Copy the transaction"))
    }

    @ViewBuilder
    private var buttons: some View {
        if let address = receipt.payAgainAddress {
            HStack(spacing: ChimpSpacing.sm) {
                ChimpButton("Pay again") { onPayAgain(address) }
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
