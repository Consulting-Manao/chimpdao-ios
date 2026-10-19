import Foundation

/// Réseaux, contrats et URLs de ChimpDAO. **Seul endroit** où ces valeurs sont écrites (CLAUDE.md, « Config/ »).
/// Valeurs testnet transmises par Pamphile le 2026-09-29, identiques à `reference/terminal/src/chain/contracts.ts`.
struct ChimpNetworkConfig: Equatable, Sendable {
    let network: StellarNetwork
    let passphrase: String
    let endpoints: Endpoints
    let contracts: Contracts
    /// Serveur qui signe les frais (Cloudflare Worker, ARCHITECTURE §3.3). Pour l'onboarding :
    /// l'enregistrement (mint) ne l'utilise pas, c'est l'admin qui paie.
    let feeSignerURL: URL
    /// Compte G du payeur de frais (clé **publique** seulement, `VITE_STELLAR_FEE_PUBLIC` du terminal) :
    /// source de toutes les transactions payées par le serveur de frais, et déployeur des Main accounts
    /// (l'adresse d'un Main account en dépend, ARCHITECTURE §3.5). Transmis par Pamphile le 2026-09-29.
    let feePayer: String
    /// Émetteur de l'USDC du réseau (`USDC_ISSUER` de `chain/assets.ts`, ARCHITECTURE §2.4).
    let usdcIssuer: String
    /// Testnet seulement : où obtenir de l'USDC de test à la main (`faucet` de l'USDC dans `chain/assets.ts`).
    /// `nil` sur mainnet (« mainnet: USDC must not carry a faucet »).
    let usdcFaucet: URL?
    /// Repère de l'horloge des ledgers (revue de sécurité F3) : un ledger vu fermé à une heure connue. Sans repère, le
    /// plafond ne s'appuie que sur le dernier ledger vu par ce téléphone.
    var ledgerAnchor: LedgerAnchor? = nil
    /// Fonctions proposées sur ce réseau (décision de Barth du 2026-10-19) : sur le mainnet, toutes éteintes pour
    /// l'instant (rien de visible, aucun onglet en erreur).
    var features: NetworkFeatures

    struct Endpoints: Equatable, Sendable {
        let rpc: URL
        let horizon: URL
        let explorer: URL
        let friendbot: URL?
    }

    struct Contracts: Equatable, Sendable {
        /// `pocket-factory`.
        let factory: String
        /// Registre des campagnes NFT (`collection`).
        let collection: String
        /// `nfc-nft` de la campagne par défaut (testnet : `chi4`).
        let nfcNft: String
        /// Hash du wasm du Chimp account déjà installé.
        let accountWasmHash: String
        /// Routeur d'appels groupés.
        let router: String
        /// Admin des contrats (`chimp-agent`, `chimp-contracts/.config/stellar/`, ARCHITECTURE §2.4).
        /// Sert seulement à avertir si la clé saisie dans le mode admin n'est pas celle-ci.
        let admin: String
    }

    /// Page de l'explorateur pour une transaction (`explorerTx` dans `chain/env.ts`).
    func explorerURL(transactionHash: String) -> URL {
        endpoints.explorer.appending(path: "tx").appending(path: transactionHash)
    }

    static let testnet = ChimpNetworkConfig(
        network: .testnet,
        passphrase: "Test SDF Network ; September 2015",
        endpoints: Endpoints(
            rpc: URL(string: "https://soroban-testnet.stellar.org")!,
            horizon: URL(string: "https://horizon-testnet.stellar.org")!,
            explorer: URL(string: "https://stellar.expert/explorer/testnet")!,
            friendbot: URL(string: "https://friendbot.stellar.org")!
        ),
        contracts: Contracts(
            factory: "CDWPHF7DRJ37GLFZGQDSO6RTX4QR75WTNKJUMFJRETQLIOAHFBU6RGYR",
            collection: "CDGFNWFN7ZKU4XDPNXOGDQ4JZ7SZCMXLL3PYFESOCCA2L5DM3ZBCPEKC",
            nfcNft: "CC6Z7JDXX2RXULI2TMY7OGJJ57WXTBRCQDRR4W4IFEJZZ7SPGCPYJEJT",
            accountWasmHash: "044275ac1be3fd505922fb0c564370331753fe808e31990b7e74ebf395614271",
            router: "CAOL3K7VQTDZELQMKTAJB3WUQGL5JLXJKZ2Y44F77NH4CZNLW5I755XI",
            admin: "GBLWPGXVH47YGMODIUHZJ7FETRISFU3TB7JGADTRIMU36OLWJ7PYEZ6M"
        ),
        feeSignerURL: URL(string: "https://chimpdao-signer.tansu-964.workers.dev/")!,
        feePayer: "GDZE7UWGO3PS6R6RI6F3XIJLX7WGIEFD3X4YQO4AJH4LS3KDY6LLFXG2",
        usdcIssuer: "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5",
        usdcFaucet: URL(string: "https://faucet.circle.com/")!,
        // Ledger 5 223 554, fermé le 2026-10-16 à 09:02:37 UTC (retrait XOXNO de la carte n°7, lu sur la chaîne).
        ledgerAnchor: LedgerAnchor(ledger: 5_223_554, time: Date(timeIntervalSince1970: 1_792_141_357)),
        features: .all
    )

    /// Etherfuse (CETES), seulement si la fonction est allumée sur ce réseau : le seul accès à sa configuration.
    var etherfuse: IntegrationConfig.Etherfuse? { features.cetes ? integrations?.etherfuse : nil }
}

/// Les fonctions de l'app qu'on peut allumer ou éteindre pour chaque réseau, séparément.
struct NetworkFeatures: Equatable, Sendable {
    /// Swap (E3 à E6) : tuile du Wallet, bouton des tiroirs, « Swap again ».
    var swap: Bool
    /// Grow : l'onglet, les tuiles et le bouton des tiroirs, « See my position ».
    var grow: Bool
    /// « Add money » : depuis une autre blockchain (NEAR Intents, ROZO, CCTP).
    var addMoney: Bool
    /// CETES (Etherfuse) : l'actif, son prix, son pot dans Grow.
    var cetes: Bool
    /// Cartes DUOX acceptées (création de compte, ajout, reconnexion, carte qui dit oui). Éteint tant que F1 n'est pas
    /// fait (revue de sécurité : une DUOX ne signe que 16 octets du digest ; décision de Pamphile du 2026-10-19).
    var duoxCards: Bool

    static let all = NetworkFeatures(swap: true, grow: true, addMoney: true, cetes: true, duoxCards: true)
    static let none = NetworkFeatures(swap: false, grow: false, addMoney: false, cetes: false, duoxCards: false)
}

// MARK: Configuration de ce build

extension ChimpNetworkConfig {
    /// La configuration de ce build, la seule de l'app (décision de Barth du 2026-10-19) : Debug et Testing → testnet,
    /// Release → mainnet. Choisie par la condition de compilation `CHIMP_TESTNET` (`project.pbxproj`, Debug et Testing
    /// seulement). Passée partout depuis `AppSession` : aucun service ne choisit son réseau lui-même.
    /// Mainnet incomplet : une erreur qui empêche l'app de démarrer, **jamais** un retour au testnet.
    static func forThisBuild() throws -> ChimpNetworkConfig {
        #if CHIMP_TESTNET
        .testnet
        #else
        try mainnetDraft.complete()
        #endif
    }

    /// Mainnet. Les valeurs que ChimpDAO n'a pas encore sont **vides** (`nil`) : contrats à déployer par Pamphile
    /// (`reference/chimp-contracts/docs/MAINNET-MIGRATION.md`), serveur de frais de production, repère de l'horloge
    /// (à lire sur un ledger mainnet ; celui du testnet ferait refuser toutes les signatures). Valeurs connues reprises
    /// de `reference/terminal/src/chain/contracts.ts` et `assets.ts` (bloc `mainnet`).
    static let mainnetDraft = NetworkConfigDraft(
        network: .mainnet,
        passphrase: "Public Global Stellar Network ; September 2015",
        rpc: URL(string: "https://rpc.lightsail.network")!,
        horizon: URL(string: "https://horizon.stellar.org")!,
        explorer: URL(string: "https://stellar.expert/explorer/public")!,
        friendbot: nil,
        // `make contract_deploy_factory network=mainnet`.
        factory: nil,
        // L'ancienne collection mainnet (`CCWQBP7U…7Y5Z`) est oubliée par la migration : la nouvelle vient du redéploiement.
        collection: nil,
        // `make contract_create_collection symbol=<campagne> network=mainnet` (l'ancien `chi1` est incompatible).
        nfcNft: nil,
        // `make contract_upload_account network=mainnet`.
        accountWasmHash: nil,
        // `make contract_deploy_router network=mainnet`.
        router: nil,
        // Admin mainnet actuel (ARCHITECTURE §2.4) ; seulement pour l'avertissement du mode admin, absent de la Release.
        admin: "GAEUFBE244A4MFUCMGUPMHJ26MPHMDJSY4XX3UMKNVT4QTLSQHDPTN23",
        // Serveur de frais de production (URL ChimpDAO) et son payeur de frais : à fournir par Pamphile.
        feeSignerURL: nil,
        feePayer: nil,
        usdcIssuer: "GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN",
        usdcFaucet: nil,
        // Un ledger mainnet et son heure de fermeture, lus sur la chaîne.
        ledgerAnchor: nil,
        // Swap, Grow, Add money et CETES éteints sur le mainnet pour l'instant, DUOX refusées tant que F1 n'est pas fait
        // (décisions du 2026-10-19).
        features: .none
    )
}

/// Une configuration réseau en cours de remplissage : `nil` = pas encore connu. `complete()` refuse tant qu'une
/// valeur manque, et dit lesquelles (comme `required` dans `chain/contracts.ts` du terminal).
struct NetworkConfigDraft: Equatable, Sendable {
    let network: StellarNetwork
    let passphrase: String
    let rpc: URL
    let horizon: URL
    let explorer: URL
    let friendbot: URL?
    let factory: String?
    let collection: String?
    let nfcNft: String?
    let accountWasmHash: String?
    let router: String?
    let admin: String?
    let feeSignerURL: URL?
    let feePayer: String?
    let usdcIssuer: String?
    let usdcFaucet: URL?
    let ledgerAnchor: LedgerAnchor?
    let features: NetworkFeatures

    /// Les valeurs qui manquent encore, par leur nom.
    var missing: [String] {
        let required: [(String, Any?)] = [
            ("contracts.factory", factory), ("contracts.collection", collection), ("contracts.nfcNft", nfcNft),
            ("contracts.accountWasmHash", accountWasmHash), ("contracts.router", router), ("contracts.admin", admin),
            ("feeSignerURL", feeSignerURL), ("feePayer", feePayer), ("usdcIssuer", usdcIssuer), ("ledgerAnchor", ledgerAnchor),
        ]
        return required.compactMap { name, value in
            if let text = value as? String { return text.isEmpty ? name : nil }
            return value == nil ? name : nil
        }
    }

    func complete() throws -> ChimpNetworkConfig {
        guard missing.isEmpty, let factory, let collection, let nfcNft, let accountWasmHash, let router, let admin,
              let feeSignerURL, let feePayer, let usdcIssuer, let ledgerAnchor else {
            throw NetworkConfigError.incomplete(network: network, missing: missing)
        }
        return ChimpNetworkConfig(
            network: network, passphrase: passphrase,
            endpoints: .init(rpc: rpc, horizon: horizon, explorer: explorer, friendbot: friendbot),
            contracts: .init(factory: factory, collection: collection, nfcNft: nfcNft, accountWasmHash: accountWasmHash, router: router, admin: admin),
            feeSignerURL: feeSignerURL, feePayer: feePayer, usdcIssuer: usdcIssuer, usdcFaucet: usdcFaucet, ledgerAnchor: ledgerAnchor,
            features: features
        )
    }
}

enum NetworkConfigError: Error, Equatable, LocalizedError {
    /// Des valeurs du réseau manquent : l'app ne démarre pas (écran « This build isn't ready »).
    case incomplete(network: StellarNetwork, missing: [String])

    var errorDescription: String? {
        switch self {
        case let .incomplete(network, missing):
            "The \(network.rawValue) configuration is incomplete: \(missing.joined(separator: ", "))."
        }
    }
}

/// Oracles de prix Reflector (SEP-40), **toujours sur mainnet et en lecture seule**, quel que soit le réseau de l'app
/// (décision du 2026-09-29, DESIGN_NOTES §12). Valeurs de `reference/terminal/src/chain/prices.ts`.
struct PriceOracleConfig: Equatable, Sendable {
    /// RPC mainnet utilisé par le terminal pour les prix (Quasar).
    let rpc: URL
    let passphrase: String
    /// Flux « CEX & DEX », base USD.
    let cexFeed: String
    /// Flux « FX rates », base USD (repli pour les codes de devises).
    let fxFeed: String
    /// Compte source des simulations (`SIM_SOURCE`) : n'importe quelle adresse G valide, jamais lue ni utilisée pour envoyer.
    let simulationSource: String
    /// Échelle des prix des flux : 14 décimales (`ORACLE_ONE`).
    let decimals: Int
    /// Durée de validité d'un prix lu : l'échantillonnage des flux, 5 minutes (`RATES_TTL_MS`).
    let cacheDuration: Duration
    /// Stablecoins comptés à exactement 1 $ (`STABLE_USD`, décision produit : USDC = 1 $).
    let stableUSD: Set<String>
    /// Codes jamais demandés à Reflector : les stablebonds d'Etherfuse n'ont de prix que par l'API d'Etherfuse, pour
    /// l'affichage (décision de Barth du 2026-10-14). Un autre « CETES » coté ailleurs ne serait pas le nôtre.
    var neverPriced: Set<String> = ["CETES"]

    static let reflector = PriceOracleConfig(
        rpc: URL(string: "https://rpc.lightsail.network")!,
        passphrase: "Public Global Stellar Network ; September 2015",
        cexFeed: "CAFJZQWSED6YAWZU3GWRTOCNPPCGBN32L7QV43XX5LZLFTK6JLN34DLN",
        fxFeed: "CBKGPWGKSKZF52CFHMTRR23TBWTPMRDIYZ4O2P5VS65BMHYH4DXMCJZC",
        simulationSource: "GAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAWHF",
        decimals: 14,
        cacheDuration: .seconds(5 * 60),
        stableUSD: ["USDC", "RLUSD", "USDT", "DAI", "PYUSD"]
    )
}
