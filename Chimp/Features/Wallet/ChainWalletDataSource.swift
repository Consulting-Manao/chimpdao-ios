import Foundation
import stellarsdk

/// Une carte déclarée par le Main account (`cards()` : `CardSigner { curve, key }`).
struct AccountCard: Equatable, Sendable {
    let publicKey: ChipPublicKey
    let curve: ChipCurve

    /// Chaque puce a sa courbe (ARCHITECTURE §0) : secp256k1 = Infineon 2Go, P-256 = DUOX.
    var chip: ChipKind { curve == .p256 ? .duox : .infineon2Go }
}

/// Lectures sur la chaîne dont le Wallet a besoin. `ChainWalletReader` (testnet) dans l'app ; un faux dans les tests.
protocol WalletChain {
    /// `cards()` du Main account : clé et courbe des cartes membres, dans l'ordre du contrat.
    func cards(of account: String) async throws -> [AccountCard]
    /// Soldes XLM et USDC d'une adresse (Main account ou Pocket), en unités de l'actif. Une simulation sans valeur est
    /// une erreur, jamais « zéro ».
    func balances(of address: String) async throws -> [AssetAmount]
    /// Pocket d'une carte (`pocket-factory.get_account`), `nil` si elle n'en a pas.
    func pocket(of card: ChipPublicKey) async throws -> String?
    /// Numéro du NFT de la carte.
    func tokenID(of card: ChipPublicKey) async throws -> UInt32
}

/// Le vrai Wallet, lu sur la chaîne : portage de la partie Stellar de `loadAccountView`
/// (`reference/terminal/src/modules/account/view.ts`). Les cartes sont celles que le **compte** déclare (`cards()`),
/// comme le terminal ; le prénom, le nom, la couleur et le numéro viennent du stockage local quand il les connaît.
/// Prix : USDC = 1 $, XLM et la devise d'affichage par l'oracle Reflector de mainnet (lecture seule). Rien n'est signé
/// ni envoyé.
struct ChainWalletDataSource: WalletDataSource {
    let session: AppSession
    let chain: WalletChain
    let oracle: PriceOracle
    var now: () -> Date = { .now }

    var firstName: String? { session.wallet.firstName }

    enum ReadError: LocalizedError {
        case noAccount

        var errorDescription: String? { "No account is open on this phone." }
    }

    func fetchWallet() async throws -> WalletSnapshot {
        let local = session.wallet
        guard let account = local.account else { throw ReadError.noAccount }

        // Lectures indépendantes, lancées ensemble (le terminal fait de même).
        async let membersRead = chain.cards(of: account.address)
        async let mainRead = chain.balances(of: account.address)
        let members = try await membersRead
        let mainAssets = try await mainRead

        let cards = try await withThrowingTaskGroup(of: (Int, CardBalance).self) { group in
            for (index, member) in members.enumerated() {
                let saved = account.cards.first { $0.publicKey == member.publicKey.hex }
                group.addTask { (index, try await self.card(member, saved: saved)) }
            }
            var result: [(Int, CardBalance)] = []
            for try await entry in group { result.append(entry) }
            return result.sorted { $0.0 < $1.0 }.map(\.1)
        }

        // `cards()` est la meilleure preuve du lien carte → compte : on la garde comme indice (`rememberCardHint`).
        session.rememberCards(members.map(\.publicKey.hex), account: account.address)

        let snapshot = WalletSnapshot(
            currency: session.preferences.currency,
            main: DrawerBalance(assets: mainAssets),
            cards: cards,
            weeklyChange: nil,
            usdPrices: [:],
            fetchedAt: now()
        )
        // Un prix seulement pour les actifs détenus (un solde nul n'a pas besoin de prix, `nonZero` du terminal), plus
        // celui de la devise d'affichage (`usdRates([...holdings, denom])` de `useNetWorth`).
        let held = Set(snapshot.allAssets.filter { $0.amount != 0 }.map(\.code))
        var priced = snapshot
        priced.usdPrices = held.isEmpty ? [:] : await oracle.usdPrices(for: DisplayMoney.priceCodes(held: held, currency: snapshot.currency))
        return priced
    }

    /// Une carte : sa Pocket (mémorisée à l'onboarding, sinon demandée à la factory), ses soldes, son numéro.
    private func card(_ member: AccountCard, saved: SavedCard?) async throws -> CardBalance {
        let key = member.publicKey
        let pocket: String?
        if let known = saved?.pocket {
            pocket = known
        } else {
            pocket = try await chain.pocket(of: key)
        }
        var assets: [AssetAmount] = []
        if let pocket { assets = try await chain.balances(of: pocket) }
        // Le numéro n'est que de l'affichage : une lecture ratée donne « ···· », pas une erreur.
        var tokenID = saved?.tokenID
        if tokenID == nil { tokenID = try? await chain.tokenID(of: key) }
        return CardBalance(
            id: key.hex,
            number: tokenID.map { String(format: "%04u", $0) } ?? "····",
            name: saved?.name ?? String(localized: "Card"),
            color: saved?.color.flatMap(ChimpCardColor.init(rawValue:)) ?? .jungle,
            assets: assets,
            pocket: pocket,
            tokenID: tokenID,
            chip: member.chip
        )
    }
}

/// `WalletChain` sur le réseau de l'app (testnet), avec le payeur de frais comme source des simulations.
final class ChainWalletReader: WalletChain {
    let config: ChimpNetworkConfig
    /// Compte source des simulations, lu une fois : une simulation ne consomme pas la séquence (`simBuilderFor` du
    /// terminal le garde aussi en mémoire).
    private var cachedSource: Account?

    init(config: ChimpNetworkConfig) {
        self.config = config
    }

    private var client: SorobanClient { SorobanClient(config: config) }

    /// XLM puis USDC (`assetsOf(network, "stellar")` du terminal).
    private func assets() throws -> [(code: String, contract: String)] {
        try SACClient.stellarAssets(config: config)
    }

    private func source() async throws -> Account {
        if let cachedSource { return cachedSource }
        let account = try await client.account(config.feePayer)
        cachedSource = account
        return account
    }

    func cards(of account: String) async throws -> [AccountCard] {
        try await ChimpAccountClient(client: client, config: config).cards(account: account, source: try await source())
            .map { AccountCard(publicKey: $0.publicKey, curve: $0.curve) }
    }

    func balances(of address: String) async throws -> [AssetAmount] {
        let source = try await source()
        let sac = SACClient(client: client)
        var result: [AssetAmount] = []
        for asset in try assets() {
            guard let units = try await sac.balance(token: asset.contract, holder: address, source: source) else {
                throw StellarError.noReturnValue("balance")
            }
            result.append(AssetAmount(code: asset.code, amount: SACClient.amount(fromUnits: units)))
        }
        return result
    }

    func pocket(of card: ChipPublicKey) async throws -> String? {
        try await PocketFactoryClient(client: client, contract: config.contracts.factory).pocket(of: card, source: try await source())
    }

    func tokenID(of card: ChipPublicKey) async throws -> UInt32 {
        let nft = NfcNftClient(client: client, defaultContract: config.contracts.nfcNft, collection: config.contracts.collection)
        return try await nft.token(of: card, source: try await source()).tokenID
    }
}
