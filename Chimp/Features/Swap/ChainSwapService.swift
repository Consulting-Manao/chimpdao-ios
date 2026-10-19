import Foundation
import stellarsdk

/// Le vrai service de swap, sur le réseau de l'app (testnet) : tiroirs et cartes lus comme Envoyer (`ChainSendService`,
/// sans copie), devis et appel par les adaptateurs du registre (Soroswap et Aquarius, le meilleur retenu), signature par
/// la carte, frais par le serveur de frais (`IntegrationCallClient`). Ne fait aucune crypto lui-même.
///
/// - Main account : ordre 2, l'arbre simulé doit être exactement l'arbre déclaré par l'adaptateur.
/// - Wallet d'une carte : ordre 1, l'arbre déclaré est signé avant toute simulation.
final class ChainSwapService: SwapService {
    let session: AppSession
    let config: ChimpNetworkConfig
    var network: StellarNetwork { config.network }
    private let drawers: ChainSendService
    private let client: SorobanClient
    private let integrations: IntegrationCallClient
    private let registry: IntegrationRegistry
    private let signer: ChipSigner
    private let feeSigner: FeeSigner
    /// Prix indicatif des stablebonds (Etherfuse), noté dans la ligne d'un swap qui en rapporte : jamais pour signer.
    private let pricing: StablebondPricing?

    init(
        session: AppSession,
        drawers: ChainSendService? = nil,
        signer: ChipSigner = NFCChipSigner(),
        feeSigner: FeeSigner? = nil,
        pricing: StablebondPricing? = nil
    ) {
        self.session = session
        config = session.config
        self.pricing = pricing ?? EtherfusePriceClient.shared(for: config)
        self.drawers = drawers ?? ChainSendService(session: session, signer: signer)
        client = SorobanClient(config: config)
        integrations = IntegrationCallClient(client: client, config: config)
        let reader = SimulationReader(client: client, source: config.feePayer)
        // Actif pivot d'Aquarius : l'USDC de Circle (un saut au plus, décision du 2026-10-14).
        let usdc = (try? SACClient.stellarAssets(config: config))?.first { $0.code == SendAsset.usdc.code }?.contract
        registry = IntegrationRegistry(
            swapAdapters: config.integrations.map { [
                SoroswapAdapter(contracts: $0.soroswap, reader: reader),
                AquariusAdapter(contracts: $0.aquarius, hub: usdc, reader: reader),
            ] } ?? [],
            yieldAdapters: []
        )
        self.signer = signer
        self.feeSigner = feeSigner ?? WorkerFeeSigner(url: config.feeSignerURL)
    }

    // MARK: Contexte et devis

    func fetchContext() async throws -> SwapContext {
        let context = try await drawers.fetchContext()
        return SwapContext(network: context.network, drawers: context.drawers, frozen: await frozenStablebonds(in: context.drawers))
    }

    // MARK: Gel (CETES)

    /// Les stablebonds gelés par leur émetteur, tiroir par tiroir (`authorized` du SAC, lu en parallèle). Une lecture ratée
    /// ne bloque rien ici : `prepare` relit le gel avant toute signature et refuse s'il ne peut pas le lire.
    private func frozenStablebonds(in drawers: [SendDrawer]) async -> [String: Set<SendAsset>] {
        guard let bonds = config.integrations?.etherfuse.stablebonds, !bonds.isEmpty,
              let source = try? Account(accountId: config.feePayer, sequenceNumber: 0) else { return [:] }
        let control = StablebondControl(client: client)
        return await withTaskGroup(of: (String, SendAsset)?.self) { group in
            for drawer in drawers {
                for bond in bonds {
                    guard let asset = SendAsset(code: bond.code) else { continue }
                    group.addTask {
                        let frozen = (try? await control.isFrozen(token: bond.contract, holder: drawer.address, source: source)) ?? false
                        return frozen ? (drawer.id, asset) : nil
                    }
                }
            }
            var result: [String: Set<SendAsset>] = [:]
            for await item in group {
                if let (drawerID, asset) = item { result[drawerID, default: []].insert(asset) }
            }
            return result
        }
    }

    func frozenAsset(in drawer: SendDrawer, among assets: [SendAsset]) async -> SendAsset? {
        let bonds = config.integrations?.etherfuse.stablebonds ?? []
        guard let source = try? Account(accountId: config.feePayer, sequenceNumber: 0) else { return nil }
        let control = StablebondControl(client: client)
        for asset in assets {
            guard let bond = bonds.first(where: { $0.code == asset.code }) else { continue }
            if (try? await control.isFrozen(token: bond.contract, holder: drawer.address, source: source)) == true { return asset }
        }
        return nil
    }

    /// Avant de signer : si l'un des deux actifs est un stablebond, son gel est relu pour ce tiroir. Gelé → rien n'est
    /// signé ; illisible → l'erreur remonte (jamais « pas gelé » par défaut).
    private func checkNotFrozen(_ draft: SwapDraft, request: SwapRequest, source: Account) async throws {
        let bonds = Set(config.integrations?.etherfuse.stablebonds.map(\.contract) ?? [])
        let control = StablebondControl(client: client)
        for asset in [request.assetIn, request.assetOut] where bonds.contains(asset.contract) {
            if try await control.isFrozen(token: asset.contract, holder: draft.drawer.address, source: source) {
                throw SwapServiceError.frozen(asset.code)
            }
        }
    }

    /// Le contrat (SAC) d'un actif de l'app sur ce réseau.
    private func asset(_ asset: SendAsset) throws -> IntegrationAsset {
        guard let contract = try SACClient.stellarAssets(config: config).first(where: { $0.code == asset.code })?.contract else {
            throw SwapServiceError.unknownDrawer(asset.code)
        }
        return IntegrationAsset(code: asset.code, contract: contract)
    }

    private func request(given: SendAsset, received: SendAsset, amount: Decimal) throws -> SwapRequest {
        SwapRequest(assetIn: try asset(given), assetOut: try asset(received), amountIn: try SwapUnits.units(of: amount, asset: given))
    }

    func quote(given: SendAsset, received: SendAsset, amount: Decimal) async throws -> SwapQuoteSummary {
        var comparing = registry
        #if DEBUG
        // Réglage caché du catalogue (Debug) : le devis d'un seul protocole (`SwapProtocolOverride`).
        let forced = SwapProtocolOverride.current.protocolID
        if let forced { comparing = IntegrationRegistry(swapAdapters: registry.swapAdapters.filter { $0.id == forced }, yieldAdapters: []) }
        #endif
        let comparison = await comparing.bestQuote(try request(given: given, received: received, amount: amount))
        let unavailable = comparison.failures.map { name(of: $0.protocolID) }
        guard let best = comparison.best else {
            if comparison.failures.isEmpty { throw SwapError.noRoute }
            // Un devis faux n'est jamais affiché comme un prix : il est dit tel quel, pas comme une panne.
            if comparison.failures.contains(where: { ($0.error as? SwapError) == .implausibleQuote }) { throw SwapError.implausibleQuote }
            throw SwapServiceError.protocolUnavailable(unavailable)
        }
        var summary = try summary(of: best, given: given, received: received, amount: amount)
        summary.comparedProtocols = comparison.answered.map(name(of:))
        summary.unavailableProtocols = unavailable
        #if DEBUG
        summary.isForcedForDebug = forced != nil
        #endif
        return summary
    }

    private func name(of protocolID: String) -> String {
        registry.swapAdapter(id: protocolID)?.name ?? protocolID
    }

    private func summary(of quote: SwapQuote, given: SendAsset, received: SendAsset, amount: Decimal) throws -> SwapQuoteSummary {
        let known = try SACClient.stellarAssets(config: config)
        let route = quote.route.compactMap { contract in
            known.first { $0.contract == contract }.flatMap { SendAsset(code: $0.code) }
        }
        return SwapQuoteSummary(
            protocolID: quote.protocolID, protocolName: registry.swapAdapter(id: quote.protocolID)?.name ?? quote.protocolID,
            given: given, received: received, amountIn: amount, expectedOutUnits: quote.amountOut,
            route: route, routeContracts: quote.route, priceImpactBasisPoints: quote.priceImpactBasisPoints
        )
    }

    // MARK: Avant le tap

    func prepare(_ draft: SwapDraft) async throws -> PreparedSwap {
        guard let adapter = registry.swapAdapter(id: draft.quote.protocolID) else { throw SwapServiceError.protocolUnavailable([draft.quote.protocolName]) }
        let request = try request(given: draft.given, received: draft.received, amount: draft.amount)
        let source = try Account(accountId: config.feePayer, sequenceNumber: 0)

        try await checkNotFrozen(draft, request: request, source: source)

        // Solde relu : on ne signe jamais sur un solde inconnu ou insuffisant.
        let held = try await SACClient(client: client).balance(token: request.assetIn.contract, holder: draft.drawer.address, source: source)
        try PaymentClient.checkBalance(held, units: UInt64(request.amountIn))

        // Devis redemandé juste avant de signer (`runSwap` : « Price moved »).
        guard let fresh = try await adapter.quote(request) else { throw SwapError.noRoute }
        guard fresh.amountOut >= draft.minimumOutUnits else { throw SwapError.slippageExceeded }

        // L'appel, au minimum que l'écran a montré ; ses bornes relues et comparées à l'écran.
        let now = UInt64(Date().timeIntervalSince1970)
        let call = try adapter.swapCall(for: fresh, minimumOut: draft.minimumOutUnits, authorizer: draft.drawer.address, now: now)
        let shown = SignedTerms(
            action: .swap, contract: call.contract, authorizer: draft.drawer.address,
            assetIn: request.assetIn.contract, amountIn: request.amountIn,
            assetOut: request.assetOut.contract, minimumOut: draft.minimumOutUnits,
            route: draft.quote.routeContracts, deadline: adapter.deadlineSeconds.map { now + $0 }
        )
        try BoundsCheck.verify(shown: shown, signed: try adapter.terms(of: call), quotedOut: draft.quote.expectedOutUnits, now: now)

        let authorizer: CallAuthorizer
        let acceptedKeys: [ChipPublicKey]
        switch draft.drawer.kind {
        case .main:
            authorizer = .account(draft.drawer.address)
            acceptedKeys = try await ChimpAccountClient(client: client, config: config)
                .cards(account: draft.drawer.address, source: source).map(\.publicKey)
        case .card:
            guard let key = drawers.cardKey(drawerID: draft.drawer.id) else { throw SwapServiceError.unknownDrawer(draft.drawer.id) }
            authorizer = .pocket(draft.drawer.address)
            acceptedKeys = [key]
        }
        do {
            let integration = try await integrations.prepare(
                call: call, authorizer: authorizer, shape: adapter.authShape(for: fresh), acceptedKeys: acceptedKeys
            )
            return PreparedSwap(draft: draft, integration: integration, firstHopVenue: fresh.firstHopVenue, contract: call.contract)
        } catch {
            // La simulation du Main account exécute le swap : un refus du router a un nom (prix qui a bougé, échéance…).
            throw adapter.swapError(for: error) ?? error
        }
    }

    func refreshedIfNeeded(_ prepared: PreparedSwap) async throws -> PreparedSwap {
        guard let integration = prepared.integration else { return try await self.prepare(prepared.draft) }
        do {
            try await integrations.checkFresh(integration)
            return prepared
        } catch IntegrationCallClient.SigningError.authorizationExpiring {
            return try await self.prepare(prepared.draft)
        }
    }

    // MARK: Le tap

    func readCard(for prepared: PreparedSwap) async throws -> SwapCardRead {
        guard let integration = prepared.integration else { throw SwapServiceError.unknownDrawer(prepared.draft.drawer.id) }
        switch try await signer.readOrSign(digests: [integration.digest], acceptedKeys: integration.acceptedKeys) {
        case .needsPIN(let card):
            let local = drawers.localCard(card.publicKey)
            return SwapCardRead(check: CardCheck(cardName: local.name, cardColor: local.color, usesPin: true, publicKey: card.publicKey), signed: nil)
        case .signed(let signed):
            let local = drawers.localCard(signed.card.publicKey)
            return SwapCardRead(
                check: CardCheck(cardName: local.name, cardColor: local.color, usesPin: false, publicKey: signed.card.publicKey),
                signed: SignedSwap(prepared: prepared, cardName: local.name, card: signed)
            )
        }
    }

    func sign(_ prepared: PreparedSwap, pin: String?, onlyCard: ChipPublicKey?) async throws -> SignedSwap {
        guard let integration = prepared.integration else { throw SwapServiceError.unknownDrawer(prepared.draft.drawer.id) }
        let keys = onlyCard.map { only in integration.acceptedKeys.filter { $0 == only } } ?? integration.acceptedKeys
        let signed = try await signer.sign(digests: [integration.digest], acceptedKeys: keys, pin: pin)
        return SignedSwap(prepared: prepared, cardName: drawers.localCard(signed.card.publicKey).name, card: signed)
    }

    func knownCard(_ key: ChipPublicKey) -> KnownCard? {
        drawers.knownCard(key)
    }

    // MARK: Après le tap

    func trace(for signed: SignedSwap) throws -> PaymentTrace {
        let prepared = signed.prepared
        guard let integration = prepared.integration else { throw SwapServiceError.unknownDrawer(prepared.draft.drawer.id) }
        let given = try asset(prepared.draft.given)
        return integration.trace(
            token: given.contract, destination: prepared.firstHopVenue,
            units: UInt64(try SwapUnits.units(of: prepared.draft.amount, asset: prepared.draft.given))
        )
    }

    func submit(_ signed: SignedSwap, onProgress: @escaping (PaymentProgress) -> Void) async throws -> SwapReceipt {
        let prepared = signed.prepared
        guard let integration = prepared.integration, let card = signed.card else {
            throw SwapServiceError.unknownDrawer(prepared.draft.drawer.id)
        }
        let trace = try trace(for: signed)
        let hash = try await integrations.submit(integration, signed: card, trace: trace, feeSigner: feeSigner, onProgress: onProgress)
        let receipt = SwapReceipt(
            summary: SwapSummary(prepared.draft), transactionHash: hash, sentAt: .now,
            explorerURL: explorerURL(transactionHash: hash), receivedAmount: await receivedAmount(hash, protocolID: prepared.draft.quote.protocolID)
        )
        // La ligne d'historique du swap (I1s) : celle du reçu de E5, avec le minimum signé et le protocole ; vers un
        // stablebond, le prix d'Etherfuse du moment (base de l'évolution, F9 et F10).
        if let account = session.wallet.account?.address {
            var record = receipt.activityRecord(venue: prepared.firstHopVenue)
            record.receivedPriceUSD = await priceNow(of: prepared.draft.received)
            session.recordActivity(record, account: account)
        }
        return receipt
    }

    /// La quantité reçue, lue par le protocole dans la valeur rendue par l'appel. `nil` si illisible (affichage seulement).
    private func receivedAmount(_ hash: String, protocolID: String?) async -> Decimal? {
        guard let adapter = protocolID.flatMap({ registry.swapAdapter(id: $0) }),
              let value = try? await client.transactionReturnValue(hash), let units = adapter.receivedUnits(value) else { return nil }
        return SwapUnits.amount(fromUnits: units)
    }

    /// Comme Envoyer (`ChainSendService.check`, qui écrit la ligne d'un **envoi** en attente finalement parti, jamais
    /// celle d'un swap) : un swap en attente se vérifie de la même façon, par le nonce de son autorisation.
    func check(_ trace: PaymentTrace) async throws -> PaymentCheck {
        let pending = session.wallet.pendingSend
        let result = try await drawers.check(trace)
        // Un swap en attente finalement parti : sa ligne d'historique, avec la quantité reçue si elle se lit encore.
        if case .sent(let hash) = result, let pending, let swap = pending.swap, let account = session.wallet.account?.address {
            session.recordActivity(.swap(
                hash: hash, drawer: trace.from, venue: trace.destination, givenCode: SendAsset(rawValue: pending.asset)?.code ?? pending.asset,
                given: pending.amount, receivedCode: SendAsset(rawValue: swap.receivedAsset)?.code ?? swap.receivedAsset,
                received: await receivedAmount(hash, protocolID: registry.swapAdapters.first { $0.name == swap.protocolName }?.id),
                minimum: swap.minimumReceived, protocolName: swap.protocolName, at: pending.signedAt,
                // Le prix « du moment du swap » n'est plus connu si la vérification arrive trop tard.
                receivedPriceUSD: Date().timeIntervalSince(pending.signedAt) < Self.priceWindow
                    ? await priceNow(of: SendAsset(rawValue: swap.receivedAsset)) : nil
            ), account: account)
        }
        return result
    }

    /// Au-delà, le prix lu ne serait plus celui du moment du swap : 15 minutes (l'âge maximal d'une source d'Etherfuse).
    static let priceWindow: TimeInterval = TimeInterval(EtherfusePriceClient.maxSourceAge)

    /// Prix indicatif d'un jeton reçu, si c'est un stablebond de `Config/` et qu'Etherfuse répond.
    private func priceNow(of asset: SendAsset?) async -> Decimal? {
        guard let asset, let bond = config.integrations?.etherfuse.stablebonds.first(where: { $0.code == asset.code }) else { return nil }
        return await pricing?.price(of: bond).price?.usd
    }

    var pendingSend: PendingSend? { session.wallet.pendingSend }

    func setPendingSend(_ pending: PendingSend?) throws {
        try session.setPendingSend(pending)
    }

    func explorerURL(transactionHash: String) -> URL? {
        config.explorerURL(transactionHash: transactionHash)
    }
}
