import Foundation
import stellarsdk

/// Le vrai service du vault xSolvBTC de Solv (décision de Barth du 2026-11-05 ; testnet : copie de test, mêmes wasm que le
/// mainnet), sur le modèle du vault DeFindex pour réutiliser ses écrans : on met du SolvBTC, on reçoit des xSolvBTC (des
/// parts) dont la valeur en SolvBTC suit la NAV de l'oracle de Solv. Ne fait aucune crypto lui-même.
///
/// - Dépôt : `approve` puis `deposit`, envoyés **ensemble** par le router de ChimpDAO (une signature de la carte) ; l'arbre
///   simulé du Main account doit être exactement l'arbre déclaré (vérifié sur la copie de test le 2026-11-05).
/// - Dépôt payé en USDC (retour de Barth, 2026-11-05) : le swap USDC → SolvBTC part **dans le même lot**, avant
///   l'`approve` et le `deposit` ; on dépose exactement le minimum de l'échange (− 0,5 %), le petit surplus éventuel de
///   SolvBTC reste dans le tiroir. Toujours une seule signature de la carte.
/// - Retrait : pas dans l'app (il exige une signature du serveur de Solv) ; la page du pot propose un swap xSolvBTC →
///   SolvBTC à la place.
final class ChainSolvService: VaultService {
    let session: AppSession
    let config: ChimpNetworkConfig
    var network: StellarNetwork { config.network }
    private let drawers: ChainSendService
    private let client: SorobanClient
    private let integrations: IntegrationCallClient
    private let solv: IntegrationConfig.Solv?
    private let signer: ChipSigner
    private let feeSigner: FeeSigner
    /// Le trésorier du vault (où part le SolvBTC d'un dépôt), lu une fois : la trace de « Check again » le cherche.
    private var treasurer: String?
    /// L'échange USDC → SolvBTC d'un dépôt payé en USDC : les mêmes devis et contrôles que l'écran Swap.
    private let swaps: ChainSwapService

    init(
        session: AppSession,
        drawers: ChainSendService? = nil,
        signer: ChipSigner = NFCChipSigner(),
        feeSigner: FeeSigner? = nil
    ) {
        self.session = session
        config = session.config
        self.drawers = drawers ?? ChainSendService(session: session, signer: signer)
        client = SorobanClient(config: config)
        integrations = IntegrationCallClient(client: client, config: config)
        solv = session.config.solv
        self.signer = signer
        self.feeSigner = feeSigner ?? WorkerFeeSigner(url: config.feeSignerURL)
        swaps = ChainSwapService(session: session, drawers: self.drawers, signer: signer, feeSigner: self.feeSigner)
    }

    private func place() throws -> IntegrationConfig.Solv {
        guard let solv else { throw VaultServiceError.noVault }
        return solv
    }

    private func source() throws -> Account {
        try Account(accountId: config.feePayer, sequenceNumber: 0)
    }

    /// La NAV (SolvBTC par xSolvBTC) et ses décimales, lues sur l'oracle de Solv.
    private func nav(_ solv: IntegrationConfig.Solv) async throws -> (nav: Int128, decimals: Int) {
        async let navRead = client.read(source: try source(), contract: solv.oracle, function: "get_nav", arguments: [])
        async let decimalsRead = client.read(source: try source(), contract: solv.oracle, function: "get_nav_decimals", arguments: [])
        guard let nav = try await navRead.flatMap(ContractArgument.int128), nav > 0,
              case .u32(let decimals)? = try await decimalsRead, decimals <= 18 else {
            throw YieldError.implausibleValue
        }
        return (nav, Int(decimals))
    }

    // MARK: Contexte

    /// Les tiroirs (leurs xSolvBTC sont lus avec les autres soldes), la NAV, et la valeur de chaque position en SolvBTC.
    func fetchContext() async throws -> VaultContext {
        let solv = try place()
        async let contextRead = drawers.fetchContext()
        async let navRead = nav(solv)
        let context = try await contextRead
        let nav: (nav: Int128, decimals: Int)
        do {
            nav = try await navRead
        } catch {
            throw VaultServiceError.vaultUnavailable
        }
        let records = session.wallet.account.map { session.activity.activity(of: $0.address).records } ?? []
        let holdings = context.drawers.compactMap { drawer -> VaultHolding? in
            let shares = drawer.balance(of: .xsolvbtc)
            guard shares > 0, let units = try? SwapUnits.units(of: shares, asset: .xsolvbtc),
                  let value = SolvCalls.value(shares: units, nav: nav.nav, navDecimals: nav.decimals) else { return nil }
            return VaultHolding(
                drawerID: drawer.id, drawerAddress: drawer.address, shares: shares,
                value: SwapUnits.amount(fromUnits: value, asset: .solvbtc),
                basis: VaultBasis.from(records: records, drawer: drawer.address, vault: solv.vault), readAt: .now
            )
        }
        return VaultContext(network: context.network, drawers: context.drawers, vault: Self.info(solv), holdings: holdings)
    }

    static func info(_ solv: IntegrationConfig.Solv) -> VaultInfo {
        // Aucun retrait dans l'app : la page du pot propose le swap à la place.
        VaultInfo(
            id: solv.vault, name: solv.name, protocols: ["Solv"], asset: .solvbtc, invested: 0, totalManaged: 0,
            mark: .solv, withdrawalsBlocked: true, depositAssets: [.usdc, .solvbtc]
        )
    }

    // MARK: Devis

    /// Les xSolvBTC qu'un dépôt frapperait à la NAV du moment (`calculate_mint_amount`, sans frais de dépôt) : « about ».
    func depositQuote(drawer: SendDrawer, amount: Decimal) async throws -> VaultQuote {
        let solv = try place()
        let units = try SwapUnits.units(of: amount, asset: .solvbtc)
        guard units > 0 else { throw YieldError.amountTooSmall }
        let nav = try await nav(solv)
        guard let shares = SolvCalls.mintedShares(units: units, nav: nav.nav, navDecimals: nav.decimals), shares > 0 else {
            throw YieldError.amountTooSmall
        }
        var quote = VaultQuote(action: .deposit, amount: amount, shares: TokenAmount(shares), expectedOut: nil, minimumOut: nil, all: false)
        quote.decimals = SendAsset.xsolvbtc.decimals
        return quote
    }

    /// Payé en USDC : le devis de l'échange USDC → SolvBTC (le meilleur de Soroswap et d'Aquarius), puis les xSolvBTC
    /// que frapperait son minimum (− 0,5 %), qui est exactement ce qui sera déposé.
    func depositQuote(drawer: SendDrawer, amount: Decimal, paying: SendAsset) async throws -> VaultQuote {
        guard paying == .usdc else { return try await depositQuote(drawer: drawer, amount: amount) }
        let solv = try place()
        async let swapRead = swaps.quote(given: .usdc, received: .solvbtc, amount: amount)
        async let navRead = nav(solv)
        let swap = VaultSwap(try await swapRead)
        let minimum = Self.depositedUnits(of: swap)
        let nav = try await navRead
        guard minimum > 0, let shares = SolvCalls.mintedShares(units: minimum, nav: nav.nav, navDecimals: nav.decimals), shares > 0 else {
            throw YieldError.amountTooSmall
        }
        var quote = VaultQuote(
            action: .deposit, amount: amount, shares: TokenAmount(shares), expectedOut: nil, minimumOut: TokenAmount(minimum), all: false
        )
        quote.decimals = SendAsset.xsolvbtc.decimals
        quote.swap = swap
        return quote
    }

    /// Le SolvBTC déposé après un échange : son minimum à la tolérance par défaut (0,5 %).
    static func depositedUnits(of swap: VaultSwap) -> Int128 {
        Slippage.minimum(of: swap.expectedOut.units, basisPoints: Slippage.defaultBasisPoints)
    }

    func withdrawQuote(drawer: SendDrawer, amount: Decimal, all: Bool) async throws -> VaultQuote {
        throw YieldError.vaultUnavailable
    }

    // MARK: Avant le tap

    func prepare(_ draft: VaultDraft) async throws -> PreparedVault {
        let solv = try place()
        guard draft.action == .deposit else { throw YieldError.vaultUnavailable }
        let swap = draft.quote.swap
        // Payé en USDC : seulement l'échange USDC → SolvBTC montré, et le SolvBTC déposé est son minimum, montré aussi.
        guard swap == nil || (draft.vault.asset == .usdc && swap?.given == .usdc && swap?.received == .solvbtc
            && draft.quote.minimumOut?.units == swap.map(Self.depositedUnits)) else {
            throw ContractArgument.ArgumentError.malformed("not a USDC → SolvBTC deposit")
        }
        let source = try source()
        async let accountCards = mainAccountCards(of: draft.drawer, source: source)
        let given = swap == nil ? solv.solvBTC.contract : try usdcContract()
        let givenUnits = try SwapUnits.units(of: draft.amount, asset: swap == nil ? .solvbtc : .usdc)
        let units = swap == nil ? givenUnits : (draft.quote.minimumOut?.units ?? 0)
        // Solde, actif accepté, trésorier et dernier ledger relus ensemble : on ne signe jamais sur un solde inconnu ou
        // insuffisant, ni vers un vault qui refuse le SolvBTC.
        async let heldRead = SACClient(client: client).balance(token: given, holder: draft.drawer.address, source: source)
        async let legRead = swapLeg(for: swap, minimumOut: TokenAmount(units), drawer: draft.drawer)
        async let acceptedRead = client.read(
            source: source, contract: solv.vault, function: "is_currency_supported", arguments: [try ContractArgument.address(solv.solvBTC.contract)]
        )
        async let treasurerRead = client.read(source: source, contract: solv.vault, function: "get_treasurer", arguments: [])
        async let ledgerRead = client.latestLedger()
        try PaymentClient.checkBalance(try await heldRead, units: UInt64(givenUnits))
        guard case .bool(true)? = try await acceptedRead else { throw YieldError.vaultUnavailable }
        treasurer = try await treasurerRead?.address.flatMap { try? $0.toStrKey() }

        // L'`approve` vit le temps de l'autorisation signée, et un peu plus : il est consommé par le dépôt, dans la même
        // transaction, pour exactement ce montant.
        let liveUntil = try await ledgerRead + SorobanAuth.expirationLedgers + 80
        let depositLegs = try SolvCalls.depositLegs(vault: solv.vault, from: draft.drawer.address, currency: solv.solvBTC.contract, units: units, liveUntilLedger: liveUntil)
        let shown = SignedTerms(
            action: .deposit, contract: solv.vault, authorizer: draft.drawer.address, assetIn: solv.solvBTC.contract, amountIn: units,
            assetOut: solv.xSolvBTC.contract, minimumOut: nil, route: [], deadline: nil
        )
        try BoundsCheck.verify(
            shown: shown, signed: try SolvCalls.terms(of: depositLegs, vault: solv.vault, currency: solv.solvBTC.contract, shares: solv.xSolvBTC.contract),
            quotedOut: nil, now: UInt64(Date().timeIntervalSince1970)
        )
        // L'échange d'abord : le SolvBTC qu'il rend (au moins `units`) est celui que le vault tire ensuite.
        let leg = try await legRead
        let legs = (leg.map { [$0.call] } ?? []) + depositLegs
        let shape: any AuthShape = leg.map { ComposedShape($0.shape, SolvAuthShape(vault: solv.vault)) } ?? SolvAuthShape(vault: solv.vault)
        let root = try RouterBatch.call(router: config.contracts.router, caller: draft.drawer.address, legs: legs)

        let authorizer: CallAuthorizer
        let acceptedKeys: [ChipPublicKey]
        switch draft.drawer.kind {
        case .main:
            authorizer = .account(draft.drawer.address)
            acceptedKeys = try await accountCards
        case .card:
            guard let key = drawers.cardKey(drawerID: draft.drawer.id) else { throw VaultServiceError.unknownDrawer(draft.drawer.id) }
            authorizer = .pocket(draft.drawer.address)
            acceptedKeys = [key]
        }
        do {
            let integration = try await integrations.prepare(
                call: root, legs: legs, authorizer: authorizer, shape: shape, acceptedKeys: acceptedKeys
            )
            return PreparedVault(draft: draft, integration: integration)
        } catch {
            // La simulation du Main account exécute l'échange : un prix passé sous le minimum est dit comme tel.
            if let swap, swaps.swapError(for: error, protocolID: swap.protocolID) == .slippageExceeded { throw VaultServiceError.priceMoved }
            throw SolvCalls.yieldError(for: error) ?? error
        }
    }

    /// L'échange USDC → SolvBTC, au minimum montré ; un prix passé dessous : « the amount moved », rien n'est signé.
    private func swapLeg(for swap: VaultSwap?, minimumOut: TokenAmount, drawer: SendDrawer) async throws -> (call: ContractCall, shape: any AuthShape)? {
        guard let swap else { return nil }
        do {
            return try await swaps.batchLeg(for: swap, minimumOut: minimumOut, authorizer: drawer.address)
        } catch SwapError.slippageExceeded {
            throw VaultServiceError.priceMoved
        }
    }

    private func usdcContract() throws -> String {
        guard let usdc = try SACClient.stellarAssets(config: config).first(where: { $0.code == SendAsset.usdc.code }) else {
            throw VaultServiceError.noVault
        }
        return usdc.contract
    }

    /// Les cartes du Main account (relues sur la chaîne) ; aucune pour le wallet d'une carte.
    private func mainAccountCards(of drawer: SendDrawer, source: Account) async throws -> [ChipPublicKey] {
        guard case .main = drawer.kind else { return [] }
        return try await ChimpAccountClient(client: client, config: config).cards(account: drawer.address, source: source).map(\.publicKey)
    }

    func refreshedIfNeeded(_ prepared: PreparedVault) async throws -> PreparedVault {
        guard let integration = prepared.integration else { return try await self.prepare(prepared.draft) }
        do {
            try await integrations.checkFresh(integration)
            return prepared
        } catch IntegrationCallClient.SigningError.authorizationExpiring {
            return try await self.prepare(prepared.draft)
        }
    }

    // MARK: Le tap

    func readCard(for prepared: PreparedVault) async throws -> VaultCardRead {
        guard let integration = prepared.integration else { throw VaultServiceError.unknownDrawer(prepared.draft.drawer.id) }
        switch try await signer.readOrSign(digests: [integration.digest], acceptedKeys: integration.acceptedKeys) {
        case .needsPIN(let card):
            let local = drawers.localCard(card.publicKey)
            return VaultCardRead(check: CardCheck(cardName: local.name, cardColor: local.color, usesPin: true, publicKey: card.publicKey), signed: nil)
        case .signed(let signed):
            let local = drawers.localCard(signed.card.publicKey)
            return VaultCardRead(
                check: CardCheck(cardName: local.name, cardColor: local.color, usesPin: false, publicKey: signed.card.publicKey),
                signed: SignedVault(prepared: prepared, cardName: local.name, card: signed)
            )
        }
    }

    func sign(_ prepared: PreparedVault, pin: String?, onlyCard: ChipPublicKey?) async throws -> SignedVault {
        guard let integration = prepared.integration else { throw VaultServiceError.unknownDrawer(prepared.draft.drawer.id) }
        let keys = onlyCard.map { only in integration.acceptedKeys.filter { $0 == only } } ?? integration.acceptedKeys
        let signed = try await signer.sign(digests: [integration.digest], acceptedKeys: keys, pin: pin)
        return SignedVault(prepared: prepared, cardName: drawers.localCard(signed.card.publicKey).name, card: signed)
    }

    func knownCard(_ key: ChipPublicKey) -> KnownCard? {
        drawers.knownCard(key)
    }

    // MARK: Après le tap

    /// Le SolvBTC part du tiroir vers le trésorier du vault (`transfer_from`), dans la transaction de notre autorisation.
    func trace(for signed: SignedVault) throws -> PaymentTrace {
        let solv = try place()
        guard let integration = signed.prepared.integration else { throw VaultServiceError.unknownDrawer(signed.prepared.draft.drawer.id) }
        // Payé en USDC : le SolvBTC déposé est le minimum de l'échange.
        let quote = signed.prepared.draft.quote
        let units = quote.swap == nil ? try SwapUnits.units(of: signed.prepared.draft.amount, asset: .solvbtc) : (quote.minimumOut?.units ?? 0)
        guard let whole = UInt64(exactly: units), whole > 0 else { throw YieldError.amountTooSmall }
        return integration.trace(token: solv.solvBTC.contract, destination: treasurer ?? solv.vault, units: whole)
    }

    func submit(_ signed: SignedVault, onProgress: @escaping (PaymentProgress) -> Void) async throws -> VaultReceipt {
        let solv = try place()
        let prepared = signed.prepared
        guard let integration = prepared.integration, let card = signed.card else {
            throw VaultServiceError.unknownDrawer(prepared.draft.drawer.id)
        }
        let hash = try await integrations.submit(integration, signed: card, trace: try trace(for: signed), feeSigner: feeSigner, onProgress: onProgress)
        // Le router ne rend rien : les xSolvBTC frappés sont ceux du devis, à la NAV du moment (« about »).
        let receipt = VaultReceipt(
            summary: VaultSummary(prepared.draft), transactionHash: hash, sentAt: .now, explorerURL: explorerURL(transactionHash: hash),
            shares: prepared.draft.quote.sharesAmount, received: nil
        )
        if let account = session.wallet.account?.address {
            session.recordActivity(Self.activityRecord(receipt, vault: solv.vault, label: solv.label), account: account)
        }
        return receipt
    }

    /// La ligne d'historique d'un dépôt. Payé en USDC : celle du SolvBTC déposé (le minimum de l'échange), pour que la
    /// base de la position (`VaultBasis`) reste en SolvBTC.
    static func activityRecord(_ receipt: VaultReceipt, vault: String, label: ActivityRecord.VaultLabel) -> ActivityRecord {
        let summary = receipt.summary
        guard summary.action == .deposit, summary.asset == .usdc, let deposited = summary.minimumOut else {
            return receipt.activityRecord(vault: vault, label: label)
        }
        return .vaultDeposit(
            hash: receipt.transactionHash, drawer: summary.drawerAddress, vault: vault, label: label,
            assetCode: SendAsset.solvbtc.code, amount: deposited, shares: receipt.shares, at: receipt.sentAt
        )
    }

    func check(_ trace: PaymentTrace) async throws -> PaymentCheck {
        let pending = session.wallet.pendingSend
        let result = try await drawers.check(trace)
        if case .sent(let hash) = result, let pending, let summary = VaultSummary(pending, network: config.network),
           let account = session.wallet.account?.address, let solv {
            let receipt = VaultReceipt(
                summary: summary, transactionHash: hash, sentAt: pending.signedAt, explorerURL: explorerURL(transactionHash: hash),
                shares: summary.shares, received: nil
            )
            session.recordActivity(Self.activityRecord(receipt, vault: solv.vault, label: solv.label), account: account)
        }
        return result
    }

    var pendingSend: PendingSend? { session.wallet.pendingSend }

    func setPendingSend(_ pending: PendingSend?) throws {
        try session.setPendingSend(pending)
    }

    func explorerURL(transactionHash: String) -> URL? {
        config.explorerURL(transactionHash: transactionHash)
    }
}
