import Foundation
import stellarsdk

/// Contrat `prize` (carte partenaire, livrable D5) : de l'argent mis de côté pour **une carte**, que seule cette carte peut
/// retirer vers son wallet (`reference/chimp-contracts/examples/prize`). Le terminal ne l'utilise pas encore : ce client
/// suit le contrat et son README (« redeem takes the redeemer's own wallet auth and a chip attestation »).
///
/// - `deposit(from, amount, token_id)` : `from` autorise, le jeton du contrat (XLM sur testnet) part de `from` vers le
///   contrat et s'ajoute au coffre de la puce du NFT `token_id`. Les dépôts s'additionnent.
/// - `redeem(redeemer, auth, public_key, nonce)` : `redeemer` autorise ; la puce atteste **cet appel** (`call_digest`,
///   domaine `chimpdao.prize.v1`, arguments `[redeemer]`, nonce strictement plus grand que le dernier) ; `redeemer` doit
///   être le propriétaire du NFT de la carte (sa Pocket) ; tout le coffre part vers `redeemer`.
/// - Personne ne retire : l'argent reste dans le contrat. Il n'y a ni date limite ni remboursement.
///
/// Adaptation à l'iPhone (DESIGN_NOTES §13) : l'attestation est un argument de `redeem`, donc une partie de l'appel que la
/// Pocket autorise ensuite (ordre 1). La carte signe d'abord l'attestation, puis, **dans le même tap**, l'autorisation de la
/// Pocket pour chaque `recovery_id` possible de l'attestation (0 et 1 : l'app n'a pas de bibliothèque secp256k1 pour le
/// trouver avant). Après le tap, une simulation de `verify_for_card` dit lequel est le bon, comme `CardPossession`.
enum PrizeContract {
    /// `DOMAIN` du contrat : distinct de celui de `nfc-nft`, les attestations ne passent pas de l'un à l'autre.
    static let domain = "chimpdao.prize.v1"

    /// Erreurs du contrat (`errors.rs`).
    enum PrizeError: Int, Error, Equatable, CaseIterable, LocalizedError {
        /// Rien n'est mis de côté pour cette carte (`NoVaultForChip`).
        case nothingReserved = 400
        /// `redeemer` n'est pas le propriétaire du NFT de la carte (`NotChipOwner`).
        case notCardOwner = 401
        /// L'attestation ne vérifie pas, ou son nonce a déjà servi (`InvalidSignature`).
        case invalidAttestation = 402
        /// Dépôt nul ou négatif (`InvalidAmount`).
        case invalidAmount = 403

        var errorDescription: String? {
            switch self {
            case .nothingReserved: "Nothing is reserved for this card."
            case .notCardOwner: "This wallet doesn't own the card."
            case .invalidAttestation: "The card's signature for this claim wasn't accepted."
            case .invalidAmount: "The amount must be more than zero."
            }
        }

        /// L'erreur du contrat dans le texte d'une simulation refusée (`Error(Contract, #400)`), sinon `nil`.
        /// Attention : `#402` est aussi le code de refus d'une Pocket (`RecoveryIDSearch.RejectionCode.pocket`).
        static func `in`(_ error: Error) -> PrizeError? {
            guard case StellarError.simulationFailed(let message) = error else { return nil }
            return allCases.first { message.contains("Error(Contract, #\($0.rawValue))") }
        }
    }

    /// Ce que la puce atteste : `call_digest(DOMAIN, prize, "redeem", [redeemer], nonce)`.
    static func redeemDigest(prize: String, redeemer: String, nonce: UInt32) throws -> Data {
        try ChipCallDigest.callDigest(
            domain: domain, contractID: prize, function: "redeem",
            arguments: [try ContractArgument.address(redeemer)], nonce: nonce
        )
    }

    /// Arguments de `redeem(redeemer, auth, public_key, nonce)`.
    static func redeemArguments(redeemer: String, attestation: SCValXDR, publicKey: ChipPublicKey, nonce: UInt32) throws -> [SCValXDR] {
        [try ContractArgument.address(redeemer), attestation, .bytes(publicKey.bytes), .u32(nonce)]
    }

    /// Arguments de `deposit(from, amount, token_id)`.
    static func depositArguments(from: String, amount: TokenAmount, tokenID: UInt32) throws -> [SCValXDR] {
        [try ContractArgument.address(from), ContractArgument.i128(amount.units), .u32(tokenID)]
    }

    /// `ChipAuth` de l'attestation, pour un `recovery_id` donné (Infineon) ou tel quel (DUOX).
    static func attestation(_ signed: ChipSignedDigest, recoveryID: UInt32) throws -> SCValXDR {
        switch signed {
        case .secp256k1(let signature): try ChipAuthEncoding.chipAuthSecp256k1(signature: signature, recoveryID: recoveryID)
        case .p256(let signature, let rndB): try ChipAuthEncoding.chipAuthSecp256r1(signature: signature, rndB: rndB)
        }
    }

    /// `recovery_id` possibles de l'attestation, dont l'autorisation de la Pocket est signée dans le même tap. Infineon :
    /// 0 et 1 (2 et 3 ne servent que si `r` dépasse l'ordre de la courbe, une chance sur 2^127 environ). DUOX : aucun.
    static func attestationRecoveryIDs(for curve: ChipCurve) -> [UInt32] {
        curve == .secp256k1 ? [0, 1] : [0]
    }
}

/// Retrait préparé **avant** le tap (règle 9) : le coffre relu, le propriétaire du NFT vérifié, le nonce de l'attestation,
/// le dernier ledger et le nonce de l'autorisation de la Pocket. Tout ce que la carte signera s'en déduit sans réseau.
struct PreparedPrizeClaim: Equatable, Sendable {
    let prize: String
    /// La Pocket de la carte : elle autorise et elle reçoit.
    let pocket: String
    let card: ChipPublicKey
    let curve: ChipCurve
    /// Ce qui est mis de côté (unités on-chain du jeton du contrat).
    let amount: TokenAmount
    /// Jeton du contrat (SAC XLM sur testnet).
    let token: String
    /// `nfc-nft` lié au contrat (`nfc_contract()`), pour la simulation de `verify_for_card`.
    let nfcContract: String
    let attestationNonce: UInt32
    /// Nonce de l'autorisation de la Pocket (aléatoire) : il identifie notre autorisation pour « Check again ».
    let pocketNonce: Int64
    let preparedAtLedger: UInt32
    let expirationLedger: UInt32
    let passphrase: String

    /// Premier digest du tap : l'attestation de la puce.
    var attestationDigest: Data {
        get throws { try PrizeContract.redeemDigest(prize: prize, redeemer: pocket, nonce: attestationNonce) }
    }

    /// L'appel `redeem` avec cette attestation.
    func call(attestation: SCValXDR) throws -> ContractCall {
        ContractCall(
            contract: prize, function: "redeem",
            arguments: try PrizeContract.redeemArguments(redeemer: pocket, attestation: attestation, publicKey: card, nonce: attestationNonce)
        )
    }

    /// L'arbre que la Pocket autorise (ordre 1, déclaré) : `redeem` seul, sans sous-appel. Le contrat ne demande aucune
    /// autre autorisation au `redeemer` (le transfert part du contrat, `verify_for_card` et `owner_of` sont des lectures).
    func declaredAuthorization(attestation: SCValXDR) throws -> DeclaredAuthorization {
        try DeclaredAuthorization(
            authorizer: pocket, invocation: try call(attestation: attestation).invocation(),
            passphrase: passphrase, expirationLedger: expirationLedger, nonce: pocketNonce
        )
    }

    /// Digests suivants du tap, calculés à partir de l'attestation signée : l'autorisation de la Pocket pour chaque
    /// `recovery_id` possible, dans l'ordre de `PrizeContract.attestationRecoveryIDs`.
    func pocketDigests(after signatures: [ChipSignedDigest]) throws -> [Data] {
        guard signatures.count == 1, let attestation = signatures.first else {
            throw ChipError.malformedResponse("expected 1 attestation, got \(signatures.count)")
        }
        try Self.checkCurve(attestation, curve)
        return try PrizeContract.attestationRecoveryIDs(for: curve).map {
            try declaredAuthorization(attestation: try PrizeContract.attestation(attestation, recoveryID: $0)).digest
        }
    }

    static func checkCurve(_ signed: ChipSignedDigest, _ curve: ChipCurve) throws {
        switch (curve, signed) {
        case (.secp256k1, .secp256k1), (.p256, .p256): return
        default: throw ChipError.malformedResponse("the signature doesn't match the card's curve")
        }
    }

    /// La trace de « Check again » : le transfert du contrat vers la Pocket, et le nonce de l'autorisation de la Pocket.
    var trace: PaymentTrace {
        PaymentTrace(
            token: token, from: pocket, destination: pocket, units: UInt64(clamping: amount.units), nonce: pocketNonce,
            preparedAtLedger: preparedAtLedger, expirationLedger: expirationLedger, eventSender: prize, eventRecipient: pocket
        )
    }
}

/// Lectures et retrait du contrat `prize`. Frais payés par ChimpDAO (serveur de frais), comme les autres appels.
struct PrizeClient {
    let client: SorobanClient
    let config: ChimpNetworkConfig
    let contract: String

    /// `get_redeemable(chip_public_key)` : ce qui est mis de côté pour cette carte (0 si rien).
    func reserved(for card: ChipPublicKey, source: Account) async throws -> TokenAmount {
        let value = try await client.readValue(source: source, contract: contract, function: "get_redeemable", arguments: [.bytes(card.bytes)])
        guard let units = ContractArgument.int128(value), units >= 0 else {
            throw StellarError.invalidResponse("get_redeemable returned \(value)")
        }
        return TokenAmount(units)
    }

    /// `get_nonce(public_key)` : dernier nonce d'attestation utilisé (0 au départ).
    func nonce(for card: ChipPublicKey, source: Account) async throws -> UInt32 {
        let value = try await client.readValue(source: source, contract: contract, function: "get_nonce", arguments: [.bytes(card.bytes)])
        guard let nonce = value.u32 else { throw StellarError.invalidResponse("get_nonce returned \(value)") }
        return nonce
    }

    /// `nfc_contract()` : la campagne NFT à laquelle le contrat se fie.
    func nfcContract(source: Account) async throws -> String {
        let value = try await client.readValue(source: source, contract: contract, function: "nfc_contract")
        guard let address = value.address, case .contract = address else {
            throw StellarError.invalidResponse("nfc_contract returned \(value)")
        }
        return try address.toStrKey()
    }

    /// Avant le tap : coffre non vide (sinon `nothingReserved`), NFT de la carte détenu par `pocket` (sinon
    /// `notCardOwner` : la carte ne signe jamais un retrait voué à l'échec), nonce suivant, dernier ledger.
    func prepareClaim(pocket: String, card: ChipPublicKey, curve: ChipCurve) async throws -> PreparedPrizeClaim {
        let source = try await client.account(config.feePayer)
        let amount = try await reserved(for: card, source: source)
        guard amount.units > 0 else { throw PrizeContract.PrizeError.nothingReserved }
        let nfc = try await nfcContract(source: source)
        let nft = NfcNftClient(client: client, defaultContract: nfc, collection: config.contracts.collection)
        let tokenID = try await client.readValue(source: source, contract: nfc, function: "token_id", arguments: [.bytes(card.bytes)])
        guard let tokenID = tokenID.u32 else { throw StellarError.invalidResponse("token_id returned \(tokenID)") }
        guard try await nft.owner(ofToken: tokenID, contract: nfc, source: source) == pocket else {
            throw PrizeContract.PrizeError.notCardOwner
        }
        let stored = try await nonce(for: card, source: source)
        guard stored < UInt32.max else { throw PrizeContract.PrizeError.invalidAttestation }
        let ledger = try await client.latestLedger()
        return PreparedPrizeClaim(
            prize: contract, pocket: pocket, card: card, curve: curve, amount: amount,
            token: try SACClient.contractID(for: Asset(type: AssetType.ASSET_TYPE_NATIVE)!, network: client.network),
            nfcContract: nfc, attestationNonce: stored + 1, pocketNonce: try SorobanAuth.randomNonce(),
            preparedAtLedger: ledger, expirationLedger: ledger + SorobanAuth.expirationLedgers, passphrase: config.passphrase
        )
    }

    /// Juste avant d'ouvrir la session NFC : refus si l'autorisation a moins de 20 ledgers devant elle.
    func checkFresh(_ prepared: PreparedPrizeClaim) async throws {
        try IntegrationCallClient.checkFresh(expirationLedger: prepared.expirationLedger, currentLedger: try await client.latestLedger())
    }

    /// Après le tap : `recovery_id` de l'attestation (simulation de `verify_for_card`, Infineon), l'autorisation de la Pocket
    /// qui va avec, puis la transaction (source = payeur de frais), simulée en mode `enforce` et assemblée (`recovery_id` de
    /// la Pocket cherché par simulation). Puis frais par le serveur de frais, envoi, attente. Renvoie le hash.
    ///
    /// Comme `PaymentClient.submit` : toute erreur est rendue dans un `PaymentFailure` qui porte la trace ; l'autorisation
    /// signée a pu sortir du téléphone, l'issue se vérifie avec `PaymentClient.check`.
    func submit(
        _ prepared: PreparedPrizeClaim,
        signed: CardSignatures,
        feeSigner: FeeSigner,
        onProgress: ((PaymentProgress) -> Void)? = nil
    ) async throws -> String {
        var trace = prepared.trace
        onProgress?(.checking)
        do {
            guard signed.card.publicKey == prepared.card else { throw ChipError.cardNotAccepted(tapped: signed.card.publicKey) }
            let ids = PrizeContract.attestationRecoveryIDs(for: prepared.curve)
            guard signed.signatures.count == 1 + ids.count, let attestation = signed.signatures.first else {
                throw ChipError.malformedResponse("expected \(1 + ids.count) signatures, got \(signed.signatures.count)")
            }
            try PreparedPrizeClaim.checkCurve(attestation, prepared.curve)
            let current = try await client.latestLedger()
            guard current < prepared.expirationLedger else {
                throw IntegrationCallClient.SigningError.authorizationExpiring(expirationLedger: prepared.expirationLedger, currentLedger: current)
            }
            let source = try await client.account(config.feePayer)
            let index = try await attestationIndex(prepared, attestation: attestation, source: source)
            let chipAuth = try PrizeContract.attestation(attestation, recoveryID: ids[index])
            let call = try prepared.call(attestation: chipAuth)
            let declared = try prepared.declaredAuthorization(attestation: chipAuth)
            let transaction = try await AuthorizedCall.assembled(
                client: client, source: source, contract: call.contract, function: call.function, arguments: call.arguments,
                entry: declared.entry, curve: prepared.curve, signature: signed.signatures[1 + index],
                rejectionCodes: RecoveryIDSearch.RejectionCode.pocket, envelope: { $0 }
            )
            trace.transactionMaxTime = transaction.preconditions?.timeBounds?.maxTime
            onProgress?(.sending)
            return try await client.refitAndSubmit(transaction, feeSigner: feeSigner) { onProgress?(.confirming) }
        } catch {
            trace.transactionHash = PaymentClient.sentHash(in: error)
            throw PaymentFailure(trace: trace, underlying: error)
        }
    }

    /// Lequel des `recovery_id` possibles est celui de l'attestation : simulation gratuite de `verify_for_card` (Infineon),
    /// comme `CardPossession`. DUOX : le seul. Aucun ne vérifie : `invalidAttestation`, rien n'est envoyé.
    private func attestationIndex(_ prepared: PreparedPrizeClaim, attestation: ChipSignedDigest, source: Account) async throws -> Int {
        let ids = PrizeContract.attestationRecoveryIDs(for: prepared.curve)
        guard prepared.curve == .secp256k1 else { return 0 }
        let nft = NfcNftClient(client: client, defaultContract: prepared.nfcContract, collection: config.contracts.collection)
        let digest = try prepared.attestationDigest
        for (index, recoveryID) in ids.enumerated() {
            let auth = try PrizeContract.attestation(attestation, recoveryID: recoveryID)
            do {
                if try await nft.verifyForCard(publicKey: prepared.card, digest: digest, auth: auth, contract: prepared.nfcContract, source: source) {
                    return index
                }
            } catch where RecoveryIDSearch.isRejectedSignature(error, contractCodes: nil) {
                continue
            }
        }
        throw PrizeContract.PrizeError.invalidAttestation
    }
}
