#if CHIMP_ADMIN
import Foundation
import Observation

/// « Reserve money for a card » (Chimp Admin, onglet Cards, D5) : après « Check a card », un montant en XLM de testnet,
/// puis `prize.deposit` par la clé admin. L'argent est mis de côté pour cette carte : seule elle peut le retirer, vers son
/// wallet, depuis ChimpDAO. Le contrat n'a pas de remboursement : un dépôt ne se reprend pas (dit avant d'envoyer).
@Observable
final class AdminPrizeModel {
    enum Reservation: Equatable {
        case loading
        case loaded(PrizeReservation)
        case failed(String)
    }

    enum Message: Equatable {
        case reserved(String)
        case failed(String)
    }

    let card: ChipPublicKey
    /// « Card #007 », ou « This card ».
    let title: String
    var amountText = "\(PrepareCardsModel.defaultStartingXLM)"
    private(set) var reservation: Reservation = .loading
    private(set) var isReserving = false
    private(set) var message: Message?
    var isConfirming = false

    /// `nil` : pas de contrat `prize` sur ce réseau (pas encore déployé), ou pas de testnet dans ce build.
    private let service: PrizeReserving?
    static let amountRange = 1...1000

    init(card: ChipPublicKey, title: String, service: PrizeReserving?) {
        self.card = card
        self.title = title
        self.service = service
    }

    /// Le vrai contrat sur iPhone (s'il est configuré) ; un faux sur le simulateur.
    static func live(card: ChipPublicKey, title: String) -> AdminPrizeModel {
        #if targetEnvironment(simulator)
        return AdminPrizeModel(card: card, title: title, service: MockPrizeReserving())
        #else
        return AdminPrizeModel(card: card, title: title, service: try? ChainPrizeReserving(
            config: .testnet, keyStore: KeychainAdminKeyStore(network: .testnet)
        ))
        #endif
    }

    /// Le contrat est-il configuré ? Sinon le bouton de la fiche ne s'affiche pas.
    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        ChimpNetworkConfig.testnet.contracts.prize != nil
        #endif
    }

    var amount: Int? {
        guard let value = Int(amountText.trimmingCharacters(in: .whitespaces)), Self.amountRange.contains(value) else { return nil }
        return value
    }

    var amountProblem: String? {
        amountText.isEmpty || amount != nil ? nil : "Choose between \(Self.amountRange.lowerBound) and \(Self.amountRange.upperBound) XLM."
    }

    var canReserve: Bool {
        guard amount != nil, !isReserving, service != nil, case .loaded = reservation else { return false }
        return true
    }

    /// Ce que le contrat sait de la carte (numéro de NFT, déjà mis de côté).
    func load() async {
        guard let service else {
            reservation = .failed("The prize contract isn't deployed on testnet yet.")
            return
        }
        reservation = .loading
        do {
            reservation = .loaded(try await service.reservation(for: card))
        } catch {
            reservation = .failed(Self.describe(error))
        }
    }

    /// Après la confirmation : le dépôt, signé et payé par la clé admin. Un seul envoi à la fois.
    func reserve() async {
        guard canReserve, let amount, let service else { return }
        isReserving = true
        message = nil
        defer { isReserving = false }
        do {
            let result = try await service.reserve(TokenAmount(Int128(PrepareCardsModel.units(amount))), for: card)
            let total = result.reserved.map { " Now reserved: \(Self.xlmText($0)) XLM." } ?? ""
            message = .reserved("Reserved \(amount) test XLM for \(title).\(total)")
            if let reserved = result.reserved, case .loaded(let old) = reservation {
                reservation = .loaded(PrizeReservation(tokenID: old.tokenID, reserved: reserved))
            } else {
                await load()
            }
        } catch {
            message = .failed(Self.describe(error))
        }
    }

    static func xlmText(_ amount: TokenAmount) -> String {
        SACClient.amount(fromUnits: Decimal(string: String(amount.units)) ?? 0).formatted(.number.precision(.fractionLength(0...7)))
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }
}

/// Pour `navigationDestination(item:)` : un écran par modèle (identité de l'objet).
extension AdminPrizeModel: Hashable {
    static func == (lhs: AdminPrizeModel, rhs: AdminPrizeModel) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
#endif
