import Foundation
import stellarsdk

/// Le vrai service des cadeaux, sur le réseau de l'app (testnet) : cartes du compte lues sur le téléphone, coffres lus et
/// retrait construit par `PrizeClient` (`Core/Contracts/PrizeClient.swift`), signature par la carte (un seul tap, deux
/// signatures enchaînées), frais par le serveur de frais. Ne fait aucune crypto lui-même.
final class ChainPrizeService: PrizeService {
    let session: AppSession
    let config: ChimpNetworkConfig
    var network: StellarNetwork { config.network }
    private let client: SorobanClient
    private let prize: PrizeClient?
    private let payments: PaymentClient
    private let signer: ChipSigner
    private let feeSigner: FeeSigner

    init(session: AppSession, signer: ChipSigner = NFCChipSigner(), feeSigner: FeeSigner? = nil) {
        self.session = session
        config = session.config
        let config = session.config
        let client = SorobanClient(config: config)
        self.client = client
        prize = config.contracts.prize.map { PrizeClient(client: client, config: config, contract: $0) }
        payments = PaymentClient(client: client, config: config)
        self.signer = signer
        self.feeSigner = feeSigner ?? WorkerFeeSigner(url: config.feeSignerURL)
    }

    /// Le contrat est-il configuré sur ce réseau ? Sinon rien n'est lu, rien ne s'affiche.
    static func isAvailable(_ config: ChimpNetworkConfig) -> Bool {
        config.contracts.prize != nil
    }

    // MARK: Les cadeaux

    /// Une carte du compte, telle que ce téléphone la connaît (clé, wallet, nom, couleur, puce).
    private struct Card {
        let key: ChipPublicKey
        let wallet: String
        let saved: SavedCard
    }

    private var cards: [Card] {
        (session.wallet.account?.cards ?? []).compactMap { saved in
            guard let wallet = saved.pocket, let key = try? ChipPublicKey(Data(hex: saved.publicKey) ?? Data()) else { return nil }
            return Card(key: key, wallet: wallet, saved: saved)
        }
    }

    func gifts() async throws -> [PrizeGift] {
        guard let prize else { return [] }
        guard session.wallet.account != nil else { throw PrizeServiceError.noAccount }
        let cards = cards
        guard !cards.isEmpty else { return [] }
        let source = try await client.account(config.feePayer)
        // Un coffre par carte, lus ensemble ; l'ordre des cartes est gardé.
        let reserved: [(Int, TokenAmount)] = try await withThrowingTaskGroup(of: (Int, TokenAmount).self) { group in
            for (index, card) in cards.enumerated() {
                group.addTask { (index, try await prize.reserved(for: card.key, source: try PocketClient.copy(source))) }
            }
            var found: [(Int, TokenAmount)] = []
            for try await entry in group { found.append(entry) }
            return found.sorted { $0.0 < $1.0 }
        }
        return reserved.compactMap { index, amount in
            guard amount.units > 0 else { return nil }
            return gift(cards[index], amount: amount)
        }
    }

    private func gift(_ card: Card, amount: TokenAmount) -> PrizeGift {
        let isDuox = card.saved.chip == ChipKind.duox.rawValue
        return PrizeGift(
            cardKey: card.key,
            cardName: card.saved.name ?? String(localized: "Card"),
            cardColor: card.saved.color.flatMap(ChimpCardColor.init(rawValue:)) ?? .jungle,
            cardNumber: card.saved.tokenID.map { String(format: "%04u", $0) },
            wallet: card.wallet,
            amount: SACClient.amount(fromUnits: Decimal(string: String(amount.units)) ?? 0),
            // Puce inconnue sur ce téléphone : on suppose une Infineon avec PIN (comme Envoyer).
            usesPin: !isDuox,
            curve: isDuox ? .p256 : .secp256k1
        )
    }

    // MARK: Avant le tap

    func prepare(_ gift: PrizeGift) async throws -> PreparedPrizeClaim {
        guard let prize else { throw PrizeServiceError.unavailable }
        guard let card = cards.first(where: { $0.key == gift.cardKey }), card.wallet == gift.wallet else {
            throw PrizeServiceError.unknownCard
        }
        let prepared = try await prize.prepareClaim(pocket: gift.wallet, card: gift.cardKey, curve: gift.curve)
        // Le contrat donne **tout** le coffre : s'il a changé depuis la vérification, rien n'est signé (règle 8).
        let now = SACClient.amount(fromUnits: Decimal(string: String(prepared.amount.units)) ?? 0)
        guard now == gift.amount else { throw PrizeAmountChanged(amount: now) }
        return prepared
    }

    func refreshedIfNeeded(_ prepared: PreparedPrizeClaim, gift: PrizeGift) async throws -> PreparedPrizeClaim {
        guard let prize else { throw PrizeServiceError.unavailable }
        do {
            try await prize.checkFresh(prepared)
            return prepared
        } catch IntegrationCallClient.SigningError.authorizationExpiring {
            return try await self.prepare(gift)
        }
    }

    // MARK: Le tap

    func sign(_ prepared: PreparedPrizeClaim, pin: String?) async throws -> CardSignatures {
        let attestation = try prepared.attestationDigest
        return try await signer.sign(
            digests: [attestation], followUp: { try prepared.pocketDigests(after: $0) },
            acceptedKeys: [prepared.card], pin: pin
        )
    }

    func knownCard(_ key: ChipPublicKey) -> KnownCard? {
        guard let saved = session.wallet.account?.cards.first(where: { $0.publicKey == key.hex }) else { return nil }
        return KnownCard(name: saved.name ?? String(localized: "Card"), color: saved.color.flatMap(ChimpCardColor.init(rawValue:)) ?? .jungle)
    }

    // MARK: Après le tap

    func submit(
        _ prepared: PreparedPrizeClaim, gift: PrizeGift, signed: CardSignatures, onProgress: @escaping (PaymentProgress) -> Void
    ) async throws -> PrizeReceipt {
        guard let prize else { throw PrizeServiceError.unavailable }
        let hash = try await prize.submit(prepared, signed: signed, feeSigner: feeSigner, onProgress: onProgress)
        let receipt = PrizeReceipt(gift: gift, transactionHash: hash, sentAt: .now, explorerURL: explorerURL(transactionHash: hash))
        if let account = session.wallet.account?.address {
            session.recordActivity(receipt.activityRecord(prize: prepared.prize), account: account)
        }
        return receipt
    }

    /// Comme Envoyer : le retrait en attente se vérifie par le nonce de l'autorisation du wallet. Parti : sa ligne.
    func check(_ trace: PaymentTrace) async throws -> PaymentCheck {
        let pending = session.wallet.pendingSend
        let result = try await payments.check(trace)
        if case .sent(let hash) = result, pending?.prize != nil, let account = session.wallet.account?.address,
           let sender = trace.eventSender {
            session.recordActivity(.gift(
                hash: hash, prize: sender, wallet: trace.from, assetCode: SendAsset.xlm.code,
                amount: SACClient.amount(fromUnits: Decimal(trace.units)), at: pending?.signedAt ?? .now
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

/// Le coffre a changé entre la vérification et la signature : rien n'a été signé. `amount` : ce qui est mis de côté
/// maintenant (0 : déjà retiré, par exemple depuis un autre téléphone).
struct PrizeAmountChanged: Error, Equatable {
    let amount: Decimal
}
