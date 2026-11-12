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
    /// Stablebonds (CETES) : prix indicatif d'Etherfuse, compté dans le total (décision de Barth du 2026-10-15). Prix
    /// indisponible → la règle actuelle : pas de total partiel.
    var stablebondPrices: StablebondWalletPrices? = nil
    var now: () -> Date = { .now }
    /// Pour vérifier qu'une Pocket est bien celle de sa carte (F2).
    var config: ChimpNetworkConfig { session.config }

    var firstName: String? { session.wallet.firstName }
    var accountAddress: String? { session.wallet.account?.address }

    enum ReadError: LocalizedError {
        case noAccount

        var errorDescription: String? { "No account is open on this phone." }
    }

    func discardCachedReads() {
        ReadCache.shared.clear()
    }

    func storedWallet() -> WalletSnapshot? {
        session.wallet.account.flatMap { session.balances.snapshot(of: $0.address) }
    }

    func fetchWallet() async throws -> WalletSnapshot {
        guard let account = session.wallet.account else { throw ReadError.noAccount }
        return try await fetchWallet(for: account)
    }

    /// Soldes d'un compte ouvert sur ce téléphone, affiché ou non (totaux de I6 « Switch account »).
    func fetchWallet(for account: SavedAccount) async throws -> WalletSnapshot {

        // Lectures indépendantes, lancées ensemble (le terminal fait de même).
        async let membersRead = chain.cards(of: account.address)
        async let mainRead = chain.balances(of: account.address)
        // Les wallets des cartes déjà connues du téléphone sont lus sans attendre `cards()`. Seule la liste du compte
        // compte pour l'affichage : une lecture d'une carte qui n'y est plus est jetée. Revue de sécurité F2 : seulement
        // une Pocket qui est bien l'adresse prédite pour sa carte (rien n'est lu à une adresse refusée).
        var early: [String: Task<[AssetAmount], Error>] = [:]
        for saved in account.cards {
            guard let pocket = saved.pocket, let key = try? ChipPublicKey(Data(hex: saved.publicKey) ?? Data()),
                  (try? config.checkedPocket(pocket, of: key)) != nil else { continue }
            early[pocket] = Task { [chain] in try await chain.balances(of: pocket) }
        }
        defer { early.values.forEach { $0.cancel() } }
        let members = try await membersRead
        let mainAssets = try await mainRead

        let cards = try await withThrowingTaskGroup(of: (Int, CardBalance).self) { group in
            for (index, member) in members.enumerated() {
                let saved = account.cards.first { $0.publicKey == member.publicKey.hex }
                let prefetched = saved?.pocket.flatMap { early[$0] }
                group.addTask { (index, try await self.card(member, saved: saved, prefetched: prefetched)) }
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
        // Reflector et Etherfuse sont indépendants : lus ensemble.
        async let reflector = held.isEmpty ? [:] : oracle.usdPrices(for: DisplayMoney.priceCodes(held: held, currency: snapshot.currency))
        async let etherfuse = stablebondPrices?.usdPrices(for: held)
        priced.usdPrices = await reflector
        if let bonds = await etherfuse { priced.usdPrices.merge(bonds) { _, etherfuse in etherfuse } }
        // Gardés pour le prochain lancement (affichage seulement, `BalanceStore`).
        session.balances.save(priced, of: account.address)
        return priced
    }

    /// Une carte : sa Pocket (mémorisée à l'onboarding, sinon demandée à la factory), ses soldes, son numéro.
    /// `prefetched` : la lecture des soldes de la Pocket mémorisée, déjà lancée.
    private func card(_ member: AccountCard, saved: SavedCard?, prefetched: Task<[AssetAmount], Error>?) async throws -> CardBalance {
        let key = member.publicKey
        var pocket: String?
        if let known = saved?.pocket {
            pocket = known
        } else {
            pocket = try await chain.pocket(of: key)
        }
        // Revue de sécurité F2 : gardée ou lue, la Pocket doit être celle que la factory déploie pour cette clé.
        if let found = pocket { pocket = try config.checkedPocket(found, of: key) }
        // Le numéro n'est que de l'affichage : une lecture ratée donne « ···· », pas une erreur. Lu en même temps que les soldes.
        async let tokenRead: UInt32? = saved?.tokenID == nil ? try? await chain.tokenID(of: key) : saved?.tokenID
        var assets: [AssetAmount] = []
        if let pocket {
            // La lecture anticipée ne vaut que pour la Pocket vérifiée (F2) ; sinon, une lecture neuve.
            if let prefetched, pocket == saved?.pocket {
                assets = try await prefetched.value
            } else {
                assets = try await chain.balances(of: pocket)
            }
        }
        let tokenID = await tokenRead
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

/// `WalletChain` sur le réseau de l'app (testnet), avec le payeur de frais comme source des simulations. Les lectures
/// passent par `ReadCache` (60 s, vidée après chaque envoi) : Envoyer, Swap et Grow reprennent celles du Wallet.
final class ChainWalletReader: WalletChain {
    let config: ChimpNetworkConfig
    private let cache: ReadCache

    init(config: ChimpNetworkConfig, cache: ReadCache = .shared) {
        self.config = config
        self.cache = cache
    }

    private var client: SorobanClient { SorobanClient(config: config) }

    /// XLM, USDC puis les stablebonds (`assetsOf(network, "stellar")` du terminal).
    private func assets() throws -> [(code: String, contract: String)] {
        try SACClient.stellarAssets(config: config)
    }

    /// Compte source des simulations : le payeur de frais, sans lire sa séquence (une simulation ne la consomme ni ne la
    /// vérifie ; même choix que Swap, Grow et l'oracle). Un aller-retour réseau de moins avant chaque Wallet.
    private func source() throws -> Account {
        try Account(accountId: config.feePayer, sequenceNumber: 0)
    }

    /// Gardées comme les soldes (le terminal ne garde que soldes, Pocket et positions) : une carte ajoutée ou retirée
    /// depuis ce téléphone vide la mémoire, depuis un autre elle se voit en une minute au plus.
    func cards(of account: String) async throws -> [AccountCard] {
        let source = try source()
        return try await cache.read("cards:\(config.passphrase):\(account)") { [client, config] in
            try await ChimpAccountClient(client: client, config: config).cards(account: account, source: source)
                .map { AccountCard(publicKey: $0.publicKey, curve: $0.curve) }
        }
    }

    /// Un actif par simulation, toutes lancées ensemble ; le résultat garde l'ordre des actifs.
    func balances(of address: String) async throws -> [AssetAmount] {
        let source = try source()
        let sac = SACClient(client: client)
        let assets = try assets()
        // Les tâches du groupe ne lisent que la chaîne ; la conversion en montants (décimales de chaque actif) se fait
        // ensuite, sur le fil principal (sans avertissement Swift 6 en Release, 2026-11-06).
        let units = try await withThrowingTaskGroup(of: (Int, Decimal).self) { group in
            for (index, asset) in assets.enumerated() {
                group.addTask { [cache, config] in
                    // Clé du terminal : `bal:{passphrase}:{adresse}:{actif}`.
                    let read = try await cache.read("bal:\(config.passphrase):\(address):\(asset.contract)") {
                        try await sac.balance(token: asset.contract, holder: address, source: source)
                    }
                    guard let units = read else {
                        throw StellarError.noReturnValue("balance")
                    }
                    return (index, units)
                }
            }
            var result: [(Int, Decimal)] = []
            for try await entry in group { result.append(entry) }
            return result.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return zip(assets, units).map { asset, units in
            AssetAmount(code: asset.code, amount: SACClient.amount(fromUnits: units, chainDecimals: SendAsset.decimals(code: asset.code)))
        }
    }

    /// Une Pocket trouvée est gardée sans limite de durée (une clé n'a qu'une Pocket possible) ; « pas de Pocket » ne
    /// l'est jamais, pour voir celle qu'on vient de déployer (`lookupPocket` du terminal).
    func pocket(of card: ChipPublicKey) async throws -> String? {
        let source = try source()
        do {
            return try await cache.read("pocket:\(config.passphrase):\(card.hex)", ttl: nil) { [client, config] in
                guard let found = try await PocketFactoryClient(client: client, contract: config.contracts.factory).pocket(of: card, source: source) else {
                    throw PocketNotDeployed()
                }
                return found
            }
        } catch is PocketNotDeployed {
            return nil
        }
    }

    /// « Pas encore de Pocket », passé par le chemin des erreurs de `ReadCache` pour n'être jamais gardé.
    private struct PocketNotDeployed: Error {}

    func tokenID(of card: ChipPublicKey) async throws -> UInt32 {
        let nft = NfcNftClient(client: client, defaultContract: config.contracts.nfcNft, collection: config.contracts.collection)
        return try await nft.token(of: card, source: try source()).tokenID
    }
}

/// Prix indicatifs des actifs d'un émetteur (stablebonds d'Etherfuse, USDY d'Ondo) détenus, pour le total du Wallet et des
/// tiroirs : chacun par **sa** source (Etherfuse pour les CETES, l'oracle RedStone pour l'USDY), jamais Reflector, jamais un
/// pool ; affichage seulement.
struct StablebondWalletPrices {
    let entries: [(bond: IntegrationConfig.Stablebond, pricing: StablebondPricing?)]

    init(entries: [(bond: IntegrationConfig.Stablebond, pricing: StablebondPricing?)]) {
        self.entries = entries
    }

    init(bonds: [IntegrationConfig.Stablebond], pricing: StablebondPricing?) {
        self.init(entries: bonds.map { ($0, pricing) })
    }

    init?(config: ChimpNetworkConfig) {
        let bonds = config.etherfuse.map { etherfuse in
            etherfuse.stablebonds.map { (bond: $0, pricing: EtherfusePriceClient.shared(for: config) as StablebondPricing?) }
        } ?? []
        let redstone = RedStonePriceClient.shared(for: config) as StablebondPricing?
        let usdy = config.ondo.map { [(bond: $0.usdy, pricing: redstone)] } ?? []
        let solv = config.solv.map { [(bond: $0.solvBTC, pricing: redstone), (bond: $0.xSolvBTC, pricing: redstone)] } ?? []
        guard !(bonds + usdy + solv).isEmpty else { return nil }
        self.init(entries: bonds + usdy + solv)
    }

    /// Le prix de cet actif par sa source, ou pourquoi il n'y en a pas.
    func price(of code: String) async -> StablebondPriceResult {
        guard let entry = entries.first(where: { $0.bond.code == code }), let pricing = entry.pricing else {
            return .unavailable("no price source for \(code)")
        }
        return await pricing.price(of: entry.bond)
    }

    /// Le prix en dollars de chaque actif détenu ; un prix indisponible est absent (jamais inventé).
    func usdPrices(for held: Set<String>) async -> [String: Decimal] {
        var prices: [String: Decimal] = [:]
        for entry in entries where held.contains(entry.bond.code) {
            // Clé en majuscules, comme Reflector et `NetWorth` (« SOLVBTC »).
            if let price = await entry.pricing?.price(of: entry.bond).price { prices[entry.bond.code.uppercased()] = price.usd }
        }
        return prices
    }
}
