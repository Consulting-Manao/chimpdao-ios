#if CHIMP_ADMIN
import Foundation
import Observation

/// Onglet Maintenance de Chimp Admin : la durée de vie du vault DeFindex comme un état (2026-10-22).
/// Vert « Vault OK until {date} » ; orange deux semaines avant l'expiration, avec « Extend » ; rouge une fois expiré.
@Observable
final class VaultHealthModel {
    enum State: Equatable {
        case loading
        /// Vit jusqu'à cette date (estimée), plus de deux semaines devant.
        case ok(until: Date)
        /// Moins de deux semaines : à prolonger.
        case soon(until: Date)
        /// Date passée : la prolongation ne suffit plus (il faut restaurer le contrat).
        case expired(on: Date)
        case unavailable(String)
    }

    enum ExtendResult: Equatable {
        case extended
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var isExtending = false
    private(set) var extendResult: ExtendResult?
    /// Coût estimé de la prolongation, en XLM de testnet (tous les contrats), s'il a pu être lu.
    private(set) var extendCost: Decimal?

    typealias Reading = (latest: UInt32, entries: [ContractLifetime.Entry])
    private let read: () async throws -> Reading
    private let estimate: ([ContractLifetime.Entry]) async throws -> [String: Decimal]
    private let extend: ([ContractLifetime.Entry]) async throws -> [String]
    private let now: () -> Date
    private var entries: [ContractLifetime.Entry] = []
    /// Lecture tenue par le modèle : un écran qui disparaît (changement d'onglet) ne l'interrompt plus
    /// (c'était l'erreur « Stellar RPC error: cancelled »).
    private var loading: Task<Void, Never>?

    /// Moins de 14 jours : orange.
    static let warningDays = 14

    init(read: @escaping () async throws -> Reading,
         estimate: @escaping ([ContractLifetime.Entry]) async throws -> [String: Decimal],
         extend: @escaping ([ContractLifetime.Entry]) async throws -> [String],
         now: @escaping () -> Date = { .now }) {
        self.read = read
        self.estimate = estimate
        self.extend = extend
        self.now = now
    }

    static func live() -> VaultHealthModel {
        let config = ChimpNetworkConfig.testnet
        let lifetime = try? ContractLifetime(config: config, keyStore: KeychainAdminKeyStore(network: .testnet))
        let targets = ContractLifetime.vaultTargets(config)
        return VaultHealthModel(
            read: {
                guard let lifetime else { throw CardEnrolmentError.notTestnet }
                return try await lifetime.read(targets)
            },
            estimate: { entries in try await lifetime?.estimate(entries) ?? [:] },
            extend: { entries in
                guard let lifetime else { throw CardEnrolmentError.notTestnet }
                return try await lifetime.extend(entries)
            }
        )
    }

    /// Lit l'état (une lecture à la fois ; une lecture déjà en cours n'est pas relancée).
    func refresh() {
        guard loading == nil, !isExtending else { return }
        loading = Task {
            await load()
            loading = nil
        }
    }

    func waitForRefresh() async { await loading?.value }

    private func load() async {
        do {
            let reading = try await read()
            entries = reading.entries
            state = Self.state(entries: reading.entries, latest: reading.latest, now: now())
            if case .soon = state {
                extendCost = (try? await estimate(reading.entries)).map { $0.values.reduce(0, +) }
            }
        } catch {
            if Self.isCancellation(error) { return }
            state = .unavailable((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }

    /// « Extend » : la clé admin signe et paie une prolongation par contrat, puis l'état est relu.
    func extendVault() async {
        guard case .soon = state, !isExtending, !entries.isEmpty else { return }
        isExtending = true
        extendResult = nil
        do {
            _ = try await extend(entries)
            extendResult = .extended
        } catch {
            extendResult = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
        isExtending = false
        await load()
    }

    /// L'état d'après le contrat qui expire le premier.
    static func state(entries: [ContractLifetime.Entry], latest: UInt32, now: Date) -> State {
        guard let first = entries.map(\.liveUntil).min() else { return .unavailable("No vault is set up for testnet.") }
        let until = ContractLifetime.estimatedDate(of: first, latest: latest, now: now)
        if first <= latest { return .expired(on: until) }
        let warning = now.addingTimeInterval(Double(warningDays) * 86_400)
        return until <= warning ? .soon(until: until) : .ok(until: until)
    }

    /// Une lecture interrompue n'est pas une panne : on relira.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return "\(error)".localizedCaseInsensitiveContains("cancelled")
    }
}
#endif
