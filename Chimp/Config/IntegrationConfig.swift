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

    /// Ondo USDY (décision de Barth du 2026-11-05) : un dollar qui rapporte (bons du Trésor américain). Son **prix monte**,
    /// il ne verse rien : comme les CETES, il s'obtient et se rend par swap, sans émission ni rachat (KYC d'Ondo), et l'app
    /// montre l'évolution de son prix. Réservé aux personnes non américaines (conditions d'Ondo).
    ///
    /// Mainnet : `USDY:GAJMPX5N…TADAZ6` (home domain `ondo.finance`), révocable et clawback, SAC `CB3YA656…`. Pas de
    /// testnet officiel : copie de test (`tools/grow-testnet`), d'un émetteur aux **mêmes pouvoirs**, avec une paire
    /// Soroswap USDC/USDY au prix RedStone du jour de sa création.
    struct Ondo: Equatable, Sendable {
        let issuer: String
        let usdy: Stablebond
    }

    /// Sentora (décision de Barth du 2026-11-05) : un vault qui garde le montant déposé et paie, en fin de période, un taux
    /// publié par Sentora (récompenses réclamées avec une preuve de son serveur ; retirer avant la fin les fait perdre).
    /// Mainnet : vaults USDC `CAHEWHOP…`, XLM `CA54LVHM…`, PYUSD `CAQRAXBU…`, escrow `CCZSNGVM…`. Pas de testnet officiel :
    /// copie de test (`tools/grow-testnet`), **le même wasm** copié depuis le mainnet (`ca6b85a1…`, escrow `f22e4a52…`).
    /// L'app propose le vault USDC (un pot par protocole) ; le vault XLM de test existe aussi.
    struct Sentora: Equatable, Sendable {
        let vault: String
        /// Code de l'actif du vault, parmi ceux de l'app.
        let assetCode: String
        let name: String
        let escrow: String
    }

    /// RedStone (SEP-40, **mainnet**, lecture seule) : prix indicatif des actifs que ni Reflector ni leur émetteur ne
    /// donnent (USDY). `lastprice(Asset::Stellar(contrat))`, 8 décimales, relevé le 2026-11-05 (1 USDY ≈ 1,152 $). Contrat
    /// listé par la documentation de Stellar (« Oracle providers », RedStone). Affichage seulement, jamais pour signer.
    struct RedStone: Equatable, Sendable {
        let rpc: URL
        let passphrase: String
        let oracle: String
        let decimals: Int
        /// Le contrat **du vrai actif sur le mainnet**, par code : une copie de test n'a pas de prix à elle.
        let mainnetAssets: [String: String]
        /// Au-delà, le prix est trop vieux pour être affiché (RedStone publie au moins toutes les 12 à 24 h).
        let maximumAge: TimeInterval
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

    /// XOXNO (prêt sur Stellar, phase 7, décision de Barth du 2026-10-16) : **dépôt et retrait seulement, jamais d'emprunt**,
    /// USDC seulement, testnet seulement. Aucun audit publié de ses contrats Stellar : **pas de mainnet sans audit Stellar
    /// publié et sans l'accord de Pamphile**, ni sans la prolongation des positions (`renew_account`). Adresses du dépôt
    /// `XOXNO/rs-lending-xlm` (`configs/networks.json`, commit `76c31ab`), relues sur la chaîne le 2026-10-16 (code du
    /// contrôleur `52ed959d…`, de la réserve `0be54b45…`). Absent de `reference/`.
    struct Xoxno: Equatable, Sendable {
        /// Le contrôleur : `supply`, `withdraw` et les lectures de position.
        let controller: String
        /// La réserve commune : reçoit les dépôts (`transfer` du tiroir vers elle), paie les retraits.
        let pool: String
        /// Le jeton de position (NFT OpenZeppelin « Enumerable ») : qui le détient contrôle la position.
        let positionNFT: String
        /// Le marché proposé : son actif (code de l'app) et son hub.
        let assetCode: String
        let hubID: UInt32
        /// Le profil de risque des positions créées par l'app (1, « Blue Chip »).
        let spokeID: UInt32
        let name: String
    }

    let soroswap: Soroswap
    let aquarius: Aquarius
    let defindexVaults: [DeFindexVault]
    let etherfuse: Etherfuse
    let cctp: CCTP
    let nearIntents: NearIntents
    let rozo: Rozo
    let xoxno: Xoxno
    let ondo: Ondo
    let redstone: RedStone
    let sentora: Sentora

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
        ),
        xoxno: Xoxno(
            controller: "CCXRWJ6SIU2WPFEGLFGJVITPL57QAYIMIO6OAM2NBGNDQSSCK2FFV3F3",
            pool: "CBSGF6QOQAMPFBEVSYPEQHSZRIHJ6RCGUPCRDMUX36DEKRWFAO2PZB5A",
            positionNFT: "CDVN5JU675MEDPVRPCYC45AHFC275UH57WEU5OTFE4WFGZBNN7HTLPSY",
            assetCode: "USDC", hubID: 1, spokeID: 1, name: "XOXNO USDC"
        ),
        // Copie de test du 2026-11-05 (`tools/grow-testnet`) : émetteur révocable + clawback, comme celui d'Ondo.
        ondo: Ondo(
            issuer: "GCSNYZ25ZBQJVHLOAPONBUKDXFLD5WCMETW75QNV3LO2NQMBTSUWP2DQ",
            usdy: Stablebond(code: "USDY", contract: "CBHI53SV3OMRU3TJPCUHEORL6O2OD4W4CKYUNUV2YPLLA7UYTGYEUZWI")
        ),
        redstone: RedStone(
            rpc: URL(string: "https://rpc.lightsail.network")!,
            passphrase: "Public Global Stellar Network ; September 2015",
            oracle: "CBMGLKUQZVSAIL5CPDDAWSUY7MAKXISHMOZEVLMBUWBMFGHRJSR4WYRF",
            decimals: 8,
            mainnetAssets: ["USDY": "CB3YA656OYIHU57657I5KGSBRHE5I3OZU4VFC22PYAOANFZHEWNYGAGP"],
            maximumAge: 36 * 3600
        ),
        // Copie de test du 2026-11-05 (`tools/grow-testnet`), même wasm que le mainnet ; dépôt et retrait vérifiés.
        sentora: Sentora(
            vault: "CDGXALH6TAXVN3G26TQYMH7ORXESODQQHXL2BNGMZEC4BP5NMHMIAL2V", assetCode: "USDC", name: "Sentora USDC",
            escrow: "CD4P36A22VCGWUWV4Z6WU3SAFCJTO7HEQWF5Y6R7DWLTFKQ6TI7QHWE5"
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
        if (try? KeyPair(accountId: ondo.issuer)) == nil { problems.append("ondo.issuer is not a G-address") }
        address("ondo.\(ondo.usdy.code)", ondo.usdy.contract)
        let usdy = Asset(canonicalForm: "\(ondo.usdy.code):\(ondo.issuer)")
        if usdy.flatMap({ try? SACClient.contractID(for: $0, network: .custom(passphrase: passphrase)) }) != ondo.usdy.contract {
            problems.append("ondo.\(ondo.usdy.code) is not the SAC of \(ondo.usdy.code):\(ondo.issuer)")
        }
        address("sentora.vault", sentora.vault)
        address("sentora.escrow", sentora.escrow)
        if !knownAssetCodes.contains(sentora.assetCode) { problems.append("sentora names unknown asset \"\(sentora.assetCode)\"") }
        if redstone.rpc.scheme != "https" { problems.append("redstone.rpc is not https") }
        if !redstone.oracle.hasPrefix("C") || (try? SCAddressXDR(contractId: redstone.oracle)) == nil { problems.append("redstone.oracle is not a C-address") }
        for (code, contract) in redstone.mainnetAssets where !contract.hasPrefix("C") || (try? SCAddressXDR(contractId: contract)) == nil {
            problems.append("redstone.mainnetAssets[\(code)] is not a C-address")
        }
        address("cctp.forwarder", cctp.forwarder)
        address("cctp.tokenMessengerMinter", cctp.tokenMessengerMinter)
        address("cctp.messageTransmitter", cctp.messageTransmitter)
        if cctp.sourceChains[cctp.localDomain] != nil { problems.append("cctp.sourceChains names Stellar's own domain") }
        if nearIntents.api.scheme != "https" { problems.append("nearIntents.api is not https") }
        if (try? KeyPair(accountId: nearIntents.quoteRecipient)) == nil { problems.append("nearIntents.quoteRecipient is not a G-address") }
        address("xoxno.controller", xoxno.controller)
        address("xoxno.pool", xoxno.pool)
        address("xoxno.positionNFT", xoxno.positionNFT)
        if !knownAssetCodes.contains(xoxno.assetCode) { problems.append("xoxno names unknown asset \"\(xoxno.assetCode)\"") }
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
