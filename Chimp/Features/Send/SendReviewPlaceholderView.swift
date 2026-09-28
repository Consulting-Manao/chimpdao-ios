import SwiftUI

/// ⚠️ Provisoire (jalon 4a, étape A) : montre le brouillon figé par C2 pour vérifier les valeurs
/// (adresse exacte, memo ID, tiroir, montant indépendant de la langue). Remplacé par C4 à l'étape B.
struct SendReviewPlaceholderView: View {
    let model: SendFlowModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Here's what happens", step: 3, steps: 3, onBack: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    ChimpNoticeBanner(text: "Temporary screen (step A). The real review, PIN and tap come in step B.")
                    if let draft = model.draft {
                        row("To", draft.recipientName ?? "—")
                        row("Address", draft.recipient.address)
                        row("Memo ID", draft.recipient.memoID.map { String($0) } ?? "—")
                        row("From", draft.drawer.title)
                        row("Amount (shown)", draft.asset.formattedWithCode(draft.amount, locale: locale))
                        // `description` d'un Decimal : toujours avec un point, quelle que soit la langue.
                        row("Amount (value sent)", "\(draft.amount.description) \(draft.asset.code)")
                    }
                }
                .padding(ChimpSpacing.screenMargin)
            }
        }
        .background(Color(.chimpBackground))
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .chimpFont(.label)
                .textCase(.uppercase)
                .foregroundStyle(.chimpTextSecondary)
            Text(verbatim: value)
                .chimpFont(.monoValue)
                .foregroundStyle(.chimpTextPrimary)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
