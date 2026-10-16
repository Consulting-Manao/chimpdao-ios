import Foundation
import stellarsdk

/// Le vrai service du vault, sur le réseau de l'app (testnet) : tiroirs et cartes lus comme Envoyer (`ChainSendService`),
/// vault lu et appels construits par `DeFindexAdapter`, signature par la carte, frais par le serveur de frais
/// (`IntegrationCallClient`). Ne fait aucune crypto lui-même.
///
/// - Main account : ordre 2, l'arbre simulé doit être exactement l'arbre déclaré.
/// - Wallet d'une carte : ordre 1, l'arbre déclaré est signé avant toute simulation.
final class ChainVaultService: VaultService {
    let session: AppSession
    let config: ChimpNetworkConfig
    private let drawers: ChainSendService
    private let client: SorobanClient
    private let integrations: IntegrationCallClient
    private let adapter: DeFindexAdapter?
    private let venue: YieldVenue?
    private let vaultConfig: IntegrationConfig.DeFindexVault?
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
        // Un seul vault pour l'instant (décision du 2026-10-14) : le vault XLM de DeFindex.
        vaultConfig = config.integrations?.defindexVaults.first
        let assets = (try? SACClient.stellarAssets(config: config)) ?? []
        venue = vaultConfig.flatMap { vault in
            assets.first { $0.code == vault.assetCode }.map { asset in
                YieldVenue(
                    id: vault.vault, name: vault.label.name, asset: IntegrationAsset(code: asset.code, contract: asset.contract),
                    underlyingProtocols: vault.underlyingProtocols
                )
            }
        }
        adapter = venue.map { DeFindexAdapter(vaults: [$0], reader: reader) }
        self.signer = signer
        self.feeSigner = feeSigner ?? WorkerFeeSigner(url: config.feeSignerURL)
    }

    private func vault() throws -> (DeFindexAdapter, YieldVenue, SendAsset) {
        guard let adapter, let venue, let asset = SendAsset(code: venue.asset.code) else { throw VaultServiceError.noVault }
        return (adapter, venue, asset)
    }

    // MARK: Contexte

    func fetchContext() async throws -> VaultContext {
        let (adapter, venue, asset) = try vault()
        let context = try await drawers.fetchContext()
        let state: DeFindexAdapter.VaultState
        do {
            state = try await adapter.state(of: venue)
        } catch {
            throw Self.unavailable(error)
        }
        let records = session.wallet.account.map { session.activity.activity(of: $0.address).records } ?? []
        var holdings: [VaultHolding] = []
        for drawer in context.drawers {
            let positions: [YieldPosition]
            do {
                positions = try await adapter.discover(holder: drawer.address)
            } catch {
                throw Self.unavailable(error)
            }
            for position in positions where position.venueID == venue.id {
                holdings.append(VaultHolding(
                    drawerID: drawer.id, drawerAddress: drawer.address, shares: SwapUnits.amount(fromUnits: position.shares),
                    value: SwapUnits.amount(fromUnits: position.value),
                    basis: VaultBasis.from(records: records, drawer: drawer.address, vault: venue.id), readAt: .now
                ))
            }
        }
        return VaultContext(
            network: context.network, drawers: context.drawers,
            vault: VaultInfo(
                id: venue.id, name: venue.name, protocols: venue.underlyingProtocols, asset: asset,
                invested: SwapUnits.amount(fromUnits: state.invested), totalManaged: SwapUnits.amount(fromUnits: state.totalManaged)
            ),
            holdings: holdings
        )
    }

    /// Une panne du vault (réseau, contrat) dite simplement (F3b), sauf ce que le vault a refusé avec un nom.
    private static func unavailable(_ error: Error) -> Error {
        if error is YieldError, (error as? YieldError) != .vaultUnavailable { return error }
        return VaultServiceError.vaultUnavailable
    }

    // MARK: Devis

    func depositQuote(drawer: SendDrawer, amount: Decimal) async throws -> VaultQuote {
        let (adapter, venue, asset) = try vault()
        let units = try SwapUnits.units(of: amount, asset: asset)
        let shares = try await adapter.depositQuote(venue: venue, amount: TokenAmount(units))
        return VaultQuote(action: .deposit, amount: amount, shares: shares, expectedOut: nil, minimumOut: nil, all: false)
    }

    func withdrawQuote(drawer: SendDrawer, amount: Decimal, all: Bool) async throws -> VaultQuote {
        let (adapter, venue, asset) = try vault()
        let units = all ? 0 : try SwapUnits.units(of: amount, asset: asset)
        let position = YieldPosition(protocolID: adapter.id, venueID: venue.id, holder: drawer.address, shares: 0, value: 0)
        let quote = try await adapter.withdrawQuote(position: position, amount: TokenAmount(units), all: all)
        return VaultQuote(
            action: .withdraw, amount: all ? SwapUnits.amount(fromUnits: quote.expected.units) : amount, shares: quote.shares,
            expectedOut: quote.expected, minimumOut: quote.minimum, all: all
        )
    }

    // MARK: Avant le tap

    func prepare(_ draft: VaultDraft) async throws -> PreparedVault {
        let (adapter, venue, asset) = try vault()
        let source = try Account(accountId: config.feePayer, sequenceNumber: 0)
        let call: ContractCall
        let shown: SignedTerms
        switch draft.action {
        case .deposit:
            let units = try SwapUnits.units(of: draft.amount, asset: asset)
            // Solde relu : on ne signe jamais sur un solde inconnu ou insuffisant.
            let held = try await SACClient(client: client).balance(token: venue.asset.contract, holder: draft.drawer.address, source: source)
            try PaymentClient.checkBalance(held, units: UInt64(units))
            call = try await adapter.depositCall(venue: venue, amount: TokenAmount(units), authorizer: draft.drawer.address)
            shown = SignedTerms(
                action: .deposit, contract: venue.id, authorizer: draft.drawer.address, assetIn: venue.asset.contract, amountIn: units,
                assetOut: venue.id, minimumOut: nil, route: [], deadline: nil
            )
        case .withdraw:
            guard let minimum = draft.quote.minimumOut else { throw VaultServiceError.priceMoved }
            // Les parts et le minimum **du brouillon** (ceux de l'écran) ; le vault est relu pour vérifier qu'il rend au
            // moins ce minimum maintenant, sinon rien n'est signé.
            let position = YieldPosition(protocolID: adapter.id, venueID: venue.id, holder: draft.drawer.address, shares: 0, value: 0)
            let fresh = try await adapter.withdrawQuote(position: position, amount: TokenAmount(draft.quote.shares.units), all: true)
            guard fresh.shares.units >= draft.quote.shares.units else { throw YieldError.notEnoughShares }
            let value = try await adapter.valueOf(shares: draft.quote.shares, in: venue)
            guard value >= minimum.units else { throw VaultServiceError.priceMoved }
            call = try DeFindexCalls.withdraw(vault: venue.id, from: draft.drawer.address, shares: draft.quote.shares.units, minimumOut: minimum.units)
            shown = SignedTerms(
                action: .withdraw, contract: venue.id, authorizer: draft.drawer.address, assetIn: venue.id, amountIn: draft.quote.shares.units,
                assetOut: venue.asset.contract, minimumOut: minimum.units, route: [], deadline: nil
            )
        }
        let now = UInt64(Date().timeIntervalSince1970)
        try BoundsCheck.verify(shown: shown, signed: try adapter.terms(of: call), quotedOut: draft.quote.expectedOut?.units, now: now)

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
            // La simulation du Main account exécute l'appel : un refus du vault a un nom.
            throw DeFindexAdapter.yieldError(for: error) ?? error
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

    /// La trace de « Check again » : un dépôt envoie l'actif du tiroir au vault ; un retrait le fait revenir du vault au
    /// tiroir (`eventSender`). Le nonce reste celui du tiroir.
    static func trace(of prepared: PreparedVault, integration: PreparedIntegrationCall, asset: String) throws -> PaymentTrace {
        let draft = prepared.draft
        let units = UInt64(try SwapUnits.units(of: draft.amount.truncated(to: 7), asset: draft.vault.asset))
        var trace = integration.trace(token: asset, destination: draft.vault.id, units: units)
        if draft.action == .withdraw {
            trace.eventSender = draft.vault.id
            trace.eventRecipient = draft.drawer.address
        }
        return trace
    }

    func trace(for signed: SignedVault) throws -> PaymentTrace {
        guard let integration = signed.prepared.integration else { throw VaultServiceError.unknownDrawer(signed.prepared.draft.drawer.id) }
        return try Self.trace(of: signed.prepared, integration: integration, asset: try vault().1.asset.contract)
    }

    func submit(_ signed: SignedVault, onProgress: @escaping (PaymentProgress) -> Void) async throws -> VaultReceipt {
        let prepared = signed.prepared
        guard let integration = prepared.integration, let card = signed.card else {
            throw VaultServiceError.unknownDrawer(prepared.draft.drawer.id)
        }
        let venue = try vault().1
        let trace = try Self.trace(of: prepared, integration: integration, asset: venue.asset.contract)
        let hash = try await integrations.submit(integration, signed: card, trace: trace, feeSigner: feeSigner, onProgress: onProgress)
        let value = try? await client.transactionReturnValue(hash)
        let receipt = VaultReceipt(
            summary: VaultSummary(prepared.draft), transactionHash: hash, sentAt: .now,
            explorerURL: explorerURL(transactionHash: hash),
            shares: prepared.draft.action == .deposit ? value.flatMap(DeFindexAdapter.mintedShares).map(SwapUnits.amount(fromUnits:)) : prepared.draft.quote.sharesAmount,
            received: prepared.draft.action == .withdraw ? value.flatMap(DeFindexAdapter.withdrawnAmount).map(SwapUnits.amount(fromUnits:)) : nil
        )
        if let account = session.wallet.account?.address, let label = vaultConfig?.label {
            session.recordActivity(receipt.activityRecord(vault: venue.id, label: label), account: account)
        }
        return receipt
    }

    /// Comme Envoyer : l'opération en attente se vérifie par le nonce de son autorisation. Partie : sa ligne d'historique.
    func check(_ trace: PaymentTrace) async throws -> PaymentCheck {
        let pending = session.wallet.pendingSend
        let result = try await drawers.check(trace)
        if case .sent(let hash) = result, let pending, let summary = VaultSummary(pending, network: config.network),
           let account = session.wallet.account?.address, let label = vaultConfig?.label {
            let value = try? await client.transactionReturnValue(hash)
            let receipt = VaultReceipt(
                summary: summary, transactionHash: hash, sentAt: pending.signedAt, explorerURL: explorerURL(transactionHash: hash),
                shares: summary.action == .deposit ? value.flatMap(DeFindexAdapter.mintedShares).map(SwapUnits.amount(fromUnits:)) : summary.shares,
                received: summary.action == .withdraw ? value.flatMap(DeFindexAdapter.withdrawnAmount).map(SwapUnits.amount(fromUnits:)) : nil
            )
            session.recordActivity(receipt.activityRecord(vault: trace.destination, label: label), account: account)
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
