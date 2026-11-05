import Foundation
import stellarsdk

/// Le vrai service du vault Sentora (décision de Barth du 2026-11-05 ; testnet : copie de test, même wasm que le mainnet),
/// sur le modèle de `ChainLendingService` pour réutiliser les écrans du prêt : montant exact au dépôt et au retrait, pas de
/// parts. Tiroirs et cartes lus comme Envoyer, dépôts lus directement dans les données du vault (`SentoraCalls`),
/// signature par la carte, frais par le serveur de frais. Ne fait aucune crypto lui-même.
///
/// Ce que l'app montre : le montant déposé (le vault le rend tel quel). Les récompenses de Sentora (un taux publié, réclamé
/// en fin de période avec une preuve de son serveur) ne sont ni lues ni réclamées ici ; la vérification dit avant de
/// signer qu'un retrait anticipé les fait perdre (règle 8).
///
/// - Main account : ordre 2, l'arbre simulé doit être exactement l'arbre déclaré.
/// - Wallet d'une carte : ordre 1, l'arbre déclaré est signé avant toute simulation.
final class ChainSentoraService: VaultService {
    let session: AppSession
    let config: ChimpNetworkConfig
    var network: StellarNetwork { config.network }
    private let drawers: ChainSendService
    private let client: SorobanClient
    private let integrations: IntegrationCallClient
    private let vault: IntegrationConfig.Sentora?
    private let asset: (code: String, contract: String)?
    private let signer: ChipSigner
    private let feeSigner: FeeSigner

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
        let config = session.config
        let vault = config.integrations?.sentora
        self.vault = vault
        let assets = (try? SACClient.stellarAssets(config: config)) ?? []
        asset = vault.flatMap { vault in assets.first { $0.code == vault.assetCode } }
        self.signer = signer
        self.feeSigner = feeSigner ?? WorkerFeeSigner(url: config.feeSignerURL)
    }

    private func place() throws -> (IntegrationConfig.Sentora, (code: String, contract: String), SendAsset) {
        guard let vault, let asset, let sendAsset = SendAsset(code: asset.code) else { throw VaultServiceError.noVault }
        return (vault, asset, sendAsset)
    }

    // MARK: Contexte

    /// Les tiroirs, puis en **une** lecture : l'état du vault (pause, total) et le dépôt de chaque tiroir.
    func fetchContext() async throws -> VaultContext {
        let (vault, _, sendAsset) = try place()
        let context = try await drawers.fetchContext()
        let read: (SentoraCalls.VaultState, [String: Int128])
        do {
            read = try await ReadCache.shared.read("defi:sentora:\(config.passphrase):\(vault.vault):\(context.drawers.map(\.address).joined(separator: ","))") {
                try await self.readVault(vault.vault, holders: context.drawers.map(\.address))
            }
        } catch {
            throw VaultServiceError.vaultUnavailable
        }
        let records = session.wallet.account.map { session.activity.activity(of: $0.address).records } ?? []
        let holdings = context.drawers.compactMap { drawer -> VaultHolding? in
            guard let units = read.1[drawer.address], units > 0 else { return nil }
            let value = SwapUnits.amount(fromUnits: units)
            return VaultHolding(
                drawerID: drawer.id, drawerAddress: drawer.address, shares: value, value: value,
                basis: VaultBasis.from(records: records, drawer: drawer.address, vault: vault.vault), readAt: .now
            )
        }
        return VaultContext(network: context.network, drawers: context.drawers, vault: Self.info(vault, asset: sendAsset, state: read.0), holdings: holdings)
    }

    /// L'instance du vault et le dépôt de chaque adresse, dans une seule requête `getLedgerEntries`.
    private func readVault(_ vault: String, holders: [String]) async throws -> (SentoraCalls.VaultState, [String: Int128]) {
        let instanceKey = try SentoraCalls.instanceKey(vault: vault)
        let depositKeys = try holders.map { (holder: $0, key: try SentoraCalls.depositKey(vault: vault, holder: $0)) }
        let entries = try await client.ledgerEntries([instanceKey] + depositKeys.map(\.key))
        func value(of key: String) throws -> SCValXDR? {
            guard let entry = entries.first(where: { $0.key == key }) else { return nil }
            guard case .contractData(let data) = try LedgerEntryDataXDR(fromBase64: entry.xdr) else {
                throw StellarError.invalidResponse("Sentora entry is not contract data")
            }
            return data.val
        }
        let state = try SentoraCalls.state(instance: try value(of: instanceKey))
        var principals: [String: Int128] = [:]
        for (holder, key) in depositKeys {
            guard let record = try value(of: key) else { continue }
            guard let units = SentoraCalls.principal(record, holder: holder) else { throw StellarError.invalidResponse("Sentora deposit is malformed") }
            principals[holder] = units
        }
        return (state, principals)
    }

    static func info(_ vault: IntegrationConfig.Sentora, asset: SendAsset, state: SentoraCalls.VaultState) -> VaultInfo {
        let total = SwapUnits.amount(fromUnits: state.totalPrincipal)
        return VaultInfo(
            id: vault.vault, name: vault.name, protocols: ["Sentora"], asset: asset, invested: 0, totalManaged: total,
            kind: .lending, mark: .sentora, depositsBlocked: state.paused, withdrawalsBlocked: state.paused
        )
    }

    // MARK: Devis

    func depositQuote(drawer: SendDrawer, amount: Decimal) async throws -> VaultQuote {
        let (_, _, asset) = try place()
        let units = try SwapUnits.units(of: amount, asset: asset)
        guard units > 0 else { throw YieldError.amountTooSmall }
        return VaultQuote(action: .deposit, amount: amount, shares: TokenAmount(units), expectedOut: nil, minimumOut: nil, all: false)
    }

    /// Le montant exact qui reviendra, après avoir relu le dépôt du tiroir : jamais plus que lui. « Tout » : le dépôt entier.
    func withdrawQuote(drawer: SendDrawer, amount: Decimal, all: Bool) async throws -> VaultQuote {
        let (vault, _, asset) = try place()
        let (state, principals) = try await readVault(vault.vault, holders: [drawer.address])
        guard !state.paused else { throw YieldError.vaultUnavailable }
        let principal = principals[drawer.address] ?? 0
        let units = all ? principal : try SwapUnits.units(of: amount, asset: asset)
        guard units > 0 else { throw YieldError.amountTooSmall }
        guard units <= principal else { throw YieldError.notEnoughShares }
        return VaultQuote(
            action: .withdraw, amount: SwapUnits.amount(fromUnits: units), shares: TokenAmount(units),
            expectedOut: TokenAmount(units), minimumOut: TokenAmount(units), all: all
        )
    }

    // MARK: Avant le tap

    func prepare(_ draft: VaultDraft) async throws -> PreparedVault {
        let (vault, asset, sendAsset) = try place()
        let source = try Account(accountId: config.feePayer, sequenceNumber: 0)
        // Lu pendant les autres lectures (vitesse, comme Swap et Grow).
        async let accountCards = mainAccountCards(of: draft.drawer, source: source)
        let units = draft.quote.shares.units
        let call: ContractCall
        switch draft.action {
        case .deposit:
            // Solde et vault relus ensemble : on ne signe jamais sur un solde inconnu ou insuffisant, ni vers un vault en pause.
            async let heldRead = SACClient(client: client).balance(token: asset.contract, holder: draft.drawer.address, source: source)
            async let stateRead = readVault(vault.vault, holders: [])
            try PaymentClient.checkBalance(try await heldRead, units: UInt64(try SwapUnits.units(of: draft.amount, asset: sendAsset)))
            guard !(try await stateRead).0.paused else { throw YieldError.vaultUnavailable }
            call = try SentoraCalls.deposit(vault: vault.vault, from: draft.drawer.address, units: units)
        case .withdraw:
            // Le montant **du brouillon** ; le dépôt relu doit encore le couvrir, sinon rien n'est signé.
            let (state, principals) = try await readVault(vault.vault, holders: [draft.drawer.address])
            guard !state.paused else { throw YieldError.vaultUnavailable }
            guard units <= principals[draft.drawer.address] ?? 0 else { throw YieldError.notEnoughShares }
            call = try SentoraCalls.withdraw(vault: vault.vault, from: draft.drawer.address, units: units)
        }
        let shown = draft.action == .deposit
            ? SignedTerms(
                action: .deposit, contract: vault.vault, authorizer: draft.drawer.address, assetIn: asset.contract, amountIn: units,
                assetOut: vault.vault, minimumOut: nil, route: [], deadline: nil
            )
            : SignedTerms(
                action: .withdraw, contract: vault.vault, authorizer: draft.drawer.address, assetIn: vault.vault, amountIn: units,
                assetOut: asset.contract, minimumOut: draft.quote.minimumOut?.units, route: [], deadline: nil
            )
        let now = UInt64(Date().timeIntervalSince1970)
        try BoundsCheck.verify(
            shown: shown, signed: try SentoraCalls.terms(of: call, vault: vault.vault, asset: asset.contract),
            quotedOut: draft.quote.expectedOut?.units, now: now
        )

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
                call: call, authorizer: authorizer, shape: SentoraAuthShape(vault: vault.vault, asset: asset.contract), acceptedKeys: acceptedKeys
            )
            return PreparedVault(draft: draft, integration: integration)
        } catch {
            // La simulation du Main account exécute l'appel : un refus du vault a un nom (pause, dépôt insuffisant).
            throw SentoraCalls.yieldError(for: error) ?? error
        }
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

    func trace(for signed: SignedVault) throws -> PaymentTrace {
        guard let integration = signed.prepared.integration else { throw VaultServiceError.unknownDrawer(signed.prepared.draft.drawer.id) }
        return try ChainLendingService.trace(of: signed.prepared, integration: integration, asset: try place().1.contract)
    }

    func submit(_ signed: SignedVault, onProgress: @escaping (PaymentProgress) -> Void) async throws -> VaultReceipt {
        let prepared = signed.prepared
        guard let integration = prepared.integration, let card = signed.card else {
            throw VaultServiceError.unknownDrawer(prepared.draft.drawer.id)
        }
        let (vault, asset, _) = try place()
        let trace = try ChainLendingService.trace(of: prepared, integration: integration, asset: asset.contract)
        let hash = try await integrations.submit(integration, signed: card, trace: trace, feeSigner: feeSigner, onProgress: onProgress)
        // Le vault rend exactement le montant signé, ou refuse : c'est ce qui revient.
        let receipt = VaultReceipt(
            summary: VaultSummary(prepared.draft), transactionHash: hash, sentAt: .now, explorerURL: explorerURL(transactionHash: hash),
            shares: nil, received: prepared.draft.action == .withdraw ? prepared.draft.quote.expected : nil
        )
        if let account = session.wallet.account?.address {
            session.recordActivity(receipt.activityRecord(vault: vault.vault, label: vault.label), account: account)
        }
        return receipt
    }

    func check(_ trace: PaymentTrace) async throws -> PaymentCheck {
        let pending = session.wallet.pendingSend
        let result = try await drawers.check(trace)
        if case .sent(let hash) = result, let pending, let summary = VaultSummary(pending, network: config.network),
           let account = session.wallet.account?.address, let vault {
            let receipt = VaultReceipt(
                summary: summary, transactionHash: hash, sentAt: pending.signedAt, explorerURL: explorerURL(transactionHash: hash),
                shares: nil, received: summary.action == .withdraw ? summary.amount : nil
            )
            session.recordActivity(receipt.activityRecord(vault: vault.vault, label: vault.label), account: account)
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
