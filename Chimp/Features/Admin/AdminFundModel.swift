#if CHIMP_ADMIN
import Foundation
import Observation

/// « Testnet money » : portage du `FundBlock` du terminal (`modules/settings/Settings.tsx`), partie Stellar.
/// Un bouton finance le Main account puis le wallet (Pocket) de chaque carte du compte, **l'un après l'autre** (un seul
/// payeur, l'admin, donc une seule séquence). Le premier motif d'échec est gardé : « 1/2 funded — Friendbot refused: 502 ».
@Observable
final class AdminFundModel {
    /// Une adresse à financer.
    struct Target: Equatable, Identifiable {
        let label: String
        let address: String

        var id: String { address }
    }

    enum Message: Equatable {
        case ok(String)
        case failed(String)
    }

    private(set) var targets: [Target] = []
    private(set) var isLoadingTargets = false
    private(set) var isBusy = false
    private(set) var message: Message?
    /// « Any address » : une adresse G ou C saisie (Chimp Admin n'a pas de compte ouvert).
    var customAddress = ""

    private let session: AppSession
    private let chain: WalletChain
    private let funder: TestnetFunding

    init(session: AppSession, chain: WalletChain, funder: TestnetFunding) {
        self.session = session
        self.chain = chain
        self.funder = funder
    }

    /// Les destinations, comme le terminal les tire de la vue du compte : le Main account, puis la Pocket de chaque carte
    /// que le compte déclare (`cards()`), celle mémorisée sur le téléphone sinon celle de la factory.
    func loadTargets() async {
        guard let account = session.wallet.account else {
            targets = []
            return
        }
        isLoadingTargets = true
        defer { isLoadingTargets = false }
        var found = [Target(label: "Main account", address: account.address)]
        do {
            for key in try await chain.cards(of: account.address).map(\.publicKey) {
                let saved = account.cards.first { $0.publicKey == key.hex }
                let pocket: String?
                if let known = saved?.pocket {
                    pocket = known
                } else {
                    pocket = try await chain.pocket(of: key)
                }
                if let pocket { found.append(Target(label: "\(saved?.name ?? "Card")'s wallet", address: pocket)) }
            }
            targets = found
        } catch {
            targets = found
            message = .failed("Couldn't read the account's cards: \(Self.describe(error)). Only the Main account is listed.")
        }
    }

    /// « Fund this account » : chaque destination à son tour ; message de succès, ou « k/N funded — premier motif ».
    func fund() async {
        guard !isBusy else { return }
        guard !targets.isEmpty else {
            message = .failed("Nothing to fund yet — sign in or add a card first")
            return
        }
        isBusy = true
        message = nil
        defer { isBusy = false }
        var reasons: [String] = []
        var funded = 0
        for target in targets {
            do {
                try await funder.fund(target.address)
                funded += 1
            } catch {
                reasons.append(Self.describe(error))
            }
        }
        let total = targets.count
        message = funded == total
            ? .ok("Funded \(total) balance\(total == 1 ? "" : "s"). Pull to refresh the Wallet.")
            : .failed("\(funded)/\(total) funded — \(reasons.first ?? "unknown")")
    }

    /// L'adresse saisie, si elle a la forme d'une adresse Stellar (G… ou C…, 56 caractères) ; sinon `nil`.
    var customTarget: String? {
        let address = customAddress.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard address.count == 56, address.hasPrefix("G") || address.hasPrefix("C") else { return nil }
        return address
    }

    /// « Send 1000 test XLM » vers l'adresse saisie (même financement que les autres : friendbot pour G, l'admin pour C).
    func fundCustom() async {
        guard !isBusy, let address = customTarget else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            try await funder.fund(address)
            message = .ok("Sent 1000 test XLM to \(address.prefix(6))…\(address.suffix(4)).")
        } catch {
            message = .failed(Self.describe(error))
        }
    }

    static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }
}
#endif
