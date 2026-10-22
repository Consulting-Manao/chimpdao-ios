#if CHIMP_ADMIN
import Foundation
import Observation

/// Chimp Admin : la clé admin enregistrée sur cet iPhone et le solde de son compte, pour la ligne d'état en haut de
/// chaque onglet (« Admin key ✓ · 19,920 test XLM ») et l'écran « Set up Chimp Admin » (demande de Barth du 2026-10-22).
@Observable
final class AdminSession {
    enum Balance: Equatable {
        case unknown
        case loading
        case xlm(Decimal)
        case unavailable
    }

    let key: AdminKeyModel
    private(set) var balance: Balance = .unknown
    /// Solde XLM du compte admin (Horizon). Lecture seule.
    private let readBalance: (String) async throws -> Decimal
    /// Lecture en cours : tenue par le modèle, pas par l'écran (un écran qui disparaît ne l'interrompt pas).
    private var reading: Task<Void, Never>?

    init(key: AdminKeyModel, readBalance: @escaping (String) async throws -> Decimal) {
        self.key = key
        self.readBalance = readBalance
    }

    /// Le vrai trousseau et Horizon testnet sur iPhone ; un faux solde sur le simulateur.
    static func live() -> AdminSession {
        let key = AdminKeyModel(store: KeychainAdminKeyStore(network: .testnet))
        #if targetEnvironment(simulator)
        return AdminSession(key: key) { _ in 19_920 }
        #else
        let network = try? ChainFundingNetwork(config: .testnet)
        return AdminSession(key: key) { account in
            guard let network else { throw CardEnrolmentError.notTestnet }
            return try await network.nativeBalance(of: account)
        }
        #endif
    }

    var hasKey: Bool { key.hasKey }

    /// Relit le solde de l'admin (sans effet sans clé).
    func refreshBalance() {
        guard let account = key.publicKey else {
            balance = .unknown
            return
        }
        reading?.cancel()
        if case .xlm = balance {} else { balance = .loading }
        reading = Task { [readBalance] in
            do {
                let xlm = try await readBalance(account)
                guard !Task.isCancelled else { return }
                balance = .xlm(xlm)
            } catch {
                guard !Task.isCancelled else { return }
                balance = .unavailable
            }
        }
    }

    /// Attend la lecture en cours (tests).
    func waitForBalance() async { await reading?.value }

    /// « Admin key ✓ · 19,920 test XLM ».
    var statusText: String {
        if key.isUnexpectedAdmin { return "Admin key ⚠ · not the ChimpDAO admin" }
        let money: String = switch balance {
        case .xlm(let amount): "\(Self.xlmText(amount)) test XLM"
        case .unavailable: "balance unavailable"
        case .unknown, .loading: "… test XLM"
        }
        return "Admin key ✓ · \(money)"
    }

    /// « 19,920 », « 12.5 » : au plus deux décimales, tronquées.
    static func xlmText(_ amount: Decimal, locale: Locale = .autoupdatingCurrent) -> String {
        amount.truncated(to: 2).formatted(.number.locale(locale).precision(.fractionLength(0...2)))
    }
}
#endif
