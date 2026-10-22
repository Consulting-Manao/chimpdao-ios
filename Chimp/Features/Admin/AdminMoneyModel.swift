#if CHIMP_ADMIN
import Foundation
import Observation

/// Onglet Money de Chimp Admin : « Send test money » vers une adresse G… ou C…, avec le montant (2026-10-22).
@Observable
final class AdminMoneyModel {
    enum Message: Equatable {
        case sent(String)
        case failed(String)
    }

    var address = ""
    var amountText = "\(PrepareCardsModel.defaultStartingXLM)"
    private(set) var isSending = false
    private(set) var message: Message?

    /// `nil` : le testnet n'est pas joignable dans ce build (jamais un faux envoi sur iPhone).
    private let funder: TestnetFunding?
    /// Appelé après un envoi (le solde de l'admin a changé).
    var onSent: () -> Void = {}

    static let amountRange = 1...1000

    init(funder: TestnetFunding?) {
        self.funder = funder
    }

    /// Les vrais services sur iPhone ; un faux envoi sur le simulateur.
    static func live() -> AdminMoneyModel {
        #if targetEnvironment(simulator)
        return AdminMoneyModel(funder: MockTestnetFunding())
        #else
        return AdminMoneyModel(funder: (try? ChainFundingNetwork(config: .testnet)).map {
            TestnetFunder(keyStore: KeychainAdminKeyStore(network: .testnet), network: $0)
        })
        #endif
    }

    /// L'adresse saisie, si elle a la forme d'une adresse Stellar (G… ou C…, 56 caractères).
    var target: String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count == 56, trimmed.hasPrefix("G") || trimmed.hasPrefix("C") else { return nil }
        return trimmed
    }

    var amount: Int? {
        guard let value = Int(amountText.trimmingCharacters(in: .whitespaces)), Self.amountRange.contains(value) else { return nil }
        return value
    }

    var addressProblem: String? {
        address.isEmpty || target != nil ? nil : "That isn't a Stellar address. It starts with G or C and has 56 characters."
    }

    var amountProblem: String? {
        amountText.isEmpty || amount != nil ? nil : "Choose between \(Self.amountRange.lowerBound) and \(Self.amountRange.upperBound) XLM."
    }

    var canSend: Bool { target != nil && amount != nil && !isSending }

    func send() async {
        guard canSend, let target, let amount else { return }
        guard let funder else {
            message = .failed("Stellar testnet isn't available in this build.")
            return
        }
        isSending = true
        message = nil
        defer { isSending = false }
        do {
            switch try await funder.send(target, units: PrepareCardsModel.units(amount)) {
            case .sent:
                message = .sent("Sent \(amount) test XLM to \(target.prefix(6))…\(target.suffix(4)).")
            case .openedByFriendbot:
                message = .sent("This account was new: friendbot opened it with 10,000 test XLM.")
            }
            onSent()
        } catch {
            message = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }
}
#endif
