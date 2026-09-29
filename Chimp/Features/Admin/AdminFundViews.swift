#if CHIMP_ADMIN
import SwiftUI
import UIKit

/// « Testnet money » (`FundBlock` du terminal) : 1000 XLM de testnet vers le Main account et chaque wallet de carte,
/// payés par la clé admin ; puis l'USDC de test, à demander à la main au faucet de Circle.
struct AdminFundPanel: View {
    let model: AdminFundModel
    let hasAdminKey: Bool
    let usdcFaucet: URL?
    @State private var copiedAddress: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        AdminPanel(title: "Testnet money") {
            Text(verbatim: "Tops up the Main account and every card's wallet with 1000 testnet XLM each, sent by the admin key. "
                + "The admin is topped up by friendbot first if it holds less than 2000 XLM.")
                .chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
            ForEach(model.targets) { target in
                AdminValue(label: target.label, value: target.address)
            }
            if !hasAdminKey {
                Text(verbatim: "Save the admin key above first: it signs and pays the transfers.")
                    .chimpFont(.caption).foregroundStyle(Color(.chimpNegative))
            }
            ChimpButton(untranslated(buttonTitle), isLoading: model.isBusy || model.isLoadingTargets) {
                Task { await model.fund() }
            }
            .disabled(model.isBusy || model.targets.isEmpty || !hasAdminKey)
            switch model.message {
            case .ok(let text):
                Text(verbatim: text).chimpFont(.body).foregroundStyle(Color(.chimpPositive)).textSelection(.enabled)
            case .failed(let text):
                Text(verbatim: text).chimpFont(.body).foregroundStyle(Color(.chimpNegative)).textSelection(.enabled)
            case nil:
                EmptyView()
            }
            if let usdcFaucet { usdc(usdcFaucet) }
        }
        .task { await model.loadTargets() }
    }

    private var buttonTitle: String {
        if model.isBusy { return "Funding…" }
        return model.targets.isEmpty ? "Fund this account" : "Fund this account (\(model.targets.count))"
    }

    /// USDC de test : Circle n'offre qu'un site (captcha), comme dans le terminal. Son formulaire accepte une adresse C
    /// (vérifié le 2026-09-29) ; qu'il livre vraiment à un contrat reste à vérifier à la main.
    private func usdc(_ faucet: URL) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.s) {
            Text(verbatim: "Test USDC").chimpFont(.rowTitle)
            Text(verbatim: "Circle's faucet sends 20 USDC per address every 2 hours. Choose \"Stellar Testnet\", paste an address "
                + "copied below, then \"Send 20 USDC\". Its form accepts a contract address (C…); whether the USDC actually "
                + "arrives there hasn't been checked yet.")
                .chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
            ForEach(model.targets) { target in
                ChimpButton(
                    untranslated(copiedAddress == target.address ? "Copied!" : "Copy \(target.label) address"),
                    kind: .secondary, size: .compact
                ) {
                    UIPasteboard.general.string = target.address
                    copiedAddress = target.address
                }
            }
            ChimpButton(untranslated("Open faucet.circle.com"), kind: .secondary, size: .compact) {
                openURL(faucet)
            }
        }
        .padding(.top, ChimpSpacing.s)
    }
}
#endif
