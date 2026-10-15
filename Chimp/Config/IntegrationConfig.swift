import Foundation
import stellarsdk

/// Contrats des intégrations DeFi de la tranche 2. **Seul endroit** où ces adresses sont écrites (CLAUDE.md, « Config/ »).
/// Relevées et vérifiées sur testnet à l'audit du 2026-10-14 (`docs/TRANCHE2_SPEC.md`, « Adresses testnet »), décisions
/// de Barth du même jour. Testnet seulement : aucune intégration sur mainnet (`for(.mainnet)` rend `nil`).
///
/// Le contrat de réclamation (prize) est reporté à la phase D5 et n'apparaît pas ici.
struct IntegrationConfig: Equatable, Sendable {
    /// Soroswap redéploie son testnet de temps en temps (dernière fois le 2025-12-22) : quand les devis échouent, relire
    /// `public/testnet.contracts.json` de soroswap/core (jamais lu par l'app : une URL GitHub n'est pas une source de
    /// confiance pour une adresse où part de l'argent, comme dans le terminal).
    struct Soroswap: Equatable, Sendable {
        let router: String
        let factory: String
    }

    /// Routes uniquement sur la chaîne (pools directs, plus un saut via l'USDC), sans l'API `find-path` (décision du
    /// 2026-10-14). Les pools sont recréés après chaque remise à zéro du testnet : ils sont lus (`get_pools`), pas écrits ici.
    struct Aquarius: Equatable, Sendable {
        let router: String
    }

    /// Un vault DeFindex proposé : une liste choisie, jamais toute l'usine (`defindexVaults` du terminal).
    struct DeFindexVault: Equatable, Sendable {
        let vault: String
        /// Code de l'actif du vault, parmi ceux de l'app (vérifié sur la chaîne avec `get_assets` avant tout dépôt).
        let assetCode: String
        /// Nom affiché.
        let name: String
        /// Protocoles sous-jacents, toujours affichés avec l'avertissement (principe 6).
        let underlyingProtocols: [String]
        /// Stratégie du vault (lue sur la chaîne par `get_assets`, gardée ici pour la prolongation de sa durée de vie en
        /// mode admin).
        var strategy: String? = nil
    }

    struct Stablebond: Equatable, Sendable {
        let code: String
        /// SAC du stablebond (`Asset(code, émetteur).contractId`).
        let contract: String
    }

    /// Etherfuse, version légère : stablebonds obtenus par swap et affichés ; ni émission ni rachat (KYC).
    struct Etherfuse: Equatable, Sendable {
        /// Émetteur sandbox (`sand.etherfuse.com`). Clawback activé : l'émetteur peut reprendre ou geler les jetons.
        let issuer: String
        let stablebonds: [Stablebond]
        /// API publique d'Etherfuse, sans clé (points d'accès `/lookup/…`, « Public. No API key required. » dans
        /// `openapi-v2.json`, vérifié le 2026-10-15) : **affichage uniquement**, jamais pour signer, avec la source, la
        /// date et la mention « prix indicatif » (décision du 2026-10-14). Ni le SDEX ni les pools. Testnet : la sandbox,
        /// la seule qui connaît l'émetteur `GC3CW7…UPS4` (la production répond « Stablebond not found »).
        let priceAPI: URL
    }

    let soroswap: Soroswap
    let aquarius: Aquarius
    let defindexVaults: [DeFindexVault]
    let etherfuse: Etherfuse

    static let testnet = IntegrationConfig(
        soroswap: Soroswap(
            router: "CCJUD55AG6W5HAI5LRVNKAE5WDP5XGZBUDS5WNTIVDU7O264UZZE7BRD",
            factory: "CDP3HMUH6SMS3S7NPGNDJLULCOXXEPSHY4JKUKMBNQMATHDHWXRRJTBY"
        ),
        aquarius: Aquarius(router: "CBCFTQSPDBAIZ6R6PJQKSQWKNKWH2QIV3I4J72SHWBIK3ADRRAM5A6GD"),
        // Le seul vault retenu : sa stratégie unique (`CDVLOSPJ…`) passe par le pool Blend `CCEBVDYM…`, actif sur testnet.
        // Le vault USDC est exclu : son actif est l'USDC factice de Blend, pas celui de Circle. Durée de vie à prolonger
        // avant la mi-novembre 2026 (expiration relevée vers le ledger 5 705 300, ROADMAP).
        defindexVaults: [
            DeFindexVault(
                vault: "CCLV4H7WTLJQ7ATLHBBQV2WW3OINF3FOY5XZ7VPHZO7NH3D2ZS4GFSF6",
                assetCode: "XLM", name: "XLM vault", underlyingProtocols: ["DeFindex", "Blend"],
                strategy: "CDVLOSPJPQOTB6ZCWO5VSGTOLGMKTXSFWYTUP572GTPNOWX4F76X3HPM"
            ),
        ],
        etherfuse: Etherfuse(
            issuer: "GC3CW7EDYRTWQ635VDIGY6S4ZUF5L6TQ7AA4MWS7LEQDBLUSZXV7UPS4",
            stablebonds: [Stablebond(code: "CETES", contract: "CC72F57YTPX76HAA64JQOEGHQAPSADQWSY5DWVBR66JINPFDLNCQYHIC")],
            priceAPI: URL(string: "https://api.sand.etherfuse.com")!
        )
    )

    /// Les intégrations du réseau, `nil` s'il n'en a aucune (mainnet).
    static func `for`(_ network: StellarNetwork) -> IntegrationConfig? {
        network == .testnet ? .testnet : nil
    }

    /// Tout ce qui doit être vrai de la table entière (`contractsProblems` du terminal) : adresses C et G valides, aucune
    /// adresse répétée (ni ici ni parmi `reserved`, les contrats de ChimpDAO), actifs de vault connus, et chaque
    /// stablebond au SAC calculé depuis son code et son émetteur. Vide = rien à signaler.
    func problems(passphrase: String, knownAssetCodes: Set<String>, reserved: [String]) -> [String] {
        var problems: [String] = []
        var seen = Set(reserved)
        func address(_ name: String, _ value: String) {
            guard value.hasPrefix("C"), (try? SCAddressXDR(contractId: value)) != nil else {
                problems.append("\(name) is not a C-address: \"\(value)\"")
                return
            }
            if !seen.insert(value).inserted { problems.append("\(name) repeats an address used elsewhere") }
        }
        address("soroswap.router", soroswap.router)
        address("soroswap.factory", soroswap.factory)
        address("aquarius.router", aquarius.router)
        for vault in defindexVaults {
            address("defindexVaults[\(vault.name)]", vault.vault)
            if let strategy = vault.strategy { address("defindexVaults[\(vault.name)].strategy", strategy) }
            if !knownAssetCodes.contains(vault.assetCode) {
                problems.append("defindexVaults[\(vault.name)] names unknown asset \"\(vault.assetCode)\"")
            }
            if vault.underlyingProtocols.isEmpty { problems.append("defindexVaults[\(vault.name)] names no underlying protocol") }
        }
        if (try? KeyPair(accountId: etherfuse.issuer)) == nil { problems.append("etherfuse.issuer is not a G-address") }
        for bond in etherfuse.stablebonds {
            address("etherfuse.\(bond.code)", bond.contract)
            let asset = Asset(canonicalForm: "\(bond.code):\(etherfuse.issuer)")
            let expected = asset.flatMap { try? SACClient.contractID(for: $0, network: .custom(passphrase: passphrase)) }
            if expected != bond.contract { problems.append("etherfuse.\(bond.code) is not the SAC of \(bond.code):\(etherfuse.issuer)") }
        }
        if etherfuse.priceAPI.scheme != "https" { problems.append("etherfuse.priceAPI is not https") }
        return problems
    }
}

extension ChimpNetworkConfig {
    /// Les intégrations DeFi de ce réseau (`nil` sur mainnet).
    var integrations: IntegrationConfig? { .for(network) }
}
