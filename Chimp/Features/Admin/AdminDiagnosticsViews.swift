#if CHIMP_ADMIN
import Observation
import SwiftUI

/// Mode admin : « Resolve this card » — ce que l'onboarding lira pour la carte lue, en lecture seule.
@Observable
final class AdminDiagnosticsModel {
    enum State: Equatable {
        case idle
        case running
        case done(CardDiagnostics)
        case failed(String)
    }

    private(set) var state: State = .idle
    private let service: CardDiagnosing

    init(service: CardDiagnosing) {
        self.service = service
    }

    var isBusy: Bool { state == .running }

    func run(for card: ChipKeyInfo) async {
        guard !isBusy else { return }
        state = .running
        do {
            state = .done(try await service.diagnose(card))
        } catch {
            // Mode admin : erreur technique détaillée (texte d'origine du RPC).
            state = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }
}

struct AdminDiagnosticsPanel: View {
    let card: ChipKeyInfo
    let model: AdminDiagnosticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.sectionGap) {
            ChimpButton(untranslated("Resolve this card (read-only)"), kind: .secondary, isLoading: model.isBusy) {
                Task { await model.run(for: card) }
            }
            .disabled(model.isBusy)
            switch model.state {
            case .idle, .running:
                EmptyView()
            case .done(let result):
                AdminPanel(title: "What onboarding will see") {
                    AdminRow(label: "Resolution", value: Self.describe(result.resolution))
                    AdminRow(label: "Card N°", value: result.state.tokenID.map { String($0) } ?? "—")
                    address("Card's wallet (Pocket)", result.state.pocket)
                    address("Pocket owner", result.state.pocketOwner)
                    address("NFT campaign", result.state.nftContract)
                    address("Predicted Main account", result.predictedAccount)
                    AdminRow(label: "Main account deployed", value: result.accountDeployed ? "Yes" : "No")
                    if let fee = result.deploymentFee {
                        AdminRow(label: "Deployment fee (simulated)", value: "\(fee) stroops")
                    }
                    if let error = result.deploymentError {
                        Text(verbatim: "Deployment simulation failed: \(error)")
                            .chimpFont(.caption).foregroundStyle(.chimpNegative).textSelection(.enabled)
                    }
                    ForEach(result.pocketBalances, id: \.code) { balance in
                        AdminRow(label: "Pocket \(balance.code)", value: balance.amount.map { "\($0)" } ?? "unknown")
                    }
                    Text(verbatim: "Nothing was signed, sent or paid.")
                        .chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
                }
            case .failed(let message):
                AdminPanel(title: "Couldn't resolve the card", tone: .negative) {
                    Text(verbatim: message).chimpFont(.body).textSelection(.enabled)
                }
            }
        }
    }

    private func address(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
            Text(verbatim: label).chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
            Text(verbatim: value ?? "—").chimpFont(.address).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    static func describe(_ resolution: CardResolution) -> String {
        switch resolution {
        case .signIn(let account, let source): "signIn (\(source.rawValue)) \(account.prefix(6))…"
        case .newCard: "newCard (not enrolled)"
        case .enrolled: "enrolled (no account yet)"
        case .orphan(let lastKnown): "orphan (last: \(lastKnown.map { String($0.prefix(6)) } ?? "—"))"
        case .unknown(let detail): "unknown: \(detail)"
        }
    }
}
#endif
