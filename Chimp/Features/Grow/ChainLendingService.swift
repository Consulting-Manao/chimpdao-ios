import Foundation
import stellarsdk

/// Le vrai service du prêt XOXNO (phase 7, décisions de Barth du 2026-10-16 : USDC seulement, dépôt et retrait, testnet),
/// sur le modèle de `ChainVaultService` pour réutiliser les écrans du vault : tiroirs et cartes lus comme Envoyer, marché et
/// positions lus par `XoxnoAdapter`, signature par la carte, frais par le serveur de frais. Ne fait aucune crypto lui-même.
///
/// Différences avec le vault : pas de parts (un dépôt garde le montant exact), un retrait est un montant exact (ou « tout »),
/// et ce qu'on peut retirer est calculé **avant** de proposer un retrait (limite d'utilisation comprise), puis relu juste
/// avant de signer. Gel, pause et plafond sont relus avant de signer.
///
/// - Main account : ordre 2, l'arbre simulé doit être exactement l'arbre déclaré.
/// - Wallet d'une carte : ordre 1, l'arbre déclaré est signé avant toute simulation.
final class ChainLendingService: VaultService {
    let session: AppSession
    let config: ChimpNetworkConfig
    private let drawers: ChainSendService
    private let client: SorobanClient
    private let integrations: IntegrationCallClient
    private let adapter: XoxnoAdapter?
    private let sendAsset: SendAsset?
    private let signer: ChipSigner
    private let feeSigner: FeeSigner

    init(
        session: AppSession,
        config: ChimpNetworkConfig = .testnet,
        drawers: ChainSendService? = nil,
        signer: ChipSigner = NFCChipSigner(),
        feeSigner: FeeSigner? = nil
    ) {
        self.session = session
        self.config = config
        self.drawers = drawers ?? ChainSendService(session: session, config: config, signer: signer)
        client = SorobanClient(config: config)
        integrations = IntegrationCallClient(client: client, config: config)
        let reader = SimulationReader(client: client, source: config.feePayer)
        let assets = (try? SACClient.stellarAssets(config: config)) ?? []
        if let market = config.integrations?.xoxno, let asset = assets.first(where: { $0.code == market.assetCode }) {
            adapter = XoxnoAdapter(
                market: market, asset: IntegrationAsset(code: asset.code, contract: asset.contract), reader: reader,
                ledger: SorobanXoxnoLedger(client: client)
            )
            sendAsset = SendAsset(code: asset.code)
        } else {
            adapter = nil
            sendAsset = nil
        }
        self.signer = signer
        self.feeSigner = feeSigner ?? WorkerFeeSigner(url: config.feeSignerURL)
    }

    private func lending() throws -> (XoxnoAdapter, SendAsset) {
        guard let adapter, let sendAsset else { throw VaultServiceError.noVault }
        return (adapter, sendAsset)
    }

    // MARK: Contexte

    func fetchContext() async throws -> VaultContext {
        let (adapter, asset) = try lending()
        let context = try await drawers.fetchContext()
        let state: XoxnoMarketState
        do {
            state = try await adapter.state()
        } catch {
            throw Self.unavailable(error)
        }
        let records = session.wallet.account.map { session.activity.activity(of: $0.address).records } ?? []
        var holdings: [VaultHolding] = []
        for drawer in context.drawers {
            let positions: [XoxnoPosition]
            do {
                positions = try await adapter.positions(holder: drawer.address)
            } catch {
                throw Self.unavailable(error)
            }
            holdings += Self.holdings(positions, drawer: drawer, records: records, pool: adapter.market.pool)
        }
        return VaultContext(network: context.network, drawers: context.drawers, vault: Self.info(adapter: adapter, asset: asset, state: state), holdings: holdings)
    }

    static func info(adapter: XoxnoAdapter, asset: SendAsset, state: XoxnoMarketState) -> VaultInfo {
        VaultInfo(
            id: adapter.market.pool, name: adapter.market.name, protocols: ["XOXNO"], asset: asset,
            invested: SwapUnits.amount(fromUnits: state.borrowed), totalManaged: SwapUnits.amount(fromUnits: state.supplied),
            kind: .lending, withdrawableNow: SwapUnits.amount(fromUnits: state.marketWithdrawable),
            depositsBlocked: state.paused || state.frozen || state.remainingCap <= 0, withdrawalsBlocked: state.paused
        )
    }

    /// Une ligne par position du tiroir ; celle qu'on peut déplacer d'abord. Une position à renouveler n'a pas de valeur
    /// connue : `value` vaut 0 mais `condition` le dit, et rien ne l'affiche comme zéro.
    static func holdings(_ positions: [XoxnoPosition], drawer: SendDrawer, records: [ActivityRecord], pool: String) -> [VaultHolding] {
        positions.map { position in
            let condition: HoldingCondition = switch position.status {
            case .needsRenewal: .needsRenewal
            case .live(_, _, let hasDebt): hasDebt ? .hasDebt : .movable
            }
            let value = position.value.map(SwapUnits.amount(fromUnits:)) ?? 0
            return VaultHolding(
                drawerID: drawer.id, drawerAddress: drawer.address, shares: value, value: value,
                basis: VaultBasis.from(records: records, drawer: drawer.address, vault: pool), readAt: .now, condition: condition
            )
        }
        // La plus grosse position déplaçable d'abord : c'est celle qu'un retrait vise.
        .sorted { lhs, rhs in
            let (left, right) = (lhs.condition == .movable ? 0 : 1, rhs.condition == .movable ? 0 : 1)
            return left != right ? left < right : lhs.value > rhs.value
        }
    }

    private static func unavailable(_ error: Error) -> Error {
        if let yield = error as? YieldError, yield != .vaultUnavailable { return yield }
        return VaultServiceError.vaultUnavailable
    }

    // MARK: Devis

    func depositQuote(drawer: SendDrawer, amount: Decimal) async throws -> VaultQuote {
        let (_, asset) = try lending()
        let units = try SwapUnits.units(of: amount, asset: asset)
        guard units > 0 else { throw YieldError.amountTooSmall }
        return VaultQuote(action: .deposit, amount: amount, shares: TokenAmount(units), expectedOut: nil, minimumOut: nil, all: false)
    }

    /// Le montant exact qui reviendra, après avoir vérifié qu'il peut sortir **maintenant** : position relue, retirable
    /// du marché relu. « Tout » : la valeur de la position, si le marché la laisse sortir en entier.
    func withdrawQuote(drawer: SendDrawer, amount: Decimal, all: Bool) async throws -> VaultQuote {
        let (adapter, asset) = try lending()
        let (_, value, state) = try await freshPosition(of: drawer, adapter: adapter)
        guard !state.paused else { throw YieldError.vaultUnavailable }
        let units = all ? value : try SwapUnits.units(of: amount, asset: asset)
        guard units > 0 else { throw YieldError.amountTooSmall }
        guard units <= value else { throw YieldError.notEnoughShares }
        guard units <= state.withdrawable(position: value) else { throw YieldError.notEnoughLiquidity }
        return VaultQuote(
            action: .withdraw, amount: SwapUnits.amount(fromUnits: units), shares: TokenAmount(units),
            expectedOut: TokenAmount(units), minimumOut: TokenAmount(units), all: all
        )
    }

    /// La plus grosse position déplaçable du tiroir (un tiroir peut en avoir plusieurs : chaque dépôt en ouvre une), sa
    /// valeur et le marché, relus. Un retrait vise une position à la fois, la plus grosse d'abord.
    private func freshPosition(of drawer: SendDrawer, adapter: XoxnoAdapter) async throws -> (XoxnoPosition, Int128, XoxnoMarketState) {
        let positions = try await adapter.positions(holder: drawer.address)
        guard let position = positions.filter(\.canMove).max(by: { ($0.value ?? 0) < ($1.value ?? 0) }), let value = position.value, value > 0 else {
            throw positions.contains { $0.status == .needsRenewal } ? YieldError.vaultUnavailable : YieldError.notEnoughShares
        }
        return (position, value, try await adapter.state())
    }

    // MARK: Avant le tap

    func prepare(_ draft: VaultDraft) async throws -> PreparedVault {
        let (adapter, asset) = try lending()
        let source = try Account(accountId: config.feePayer, sequenceNumber: 0)
        let call: ContractCall
        let shown: SignedTerms
        var allValue: TokenAmount?
        switch draft.action {
        case .deposit:
            let units = try SwapUnits.units(of: draft.amount, asset: asset)
            // Solde relu : on ne signe jamais sur un solde inconnu ou insuffisant.
            let held = try await SACClient(client: client).balance(token: adapter.asset.contract, holder: draft.drawer.address, source: source)
            try PaymentClient.checkBalance(held, units: UInt64(units))
            let state = try await adapter.state()
            guard !state.paused, !state.frozen else { throw YieldError.vaultUnavailable }
            guard Int128(units) <= state.remainingCap else { throw YieldError.capReached }
            // Revue de sécurité F4 : chaque dépôt ouvre une nouvelle position, jamais un numéro lu sur le réseau.
            call = try adapter.supplyCall(from: draft.drawer.address, units: TokenAmount(Int128(units)))
            shown = SignedTerms(
                action: .deposit, contract: adapter.market.controller, authorizer: draft.drawer.address, assetIn: adapter.asset.contract,
                amountIn: Int128(units), assetOut: adapter.market.controller, minimumOut: nil, route: [], deadline: nil
            )
        case .withdraw:
            guard let minimum = draft.quote.minimumOut else { throw VaultServiceError.priceMoved }
            // Le montant **du brouillon** (celui de l'écran) ; position et marché relus : il doit encore pouvoir sortir.
            let (position, value, state) = try await freshPosition(of: draft.drawer, adapter: adapter)
            guard !state.paused else { throw YieldError.vaultUnavailable }
            let wanted = draft.quote.all ? value : draft.quote.shares.units
            guard draft.quote.all ? value >= minimum.units : wanted <= value else { throw YieldError.notEnoughShares }
            guard wanted <= state.withdrawable(position: value) else { throw YieldError.notEnoughLiquidity }
            call = try adapter.withdrawCall(position: position, units: TokenAmount(wanted), all: draft.quote.all)
            allValue = draft.quote.all ? minimum : nil
            shown = SignedTerms(
                action: .withdraw, contract: adapter.market.controller, authorizer: draft.drawer.address, assetIn: adapter.market.controller,
                amountIn: draft.quote.all ? 0 : wanted, assetOut: adapter.asset.contract, minimumOut: minimum.units, route: [], deadline: nil
            )
        }
        let now = UInt64(Date().timeIntervalSince1970)
        try BoundsCheck.verify(shown: shown, signed: try adapter.terms(of: call, allValue: allValue), quotedOut: draft.quote.expectedOut?.units, now: now)

        let authorizer: CallAuthorizer
        let acceptedKeys: [ChipPublicKey]
        switch draft.drawer.kind {
        case .main:
            authorizer = .account(draft.drawer.address)
            acceptedKeys = try await ChimpAccountClient(client: client, config: config)
                .cards(account: draft.drawer.address, source: source).map(\.publicKey)
        case .card:
            guard let key = drawers.cardKey(drawerID: draft.drawer.id) else { throw VaultServiceError.unknownDrawer(draft.drawer.id) }
            authorizer = .pocket(draft.drawer.address)
            acceptedKeys = [key]
        }
        do {
            let integration = try await integrations.prepare(call: call, authorizer: authorizer, shape: adapter.authShape(), acceptedKeys: acceptedKeys)
            return PreparedVault(draft: draft, integration: integration)
        } catch {
            // La simulation du Main account exécute l'appel : un refus de XOXNO a un nom (liquidité, pause, plafond).
            throw XoxnoAdapter.yieldError(for: error) ?? error
        }
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

    func trace(for signed: SignedVault) throws -> PaymentTrace {
        guard let integration = signed.prepared.integration else { throw VaultServiceError.unknownDrawer(signed.prepared.draft.drawer.id) }
        return try Self.trace(of: signed.prepared, integration: integration, asset: try lending().0.asset.contract)
    }

    func submit(_ signed: SignedVault, onProgress: @escaping (PaymentProgress) -> Void) async throws -> VaultReceipt {
        let prepared = signed.prepared
        guard let integration = prepared.integration, let card = signed.card else {
            throw VaultServiceError.unknownDrawer(prepared.draft.drawer.id)
        }
        let (adapter, _) = try lending()
        let trace = try Self.trace(of: prepared, integration: integration, asset: adapter.asset.contract)
        let hash = try await integrations.submit(integration, signed: card, trace: trace, feeSigner: feeSigner, onProgress: onProgress)
        let value = try? await client.transactionReturnValue(hash)
        let receipt = VaultReceipt(
            summary: VaultSummary(prepared.draft), transactionHash: hash, sentAt: .now, explorerURL: explorerURL(transactionHash: hash),
            shares: nil, received: prepared.draft.action == .withdraw ? value.flatMap(Self.withdrawn).map(SwapUnits.amount(fromUnits:)) : nil
        )
        if let account = session.wallet.account?.address {
            session.recordActivity(receipt.activityRecord(vault: adapter.market.pool, label: adapter.market.label), account: account)
        }
        return receipt
    }

    /// La trace de « Check again » : l'actif va du tiroir à la réserve (dépôt) ou en revient (retrait). Unités prises dans
    /// le devis (une position a 7 décimales, intérêts compris, quand le pavé de l'USDC n'en a que 2).
    static func trace(of prepared: PreparedVault, integration: PreparedIntegrationCall, asset: String) throws -> PaymentTrace {
        let draft = prepared.draft
        let units = draft.action == .withdraw ? (draft.quote.expectedOut?.units ?? draft.quote.shares.units) : draft.quote.shares.units
        guard units > 0, let whole = UInt64(exactly: units) else { throw YieldError.amountTooSmall }
        var trace = integration.trace(token: asset, destination: draft.vault.id, units: whole)
        if draft.action == .withdraw {
            trace.eventSender = draft.vault.id
            trace.eventRecipient = draft.drawer.address
        }
        return trace
    }

    /// Montant revenu, dans la valeur rendue par `withdraw` : `Vec<(HubAssetKey, i128)>`.
    static func withdrawn(_ returnValue: SCValXDR) -> Int128? {
        guard let rows = returnValue.vec, rows.count == 1, let pair = rows[0].vec, pair.count == 2 else { return nil }
        return ContractArgument.int128(pair[1])
    }

    func check(_ trace: PaymentTrace) async throws -> PaymentCheck {
        let pending = session.wallet.pendingSend
        let result = try await drawers.check(trace)
        if case .sent(let hash) = result, let pending, let summary = VaultSummary(pending, network: config.network),
           let account = session.wallet.account?.address, let adapter {
            let value = try? await client.transactionReturnValue(hash)
            let receipt = VaultReceipt(
                summary: summary, transactionHash: hash, sentAt: pending.signedAt, explorerURL: explorerURL(transactionHash: hash),
                shares: nil, received: summary.action == .withdraw ? value.flatMap(Self.withdrawn).map(SwapUnits.amount(fromUnits:)) : nil
            )
            session.recordActivity(receipt.activityRecord(vault: adapter.market.pool, label: adapter.market.label), account: account)
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
