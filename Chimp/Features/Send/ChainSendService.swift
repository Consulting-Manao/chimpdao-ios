import Foundation
import stellarsdk

/// Le vrai service d'envoi, sur le réseau de l'app (testnet) : soldes et tiroirs lus comme le Wallet
/// (`ChainWalletDataSource`, sans copie), paiement par `PaymentClient` (`Core/Contracts/Payment.swift`), signature
/// par la carte (`ChipSigner`), frais par le serveur de frais. Ne fait aucune crypto lui-même.
///
/// - Main account : ordre 2 (« simuler puis signer »), n'importe quelle carte du compte.
/// - Wallet d'une carte : ordre 1 (« signer puis simuler »), seulement cette carte.
final class ChainSendService: SendService {
    let session: AppSession
    let config: ChimpNetworkConfig
    private let wallet: WalletDataSource
    private let payments: PaymentClient
    private let signer: ChipSigner
    private let feeSigner: FeeSigner

    /// Clé publique de chaque tiroir « carte », d'après la dernière lecture (`SendDrawer.id` = clé en hexadécimal).
    private var cardKeys: [String: ChipPublicKey] = [:]

    init(
        session: AppSession,
        config: ChimpNetworkConfig = .testnet,
        wallet: WalletDataSource? = nil,
        signer: ChipSigner = NFCChipSigner(),
        feeSigner: FeeSigner? = nil
    ) {
        self.session = session
        self.config = config
        self.wallet = wallet ?? ChainWalletDataSource(session: session, chain: ChainWalletReader(config: config), oracle: ReflectorPriceOracle())
        payments = PaymentClient(client: SorobanClient(config: config), config: config)
        self.signer = signer
        self.feeSigner = feeSigner ?? WorkerFeeSigner(url: config.feeSignerURL)
    }

    enum SendServiceError: LocalizedError, Equatable {
        case noAccount
        /// Tiroir sans adresse de wallet (carte sans Pocket) ou inconnu.
        case unknownDrawer(String)

        var errorDescription: String? {
            switch self {
            case .noAccount: "No account is open on this phone."
            case .unknownDrawer(let id): "Unknown drawer \(id)."
            }
        }
    }

    // MARK: Contexte

    func fetchContext() async throws -> SendContext {
        guard let account = session.wallet.account else { throw SendServiceError.noAccount }
        let snapshot = try await wallet.fetchWallet()
        var keys: [String: ChipPublicKey] = [:]
        var drawers = [SendDrawer(
            id: "main", kind: .main, address: account.address,
            balances: Self.balances(snapshot.main.assets),
            // Un PIN peut être demandé si au moins une carte du compte est une Infineon (ou de puce inconnue).
            usesPin: snapshot.cards.contains { usesPin(cardID: $0.id) }
        )]
        for card in snapshot.cards {
            guard let pocket = card.pocket, let key = try? ChipPublicKey(Data(hex: card.id) ?? Data()) else { continue }
            keys[card.id] = key
            drawers.append(SendDrawer(
                id: card.id, kind: .card(name: card.name, color: card.color), address: pocket,
                balances: Self.balances(card.assets), usesPin: usesPin(cardID: card.id)
            ))
        }
        cardKeys = keys
        var prices: [SendAsset: Decimal] = [:]
        if let xlm = snapshot.usdPrices["XLM"] { prices[.xlm] = xlm }
        // Carnet de destinataires : plus tard (jalon 4b), sur le téléphone. Récents vides en attendant.
        return SendContext(network: session.network, drawers: drawers, recents: [], usdPrices: prices)
    }

    /// Infineon : PIN obligatoire à l'onboarding (DESIGN_NOTES §12). DUOX : jamais de PIN. Puce inconnue sur ce
    /// téléphone : on suppose un PIN (la carte dira au tap si elle en a vraiment un).
    private func usesPin(cardID: String) -> Bool {
        let saved = session.wallet.account?.cards.first { $0.publicKey == cardID }
        return saved?.chip != ChipKind.duox.rawValue
    }

    private static func balances(_ assets: [AssetAmount]) -> [SendAsset: Decimal] {
        var result: [SendAsset: Decimal] = [:]
        for asset in assets {
            if let known = SendAsset.allCases.first(where: { $0.code == asset.code }) { result[known] = asset.amount }
        }
        return result
    }

    // MARK: Avant le tap

    func prepare(_ draft: SendDraft) async throws -> PreparedSend {
        let units = try SACClient.units(of: draft.amount, keypadDecimals: draft.asset.maxFractionDigits)
        guard let token = try SACClient.stellarAssets(config: config).first(where: { $0.code == draft.asset.code })?.contract else {
            throw SendServiceError.unknownDrawer(draft.asset.code)
        }
        let payment: PreparedPayment
        switch draft.drawer.kind {
        case .main:
            payment = try await payments.prepareFromAccount(
                account: draft.drawer.address, token: token, destination: draft.recipient.address, units: units
            )
        case .card:
            guard let key = cardKeys[draft.drawer.id] else { throw SendServiceError.unknownDrawer(draft.drawer.id) }
            payment = try await payments.prepareFromPocket(
                pocket: draft.drawer.address, card: key, token: token, destination: draft.recipient.address, units: units
            )
        }
        return PreparedSend(draft: draft, payment: payment)
    }

    func refreshedIfNeeded(_ prepared: PreparedSend) async throws -> PreparedSend {
        guard let payment = prepared.payment else { return try await self.prepare(prepared.draft) }
        return try await payments.needsRefresh(payment) ? try await self.prepare(prepared.draft) : prepared
    }

    // MARK: Le tap

    func readCard(for prepared: PreparedSend) async throws -> CardRead {
        guard let payment = prepared.payment else { throw SendServiceError.unknownDrawer(prepared.draft.drawer.id) }
        switch try await signer.readOrSign(digests: [payment.digest], acceptedKeys: payment.acceptedKeys) {
        case .needsPIN(let card):
            let local = localCard(card.publicKey)
            return CardRead(
                check: CardCheck(cardName: local.name, cardColor: local.color, usesPin: true, publicKey: card.publicKey),
                signed: nil
            )
        case .signed(let signed):
            let local = localCard(signed.card.publicKey)
            return CardRead(
                check: CardCheck(cardName: local.name, cardColor: local.color, usesPin: false, publicKey: signed.card.publicKey),
                signed: SignedSend(prepared: prepared, cardName: local.name, card: signed)
            )
        }
    }

    func sign(_ prepared: PreparedSend, pin: String?, onlyCard: ChipPublicKey?) async throws -> SignedSend {
        guard let payment = prepared.payment else { throw SendServiceError.unknownDrawer(prepared.draft.drawer.id) }
        // Second tap de l'ordre « tap puis PIN » : seulement la carte lue au premier tap (si elle peut toujours signer).
        let keys = onlyCard.map { only in payment.acceptedKeys.filter { $0 == only } } ?? payment.acceptedKeys
        let signed = try await signer.sign(digests: [payment.digest], acceptedKeys: keys, pin: pin)
        return SignedSend(prepared: prepared, cardName: localCard(signed.card.publicKey).name, card: signed)
    }

    /// Clé de la carte d'un tiroir « carte », d'après la dernière lecture (`fetchContext`) : Swap s'en sert pour savoir
    /// quelle carte peut signer depuis ce wallet.
    func cardKey(drawerID: String) -> ChipPublicKey? {
        cardKeys[drawerID]
    }

    func knownCard(_ key: ChipPublicKey) -> KnownCard? {
        let isMember = cardKeys.values.contains(key) || session.wallet.account?.cards.contains { $0.publicKey == key.hex } == true
        guard isMember else { return nil }
        let local = localCard(key)
        return KnownCard(name: local.name, color: local.color)
    }

    /// Nom et couleur locaux d'une carte (« Card » et Jungle si ce téléphone ne la connaît pas, comme le Wallet).
    func localCard(_ key: ChipPublicKey) -> (name: String, color: ChimpCardColor) {
        let saved = session.wallet.account?.cards.first { $0.publicKey == key.hex }
        return (saved?.name ?? String(localized: "Card"), saved?.color.flatMap(ChimpCardColor.init(rawValue:)) ?? .jungle)
    }

    // MARK: Après le tap

    func submit(_ signed: SignedSend, onProgress: @escaping (PaymentProgress) -> Void) async throws -> SendReceipt {
        guard let payment = signed.prepared.payment, let card = signed.card else {
            throw SendServiceError.unknownDrawer(signed.prepared.draft.drawer.id)
        }
        let hash = try await payments.submit(payment, signed: card, feeSigner: feeSigner, onProgress: onProgress)
        let receipt = SendReceipt(
            summary: SendSummary(signed.prepared.draft), transactionHash: hash, sentAt: .now,
            explorerURL: explorerURL(transactionHash: hash)
        )
        // La ligne d'historique est celle du reçu : C9 et l'Activity montrent le même reçu.
        if let account = session.wallet.account?.address {
            session.recordActivity(receipt.activityRecord, account: account)
        }
        return receipt
    }

    func check(_ trace: PaymentTrace) async throws -> PaymentCheck {
        let result = try await payments.check(trace)
        // Un paiement en attente finalement parti : écrit dans l'historique comme un envoi confirmé. Pas un swap : ses deux
        // côtés reviennent de la chaîne.
        if case .sent(let hash) = result, session.wallet.pendingSend?.swap == nil, let account = session.wallet.account?.address,
           let code = (try? SACClient.stellarAssets(config: config))?.first(where: { $0.contract == trace.token })?.code {
            session.recordActivity(.payment(
                hash: hash, from: trace.from, to: trace.destination, assetCode: code,
                amount: SACClient.amount(fromUnits: Decimal(trace.units)), at: session.wallet.pendingSend?.signedAt ?? .now
            ), account: account)
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
