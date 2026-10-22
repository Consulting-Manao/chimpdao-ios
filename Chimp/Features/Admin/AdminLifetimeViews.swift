#if CHIMP_ADMIN
import Observation
import SwiftUI

/// « Vault lifetime » : jusqu'à quand vivent le vault DeFindex XLM et sa stratégie sur testnet, et leur prolongation par
/// l'admin (`ContractLifetime`). Lecture à l'affichage ; prolongation seulement sur demande, après confirmation.
@Observable
final class AdminLifetimeModel {
    enum Message: Equatable {
        case ok(String)
        case failed(String)
    }

    private(set) var latest: UInt32?
    private(set) var entries: [ContractLifetime.Entry] = []
    /// Coût estimé de la prolongation de chaque contrat, en XLM de testnet.
    private(set) var costs: [String: Decimal] = [:]
    private(set) var isBusy = false
    private(set) var message: Message?

    private let lifetime: ContractLifetime?
    private let targets: [(label: String, contract: String)]

    init(config: ChimpNetworkConfig = .testnet, keyStore: AdminKeyStore = KeychainAdminKeyStore(network: .testnet)) {
        lifetime = try? ContractLifetime(config: config, keyStore: keyStore)
        targets = ContractLifetime.vaultTargets(config)
    }

    func load() async {
        guard let lifetime, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let read = try await lifetime.read(targets)
            latest = read.latest
            entries = read.entries
            costs = (try? await lifetime.estimate(read.entries)) ?? [:]
        } catch {
            // Lecture interrompue (écran quitté) : pas une panne, elle reprendra au prochain affichage.
            if VaultHealthModel.isCancellation(error) { return }
            message = .failed("Couldn't read the contracts' lifetime: \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
        }
    }

    func extend() async {
        guard let lifetime, !isBusy, !entries.isEmpty else { return }
        isBusy = true
        message = nil
        do {
            let hashes = try await lifetime.extend(entries)
            isBusy = false
            message = .ok("Extended · " + hashes.map { "tx \($0.prefix(8))…\($0.suffix(4))" }.joined(separator: " · "))
            await load()
        } catch {
            isBusy = false
            message = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }
}

struct AdminLifetimePanel: View {
    let model: AdminLifetimeModel
    let hasAdminKey: Bool
    @State private var isConfirming = false

    var body: some View {
        AdminPanel(title: "Vault lifetime") {
            Text(verbatim: "On Soroban, a contract expires unless someone extends it. Extending is free of risk: no money moves, "
                + "no card signs. The admin key signs and pays one transaction per contract, for about 3 months from now.")
                .chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
            if let latest = model.latest {
                AdminValue(label: "Latest ledger", value: "\(latest)")
                ForEach(model.entries) { entry in
                    AdminValue(
                        label: entry.label,
                        value: "until ledger \(entry.liveUntil) · ≈ \(ContractLifetime.estimatedDate(of: entry.liveUntil, latest: latest).formatted(date: .abbreviated, time: .omitted))"
                            + (model.costs[entry.contract].map { " · extending costs ≈ \($0.formatted(.number.precision(.fractionLength(0...2)))) XLM" } ?? "")
                    )
                }
            }
            if !hasAdminKey {
                Text(verbatim: "Save the admin key above first: it signs and pays the extension.")
                    .chimpFont(.caption).foregroundStyle(Color(.chimpNegative))
            }
            ChimpButton(untranslated(model.isBusy ? "Working…" : "Extend the vault's lifetime"), isLoading: model.isBusy) {
                isConfirming = true
            }
            .disabled(model.isBusy || model.entries.isEmpty || !hasAdminKey)
            switch model.message {
            case .ok(let text):
                Text(verbatim: text).chimpFont(.body).foregroundStyle(Color(.chimpPositive)).textSelection(.enabled)
            case .failed(let text):
                Text(verbatim: text).chimpFont(.body).foregroundStyle(Color(.chimpNegative)).textSelection(.enabled)
            case nil:
                EmptyView()
            }
        }
        .task { await model.load() }
        .confirmationDialog(Text(verbatim: "Extend the vault's lifetime?"), isPresented: $isConfirming, titleVisibility: .visible) {
            Button {
                Task { await model.extend() }
            } label: {
                Text(verbatim: "Extend (the admin pays the rent)")
            }
            Button(role: .cancel) {} label: { Text(verbatim: "Cancel") }
        } message: {
            Text(verbatim: "One testnet transaction per contract from the admin key: extendFootprintTtl on the instance and the code. "
                + "The rent is paid in testnet XLM (see the estimates).")
        }
    }
}
#endif
