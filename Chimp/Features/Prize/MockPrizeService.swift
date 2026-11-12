import Foundation

/// Faux service des cadeaux (tests, catalogue, simulateur) : un faux contrat `prize`, aucune requête réseau. Les mêmes
/// étapes que `ChainPrizeService` : coffre relu à la préparation, signatures enchaînées, trace gardée, « Check again ».
final class MockPrizeService: PrizeService, @unchecked Sendable {
    enum Scenario: Equatable {
        case success
        /// Le coffre a changé entre la vérification et la préparation (nouveau montant ; 0 = déjà ouvert).
        case amountChanged(Decimal)
        /// La carte ne détient plus le NFT (`NotChipOwner`).
        case notOwner
        /// L'envoi n'a pas de réponse ; `check` dit ensuite ce qu'il est devenu.
        case unanswered(PaymentCheck)
    }

    var scenario: Scenario
    var delay: Duration
    let network = StellarNetwork.testnet
    var signer: ChipSigner
    private(set) var reserved: [PrizeGift]
    private(set) var pendingSend: PendingSend?
    private(set) var submitted = 0
    private(set) var signedDigestCounts: [Int] = []

    static let prize = "CDXIJB4UZ6DA7OVFH3HYXUKXB7G6Z2ZD4MG7PTONQ5QELL656KMWCZE4"

    init(
        gifts: [PrizeGift] = [MockPrizeService.banana],
        scenario: Scenario = .success,
        signer: ChipSigner? = nil,
        delay: Duration = .milliseconds(400),
        pending: PendingSend? = nil
    ) {
        reserved = gifts
        self.scenario = scenario
        // Pas de faux par défaut dans une signature de fonction (règle de NetworkConfigTests) : le faux signataire est posé ici.
        self.signer = signer ?? MockChipSigner(delay: .zero)
        self.delay = delay
        pendingSend = pending
    }

    static let banana = PrizeGift(
        cardKey: MockChipReader.secp256k1Key, cardName: "Banana", cardColor: .banana, cardNumber: "0007",
        wallet: "CC6Z7JDXX2RXULI2TMY7OGJJ57WXTBRCQDRR4W4IFEJZZ7SPGCPYJEJT", amount: 250, usesPin: true, curve: .secp256k1
    )

    func gifts() async throws -> [PrizeGift] {
        try await Task.sleep(for: delay)
        return reserved
    }

    func prepare(_ gift: PrizeGift) async throws -> PreparedPrizeClaim {
        try await Task.sleep(for: delay)
        switch scenario {
        case .amountChanged(let amount):
            // Un seul changement : la vérification suivante voit le nouveau montant.
            scenario = .success
            if let index = reserved.firstIndex(where: { $0.id == gift.id }) { reserved[index] = gift.withAmount(amount) }
            throw PrizeAmountChanged(amount: amount)
        case .notOwner:
            throw PrizeContract.PrizeError.notCardOwner
        case .success, .unanswered:
            break
        }
        return PreparedPrizeClaim(
            prize: Self.prize, pocket: gift.wallet, card: gift.cardKey, curve: gift.curve,
            amount: TokenAmount(Int128(try SACClient.units(of: gift.amount, keypadDecimals: 7))),
            token: "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC", nfcContract: gift.wallet,
            attestationNonce: 1, pocketNonce: 42, preparedAtLedger: 1_000, expirationLedger: 1_120, passphrase: "Test SDF Network ; September 2015"
        )
    }

    func refreshedIfNeeded(_ prepared: PreparedPrizeClaim, gift: PrizeGift) async throws -> PreparedPrizeClaim {
        prepared
    }

    func sign(_ prepared: PreparedPrizeClaim, pin: String?) async throws -> CardSignatures {
        let attestation = try prepared.attestationDigest
        let signed = try await signer.sign(
            digests: [attestation], followUp: { try prepared.pocketDigests(after: $0) }, acceptedKeys: [prepared.card], pin: pin
        )
        signedDigestCounts.append(signed.signatures.count)
        return signed
    }

    func knownCard(_ key: ChipPublicKey) -> KnownCard? {
        reserved.first { $0.cardKey == key }.map { KnownCard(name: $0.cardName, color: $0.cardColor) }
    }

    func submit(
        _ prepared: PreparedPrizeClaim, gift: PrizeGift, signed: CardSignatures, onProgress: @escaping (PaymentProgress) -> Void
    ) async throws -> PrizeReceipt {
        submitted += 1
        onProgress(.checking)
        try await Task.sleep(for: delay)
        if case .unanswered = scenario {
            throw PaymentFailure(trace: prepared.trace, underlying: StellarError.sendUnanswered(hash: String(repeating: "a", count: 64), detail: "timeout"))
        }
        onProgress(.sending)
        onProgress(.confirming)
        reserved.removeAll { $0.id == gift.id }
        return PrizeReceipt(gift: gift, transactionHash: String(repeating: "0", count: 64), sentAt: .now, explorerURL: nil)
    }

    func check(_ trace: PaymentTrace) async throws -> PaymentCheck {
        try await Task.sleep(for: delay)
        if case .unanswered(let result) = scenario { return result }
        return .nothingSent
    }

    func setPendingSend(_ pending: PendingSend?) throws {
        pendingSend = pending
    }

    func explorerURL(transactionHash: String) -> URL? { nil }
}
