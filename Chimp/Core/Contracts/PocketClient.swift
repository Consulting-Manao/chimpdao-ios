import Foundation
import stellarsdk

/// Contrat `pocket` : le wallet d'une carte, qui n'obéit qu'à sa puce (ARCHITECTURE §2.3).
/// Portage de `pocketAccountOf` / `readCardState` (lecture de `owner`) et de `pocketSignedCall` + `purseSignedCallOn`
/// (`reference/terminal/src/chain/provisioning.ts`, `purse-call.ts`) pour `set_owner`.
///
/// **Ordre 1** (§3.3, règle 3) : l'entrée d'autorisation est déclarée et signée par la puce **avant** toute simulation,
/// parce qu'une simulation en mode « recording » échoue sur une Pocket `Managed` depuis le Protocol 28 (CAP-85).
struct PocketClient {
    let client: SorobanClient

    /// `owner()` : le Main account « indiqué » par la Pocket. Juste après l'enregistrement, c'est la Pocket elle-même.
    func owner(of pocket: String, source: Account) async throws -> String {
        let value = try await client.readValue(source: source, contract: pocket, function: "owner")
        guard let address = value.address, case .contract = address else {
            throw StellarError.invalidResponse("pocket owner returned \(value)")
        }
        return try address.toStrKey()
    }

    // MARK: set_owner (ordre 1)

    /// Arguments de `set_owner(new_owner: Address)`.
    static func setOwnerArguments(newOwner: String) throws -> [SCValXDR] {
        [.address(try SCAddressXDR(contractId: newOwner))]
    }

    /// Avant le tap : l'entrée `set_owner` que la Pocket autorise (elle est à la fois le contrat appelé et l'autorisateur),
    /// expiration = ledger actuel + 120, nonce aléatoire. Le `digest` est ce que la puce signera.
    static func declareSetOwner(
        pocket: String,
        newOwner: String,
        passphrase: String,
        currentLedger: UInt32,
        nonce: Int64
    ) throws -> DeclaredAuthorization {
        try DeclaredAuthorization(
            authorizer: pocket,
            invocation: try SorobanAuth.contractInvocation(
                contract: pocket, function: "set_owner", arguments: try setOwnerArguments(newOwner: newOwner)
            ),
            passphrase: passphrase,
            expirationLedger: currentLedger + SorobanAuth.expirationLedgers,
            nonce: nonce
        )
    }

    /// Transaction `set_owner` avec l'entrée signée, source = payeur de frais.
    func setOwnerTransaction(source: Account, pocket: String, newOwner: String, signedEntry: SorobanAuthorizationEntryXDR) throws -> Transaction {
        try client.contractCall(
            source: source, contract: pocket, function: "set_owner",
            arguments: try Self.setOwnerArguments(newOwner: newOwner), auth: [signedEntry]
        )
    }

    /// Après le tap : met la signature de la puce dans l'entrée, puis simule en mode `enforce` et assemble
    /// (`prepareTransaction`). Infineon : `recovery_id` cherché par simulation (0 à 3, refus = `#201`).
    /// Rien n'est envoyé : c'est aussi ce que fait la répétition à blanc.
    func prepareSetOwner(
        declared: DeclaredAuthorization,
        pocket: String,
        newOwner: String,
        curve: ChipCurve,
        signed: ChipSignedDigest,
        feePayer: String,
        onRejected: ((UInt32, Error) -> Void)? = nil
    ) async throws -> (transaction: Transaction, recoveryID: UInt32?) {
        let source = try await client.account(feePayer)
        let build = { (auth: SCValXDR) async throws -> Transaction in
            let entry = try declared.signed(with: auth)
            let transaction = try setOwnerTransaction(source: try Self.copy(source), pocket: pocket, newOwner: newOwner, signedEntry: entry)
            try client.assemble(transaction, with: try await client.simulate(transaction))
            return transaction
        }
        switch (curve, signed) {
        case (.secp256k1, .secp256k1(let signature)):
            let found = try await RecoveryIDSearch.first(rejectionCode: RecoveryIDSearch.RejectionCode.pocket, onRejected: onRejected) { recoveryID in
                try await build(try ChipAuthEncoding.chipAuthSecp256k1(signature: signature, recoveryID: recoveryID))
            }
            return (found.result, found.recoveryID)
        case (.p256, .p256(let signature, let rndB)):
            return (try await build(try ChipAuthEncoding.chipAuthSecp256r1(signature: signature, rndB: rndB)), nil)
        default:
            throw ChipError.malformedResponse("the signature doesn't match the card's curve")
        }
    }

    /// Diagnostic (répétition à blanc) : simule `set_owner` avec un `recovery_id` imposé et renvoie l'erreur obtenue,
    /// ou `nil` si la simulation passe. Sert à voir le texte exact d'un refus quand le premier essai était le bon.
    func setOwnerSimulationError(
        declared: DeclaredAuthorization,
        pocket: String,
        newOwner: String,
        signature: Data,
        recoveryID: UInt32,
        feePayer: String
    ) async throws -> Error? {
        let source = try await client.account(feePayer)
        let entry = try declared.signed(with: try ChipAuthEncoding.chipAuthSecp256k1(signature: signature, recoveryID: recoveryID))
        let transaction = try setOwnerTransaction(source: source, pocket: pocket, newOwner: newOwner, signedEntry: entry)
        do {
            _ = try await client.simulate(transaction)
            return nil
        } catch {
            return error
        }
    }

    /// Copie du compte : `Transaction` incrémente la séquence du compte qu'on lui donne.
    static func copy(_ account: Account) throws -> Account {
        try Account(accountId: account.accountId, sequenceNumber: account.sequenceNumber)
    }
}
