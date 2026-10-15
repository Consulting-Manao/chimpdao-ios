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
        usdcFaucet: URL(string: "https://faucet.circle.com/")!
    )
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
