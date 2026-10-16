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

    /// Circle CCTP V2 (D4) : arrivées d'USDC depuis une autre blockchain. Le transfert se lance et se finalise sur le site
    /// (`/fund`, décision de Barth du 2026-10-15) ; l'app ne signe jamais rien d'Ethereum, elle reconnaît l'arrivée.
    /// Adresses vérifiées sur testnet le 2026-10-15 (interfaces lues sur la chaîne, forwarder relié à ces deux contrats).
    struct CCTP: Equatable, Sendable {
        /// `CctpForwarder` : reçoit le mint et le transfère au destinataire du hook data (`mint_and_forward`).
        let forwarder: String
        let tokenMessengerMinter: String
        let messageTransmitter: String
        /// Domaine CCTP de Stellar.
        let localDomain: UInt32
        /// Domaines d'origine connus (« Supported chains and domains » de Circle) ; un autre domaine reste « another chain ».
        let sourceChains: [UInt32: String]
    }

    /// NEAR Intents (D4, voie de repli du grant) : **devis à blanc seulement**, dans l'app (décision de Barth du 2026-10-15).
    /// Pas de testnet (Stellar mainnet seulement) ; une adresse de carte (C…) est refusée.
    struct NearIntents: Equatable, Sendable {
        /// API 1Click, publique, sans clé.
        let api: URL
        /// Destinataire du devis : un compte G de ChimpDAO (le payeur de frais), puisque les adresses de carte sont refusées.
        /// Aucun dépôt n'est jamais demandé : rien ne peut partir vers lui.
        let quoteRecipient: String
        /// Compte de remboursement exigé par un devis `INTENTS` (le contrat de NEAR Intents) ; jamais utilisé.
        let refundAccount: String
    }

    /// ROZO (D4, décision de Barth du 2026-10-16) : un **intermédiaire de confiance**. L'utilisateur envoie de l'USDC depuis
    /// son propre wallet à une adresse de dépôt de ROZO ; ROZO paie ensuite le tiroir sur Stellar depuis son propre stock
    /// (un `transfer` du SAC, que la carte ne signe pas). Entre les deux, l'argent est chez ROZO. L'app ne signe jamais rien
    /// d'une autre blockchain : elle crée la commande, montre l'adresse de dépôt et suit **sa** commande. Absent de
    /// `reference/` ; API publique sans clé (`docs.rozo.ai`, « Testnet: Base Sepolia → Stellar »), revérifiée le 2026-10-16.
    struct Rozo: Equatable, Sendable {
        /// API de paiement (`…/payment-api`).
        let api: URL
        /// Identifiant d'application exigé dans chaque commande. Testnet : celui de la démo publique (décision du
        /// 2026-10-16) ; demander le nôtre sur partners.rozo.ai avant le mainnet (ROADMAP).
        let appId: String
        /// La seule chaîne d'origine proposée, et son nom affiché (« from Base »).
        let sourceChainId: String
        let sourceChainName: String
        /// Le réseau d'origine tel que l'utilisateur doit le choisir dans son wallet (« Base Sepolia » sur testnet).
        let sourceNetworkName: String
        /// USDC de la chaîne d'origine : une commande qui en nomme un autre est refusée.
        let sourceToken: String
        /// Identifiant de Stellar chez ROZO, et l'USDC livré (`CODE:émetteur`) : une commande qui en nomme un autre est refusée.
        let stellarChainId: String
        let stellarToken: String
        /// Bornes d'un montant (testnet : 0,01 à 1 USDC).
        let minimumAmount: Decimal
        let maximumAmount: Decimal
        /// Comptes G qui paient les arrivées sur Stellar : un `transfer` venu de l'un d'eux vers un tiroir est une arrivée
        /// ROZO (« ARRIVED · from Base · via ROZO »). Relevé sur la chaîne le 2026-10-16 (paiement de la commande
        /// `pay_ewHL66ke5XdqP7GLZ8xnkVPh`, transaction `e7eedc04…4572`).
        let payoutAccounts: [String]
    }

    let soroswap: Soroswap
    let aquarius: Aquarius
    let defindexVaults: [DeFindexVault]
    let etherfuse: Etherfuse
    let cctp: CCTP
    let nearIntents: NearIntents
    let rozo: Rozo

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
        ),
        cctp: CCTP(
            forwarder: "CA66Q2WFBND6V4UEB7RD4SAXSVIWMD6RA4X3U32ELVFGXV5PJK4T4VSZ",
            tokenMessengerMinter: "CDNG7HXAPBWICI2E3AUBP3YZWZELJLYSB6F5CC7WLDTLTHVM74SLRTHP",
            messageTransmitter: "CBJ6MTCKKZG73PMDZCJMSFRD7DQEMI4FKDH7CGDSV4W6FHCRBCQAVVJY",
            localDomain: 27,
            sourceChains: [0: "Ethereum", 1: "Avalanche", 5: "Solana", 6: "Base", 26: "Arc"]
        ),
        nearIntents: NearIntents(
            api: URL(string: "https://1click.chaindefuser.com")!,
            quoteRecipient: "GDZE7UWGO3PS6R6RI6F3XIJLX7WGIEFD3X4YQO4AJH4LS3KDY6LLFXG2",
            refundAccount: "intents.near"
        ),
        rozo: Rozo(
            api: URL(string: "https://intentapitestnet.rozo.ai/functions/v1/payment-api")!,
            appId: "rozoDemo",
            sourceChainId: "84532", sourceChainName: "Base", sourceNetworkName: "Base Sepolia",
            sourceToken: "0x036cbd53842c5426634e7929541ec2318f3dcf7e",
            stellarChainId: "1500", stellarToken: "USDC:GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5",
            minimumAmount: Decimal(string: "0.01")!, maximumAmount: 1,
            payoutAccounts: ["GABWCTTOFK3TBVDLMVZER6JBXLOOCZ6PFDIUSYYU5GTJXP2CPMUYCQ37"]
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
        address("cctp.forwarder", cctp.forwarder)
        address("cctp.tokenMessengerMinter", cctp.tokenMessengerMinter)
        address("cctp.messageTransmitter", cctp.messageTransmitter)
        if cctp.sourceChains[cctp.localDomain] != nil { problems.append("cctp.sourceChains names Stellar's own domain") }
        if nearIntents.api.scheme != "https" { problems.append("nearIntents.api is not https") }
        if (try? KeyPair(accountId: nearIntents.quoteRecipient)) == nil { problems.append("nearIntents.quoteRecipient is not a G-address") }
        if rozo.api.scheme != "https" { problems.append("rozo.api is not https") }
        if rozo.payoutAccounts.isEmpty { problems.append("rozo names no payout account") }
        for account in rozo.payoutAccounts where (try? KeyPair(accountId: account)) == nil {
            problems.append("rozo.payoutAccounts has a non-G address: \"\(account)\"")
        }
        if !(rozo.minimumAmount > 0 && rozo.minimumAmount <= rozo.maximumAmount) { problems.append("rozo amount bounds are inverted") }
        if rozo.sourceToken.range(of: "^0x[0-9a-fA-F]{40}$", options: .regularExpression) == nil { problems.append("rozo.sourceToken is not an EVM address") }
        return problems
    }
}

extension ChimpNetworkConfig {
    /// Les intégrations DeFi de ce réseau (`nil` sur mainnet).
    var integrations: IntegrationConfig? { .for(network) }
}
