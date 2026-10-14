import Foundation
import stellarsdk

/// Un appel de contrat autorisé par une carte, découpé pour l'iPhone en **avant le tap** (réseau, règle 9) et **après le
/// tap** (signature posée, simulation, `recovery_id`). Brique commune au paiement (`PaymentClient`) et aux cérémonies des
/// cartes (`add_card`, `CardMembershipClient`) : portage de `accountSignedCall` (`provisioning.ts`, ordre 2) et de la
/// fin de `purseSignedCallOn` (`purse-call.ts`, ordre 1). Extrait de `PaymentClient` sans changer son comportement.
enum AuthorizedCall {
    enum CallError: Error, Equatable, LocalizedError {
        /// La simulation n'a rendu aucune autorisation (`simulation missing auth for …`).
        case missingAuthorization(function: String)
        /// La simulation a rendu autre chose qu'une seule autorisation.
        case unexpectedAuthorization(String)
        /// L'arbre rendu par la simulation n'est pas l'arbre attendu (`AuthTreeCheck`).
        case treeMismatch(AuthTreeCheck.Mismatch)

        var errorDescription: String? {
            switch self {
            case .missingAuthorization(let function): "The simulation returned no authorization for \(function)."
            case .unexpectedAuthorization(let detail): "Unexpected authorization from the simulation: \(detail)"
            case .treeMismatch(let mismatch): "Unexpected authorization from the simulation: \(mismatch)"
            }
        }
    }

    /// Ordre 2, avant le tap : l'entrée du compte rendue par la simulation, prête pour la carte.
    struct AccountEntry {
        /// Expiration posée, signature vide.
        let entry: SorobanAuthorizationEntryXDR
        /// Les 32 octets que la carte signera.
        let digest: Data
        let expirationLedger: UInt32
        /// Ledger de la simulation : l'autorisation n'a pas pu servir avant.
        let simulatedLedger: UInt32
    }

    /// Ordre 2 (« simuler, puis signer »), avant le tap : simulation de l'appel (mode « recording »), puis l'entrée de
    /// `account`, expiration = ledger de la simulation + 120 (`sim.latestLedger + AUTH_EXPIRATION_LEDGERS`), digest dans la
    /// variante reçue (`SorobanAuth.pendingEntries`, règle 4).
    ///
    /// Défense en profondeur, absente du terminal : l'entrée rendue doit être **exactement** l'arbre attendu, et la seule à
    /// signer ; sinon rien n'est signé. Un serveur RPC malveillant ne peut pas faire signer à la carte autre chose que ce qui
    /// est affiché (règle 8). Arbre attendu par défaut : l'appel demandé, sans sous-appel (paiement, `add_card`,
    /// `remove_card`). Une intégration passe l'arbre déclaré par son adaptateur (`expectedInvocation`, DESIGN_NOTES §13).
    static func prepareAccountEntry(
        client: SorobanClient,
        source: Account,
        account: String,
        contract: String,
        function: String,
        arguments: [SCValXDR],
        passphrase: String,
        expectedInvocation: SorobanAuthorizedInvocationXDR? = nil
    ) async throws -> AccountEntry {
        let transaction = try client.contractCall(
            source: try PocketClient.copy(source), contract: contract, function: function, arguments: arguments
        )
        let simulation = try await client.simulate(transaction)
        guard let entries = simulation.sorobanAuth, !entries.isEmpty else { throw CallError.missingAuthorization(function: function) }
        let simulatedLedger = UInt32(clamping: simulation.latestLedger)
        let expiration = simulatedLedger + SorobanAuth.expirationLedgers
        let expected = try expectedInvocation
            ?? SorobanAuth.contractInvocation(contract: contract, function: function, arguments: arguments)
        let only = try checkedAccountEntry(
            entries, account: account, expected: expected, passphrase: passphrase, expirationLedger: expiration
        )
        return AccountEntry(entry: only.entry, digest: only.digest, expirationLedger: expiration, simulatedLedger: simulatedLedger)
    }

    /// Ordre 2, sans réseau : parmi les entrées rendues par la simulation, la seule à signer pour `account`, vérifiée contre
    /// l'arbre attendu (`AuthTreeCheck`), expiration posée et digest calculé dans la variante reçue (règle 4).
    /// Refus si une entrée nomme une autre adresse, s'il y a plus d'une entrée, ou si l'arbre diffère d'un seul octet.
    static func checkedAccountEntry(
        _ entries: [SorobanAuthorizationEntryXDR],
        account: String,
        expected: SorobanAuthorizedInvocationXDR,
        passphrase: String,
        expirationLedger: UInt32
    ) throws -> SorobanAuth.PendingEntry {
        let pending = try SorobanAuth.pendingEntries(entries, signer: account, passphrase: passphrase, expirationLedger: expirationLedger)
        guard pending.count == 1, let only = pending.first else {
            throw CallError.unexpectedAuthorization("\(pending.count) entries to sign")
        }
        if let mismatch = AuthTreeCheck.mismatch(only.entry.rootInvocation, expected: expected) {
            throw CallError.treeMismatch(mismatch)
        }
        return only
    }

    /// Après le tap : la signature de la carte va dans l'entrée (`envelope` : `ChipAuth` tel quel pour une Pocket,
    /// `AccountAuth { auth, key }` pour un compte), une transaction neuve (source = payeur de frais) porte l'entrée signée,
    /// elle est simulée (`enforce`) et assemblée (`prepareTransaction`). Infineon : `recovery_id` cherché par simulation
    /// (refus = `rejectionCode`, `#201` Pocket, `#301` compte). Rien n'est envoyé : suivre avec `refitAndSubmit`.
    static func assembled(
        client: SorobanClient,
        source: Account,
        contract: String,
        function: String,
        arguments: [SCValXDR],
        entry: SorobanAuthorizationEntryXDR,
        curve: ChipCurve,
        signature: ChipSignedDigest,
        rejectionCode: Int,
        envelope: @escaping (SCValXDR) -> SCValXDR
    ) async throws -> Transaction {
        let build = { (chipAuth: SCValXDR) async throws -> Transaction in
            let signed = try SorobanAuth.restamped(entry, signature: envelope(chipAuth))
            let transaction = try client.contractCall(
                source: try PocketClient.copy(source), contract: contract, function: function,
                arguments: arguments, auth: [signed]
            )
            // Une entrée signée est jointe : le RPC simule en mode `enforce` (`prepareTransaction` du terminal).
            try client.assemble(transaction, with: try await client.simulate(transaction))
            return transaction
        }
        switch (curve, signature) {
        case (.secp256k1, .secp256k1(let bytes)):
            return try await RecoveryIDSearch.first(rejectionCode: rejectionCode) { recoveryID in
                try await build(try ChipAuthEncoding.chipAuthSecp256k1(signature: bytes, recoveryID: recoveryID))
            }.result
        case (.p256, .p256(let bytes, let rndB)):
            return try await build(try ChipAuthEncoding.chipAuthSecp256r1(signature: bytes, rndB: rndB))
        default:
            throw ChipError.malformedResponse("the signature doesn't match the card's curve")
        }
    }
}
