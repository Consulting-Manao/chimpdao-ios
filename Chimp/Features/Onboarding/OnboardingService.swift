import Foundation
import stellarsdk

/// Ce qu'on sait d'une carte après le tap d'A2 (lecture seule, rien n'est signé ni payé).
struct CardInspection: Equatable {
    let card: ChipKeyInfo
    let resolution: CardResolution
    /// Numéro du NFT (« N°0007 »), si la carte est enregistrée.
    let tokenID: UInt32?
    /// Adresse de la Pocket (le wallet de la carte), si la carte est enregistrée.
    let pocket: String?
    /// La Pocket est vide (XLM et USDC à zéro) ; `nil` si on ne le sait pas (lecture sans réponse ou en échec).
    let pocketIsEmpty: Bool?
}

/// Le réseau vu par l'onboarding. Implémenté par `ChainOnboardingService` (testnet) et `MockOnboardingService`.
protocol OnboardingService {
    /// Qui est cette carte ? `hint` : compte mémorisé sur le téléphone pour elle (vérifié en premier).
    func inspect(_ card: ChipKeyInfo, hint: String?) async throws -> CardInspection
}

/// Branché sur les briques de `Core/` : résolution §3.4 (`ChainCardResolver`), état de la carte, soldes de la Pocket.
struct ChainOnboardingService: OnboardingService {
    let config: ChimpNetworkConfig

    func inspect(_ card: ChipKeyInfo, hint: String?) async throws -> CardInspection {
        let resolver = ChainCardResolver(config: config)
        let resolution = try await resolver.resolve(card.publicKey, hint: hint)
        switch resolution {
        case .newCard, .unknown:
            return CardInspection(card: card, resolution: resolution, tokenID: nil, pocket: nil, pocketIsEmpty: nil)
        case .signIn:
            let state = try await resolver.state(of: card.publicKey)
            return CardInspection(card: card, resolution: resolution, tokenID: state.tokenID, pocket: state.pocket, pocketIsEmpty: nil)
        case .enrolled, .orphan:
            let state = try await resolver.state(of: card.publicKey)
            var empty: Bool?
            if let pocket = state.pocket {
                // Affichage seulement (A3 « $0.00, empty ») : une lecture ratée donne « on ne sait pas », jamais « vide ».
                empty = try? await pocketIsEmpty(pocket)
            }
            return CardInspection(card: card, resolution: resolution, tokenID: state.tokenID, pocket: state.pocket, pocketIsEmpty: empty)
        }
    }

    /// XLM et USDC de la Pocket à zéro ? `nil` si un solde n'a rendu aucune valeur.
    private func pocketIsEmpty(_ pocket: String) async throws -> Bool? {
        let client = SorobanClient(config: config)
        let source = try await client.account(config.feePayer)
        let sac = SACClient(client: client)
        let assets = [
            Asset(type: AssetType.ASSET_TYPE_NATIVE)!,
            Asset(type: AssetType.ASSET_TYPE_CREDIT_ALPHANUM4, code: "USDC", issuer: try KeyPair(accountId: config.usdcIssuer))!,
        ]
        for asset in assets {
            let token = try SACClient.contractID(for: asset, network: client.network)
            guard let units = try await sac.balance(token: token, holder: pocket, source: source) else { return nil }
            if units != 0 { return false }
        }
        return true
    }
}

/// Faux réseau pour le simulateur et le catalogue : chaque scénario reproduit une réponse possible.
struct MockOnboardingService: OnboardingService {
    enum Scenario: String, CaseIterable, Identifiable {
        /// Carte neuve, enregistrée, sans compte (A3).
        case fresh
        /// Carte neuve avec de l'argent sur son wallet.
        case freshWithMoney
        /// Carte retirée d'un compte (A3, variante « This card is yours »).
        case orphan
        /// Carte déjà dans un compte (ouvre le Wallet).
        case member
        /// Carte non enregistrée (H3).
        case notEnrolled
        /// Réseau : la résolution n'a pas pu tout demander (A2, « re-tapez »).
        case unknown
        /// Réseau en panne.
        case networkError

        var id: String { rawValue }
    }

    var scenario: Scenario = .fresh
    var delay: Duration = .milliseconds(900)

    static let memberAccount = "CDU45A6K2WTMLRDUEQ7SXGOUICJVRWSLZCYPLWB7W6FVQLD7LPNRVVFR"

    func inspect(_ card: ChipKeyInfo, hint: String?) async throws -> CardInspection {
        try await Task.sleep(for: delay)
        let pocket = try PocketFactoryClient.predictedPocket(
            factory: ChimpNetworkConfig.testnet.contracts.factory, publicKey: card.publicKey, network: .testnet
        )
        switch scenario {
        case .fresh:
            return CardInspection(card: card, resolution: .enrolled, tokenID: 7, pocket: pocket, pocketIsEmpty: true)
        case .freshWithMoney:
            return CardInspection(card: card, resolution: .enrolled, tokenID: 688, pocket: pocket, pocketIsEmpty: false)
        case .orphan:
            return CardInspection(card: card, resolution: .orphan(lastKnown: Self.memberAccount), tokenID: 421, pocket: pocket, pocketIsEmpty: true)
        case .member:
            return CardInspection(card: card, resolution: .signIn(account: Self.memberAccount, source: .pocket), tokenID: 421, pocket: pocket, pocketIsEmpty: nil)
        case .notEnrolled:
            return CardInspection(card: card, resolution: .newCard, tokenID: nil, pocket: nil, pocketIsEmpty: nil)
        case .unknown:
            return CardInspection(card: card, resolution: .unknown(detail: "Couldn't check this card"), tokenID: nil, pocket: nil, pocketIsEmpty: nil)
        case .networkError:
            throw StellarError.rpc("The request timed out.")
        }
    }
}
