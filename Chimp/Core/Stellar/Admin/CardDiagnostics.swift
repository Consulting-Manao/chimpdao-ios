#if CHIMP_ADMIN
import Foundation
import stellarsdk

/// Diagnostic d'une carte sur testnet, **en lecture seule** — mode admin uniquement (arrêt 1 de l'onboarding).
/// Tout passe par des simulations : rien n'est signé, rien n'est envoyé, rien n'est payé.
/// Réutilise les briques de l'onboarding : `ChainCardResolver`, `ChimpAccountClient`, `SACClient`.
protocol CardDiagnosing {
    func diagnose(_ card: ChipKeyInfo) async throws -> CardDiagnostics
}

struct CardDiagnostics: Equatable {
    struct AssetBalance: Equatable {
        let code: String
        /// `nil` : la simulation n'a rendu aucune valeur (solde inconnu).
        let amount: Decimal?
    }

    let resolution: CardResolution
    let state: CardState
    /// Adresse que le Main account de cette carte aura (déployeur = payeur de frais, sel = sha256(clé)).
    let predictedAccount: String
    let accountDeployed: Bool
    /// Frais simulés du déploiement (stroops), si le compte n'est pas encore déployé et que la simulation a réussi.
    let deploymentFee: UInt32?
    /// Texte de l'erreur de simulation du déploiement, le cas échéant (le diagnostic continue quand même).
    let deploymentError: String?
    let pocketBalances: [AssetBalance]
}

struct ChainCardDiagnostics: CardDiagnosing {
    let config: ChimpNetworkConfig

    func diagnose(_ card: ChipKeyInfo) async throws -> CardDiagnostics {
        let client = SorobanClient(config: config)
        let resolver = ChainCardResolver(config: config)
        let accounts = ChimpAccountClient(client: client, config: config)

        let resolution = try await resolver.resolve(card.publicKey, hint: nil)
        let state = try await resolver.state(of: card.publicKey)
        let predicted = try accounts.predictedAddress(for: card.publicKey)
        let deployed = try await client.isDeployed(predicted)

        var fee: UInt32?
        var deploymentError: String?
        if !deployed {
            do {
                fee = try await accounts.simulateDeployment(for: card)
            } catch {
                deploymentError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
        }

        var balances: [CardDiagnostics.AssetBalance] = []
        if let pocket = state.pocket {
            let source = try await client.account(config.feePayer)
            let sac = SACClient(client: client)
            let assets: [(String, Asset)] = [
                ("XLM", Asset(type: AssetType.ASSET_TYPE_NATIVE)!),
                ("USDC", Asset(type: AssetType.ASSET_TYPE_CREDIT_ALPHANUM4, code: "USDC", issuer: try KeyPair(accountId: config.usdcIssuer))!),
            ]
            for (code, asset) in assets {
                let token = try SACClient.contractID(for: asset, network: client.network)
                let units = try await sac.balance(token: token, holder: pocket, source: source)
                balances.append(.init(code: code, amount: units.map(SACClient.amount(fromUnits:))))
            }
        }

        return CardDiagnostics(
            resolution: resolution, state: state, predictedAccount: predicted, accountDeployed: deployed,
            deploymentFee: fee, deploymentError: deploymentError, pocketBalances: balances
        )
    }
}

/// Faux diagnostic pour le simulateur : aucune requête réseau.
struct MockCardDiagnostics: CardDiagnosing {
    var delay: Duration = .milliseconds(800)

    func diagnose(_ card: ChipKeyInfo) async throws -> CardDiagnostics {
        let resolver = MockCardResolver(delay: delay)
        let state = try await resolver.state(of: card.publicKey)
        return CardDiagnostics(
            resolution: try await resolver.resolve(card.publicKey, hint: nil),
            state: state,
            predictedAccount: try ChimpAccountClient.predictedAddress(
                feePayer: ChimpNetworkConfig.testnet.feePayer, publicKey: card.publicKey, network: .testnet
            ),
            accountDeployed: false,
            deploymentFee: 1_234_567,
            deploymentError: nil,
            pocketBalances: [.init(code: "XLM", amount: 0), .init(code: "USDC", amount: 0)]
        )
    }
}
#endif
