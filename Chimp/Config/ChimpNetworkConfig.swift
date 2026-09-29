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
        usdcIssuer: "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5"
    )
}
