import Foundation
import stellarsdk

/// Un appel d'intégration (swap, dépôt, retrait, lot du router) autorisé par une carte : portage de `earnSignedCall`
/// (`reference/terminal/src/chain/earn-call.ts`), découpé pour l'iPhone en **avant le tap** (réseau, règle 9) et **après
/// le tap** (signature posée, simulation, frais, envoi), comme le paiement (`PaymentClient`).
///
/// Deux ordres, choisis par qui signe (règle 3) :
/// - **Main account, ordre 2** : la simulation rend l'entrée du compte, qui doit être **exactement** l'arbre déclaré par
///   l'adaptateur (`AuthorizedCall.prepareAccountEntry`, plus strict que le terminal, DESIGN_NOTES §13).
/// - **Pocket, ordre 1** : l'arbre déclaré par l'adaptateur devient l'entrée, signée avant toute simulation (CAP-85).
///
/// Écart assumé avec le terminal : un seul autorisateur par appel. Un lot avec cosignataire (déplacer une position entre
/// une Pocket et le Main account) n'est pas pris en charge ici : il demanderait plusieurs entrées et plusieurs
/// `recovery_id` cherchés par simulation (pas de bibliothèque secp256k1 dans l'app). Aucun livrable de la tranche 2 n'en a
/// besoin ; un swap puis un dépôt passent par un lot du router sous un seul autorisateur.
struct IntegrationCallClient {
    let client: SorobanClient
    let config: ChimpNetworkConfig

    enum SigningError: Error, Equatable, LocalizedError {
        /// L'autorisation expire dans moins de 20 ledgers (~2 min), ou a déjà expiré : à préparer de nouveau, rien n'est signé
        /// ni envoyé (`EXPIRATION_MARGIN_LEDGERS`).
        case authorizationExpiring(expirationLedger: UInt32, currentLedger: UInt32)
        /// Plus d'un arbre à signer (lot avec cosignataire) : pas pris en charge.
        case cosignersNotSupported

        var errorDescription: String? {
            switch self {
            case .authorizationExpiring(let expiration, let current):
                "The authorization expires at ledger \(expiration) (now \(current)): prepare it again before signing."
            case .cosignersNotSupported: "A call signed by more than one balance isn't supported."
            }
        }
    }

    // MARK: Avant le tap

    /// L'arbre que `authorizer` signe pour `call` (un lot du router si `legs` est donné), déclaré par la forme de
    /// l'adaptateur. Refus avant tout réseau si la forme ne revendique pas l'appel.
    static func declaredInvocation(
        call: ContractCall,
        legs: [ContractCall]? = nil,
        authorizer: CallAuthorizer,
        shape: any AuthShape
    ) throws -> SorobanAuthorizedInvocationXDR {
        let declared = try DeclaredInvocations.build(root: call, legs: legs, authorizers: [authorizer], shape: shape)
        guard declared.count == 1, let only = declared.first else { throw SigningError.cosignersNotSupported }
        return only.invocation
    }

    /// Prépare l'autorisation de `call`. Main account : simulation, entrée vérifiée contre l'arbre déclaré, expiration =
    /// ledger de la simulation + 120. Pocket : entrée déclarée, nonce aléatoire, expiration = dernier ledger + 120.
    /// `acceptedKeys` : les cartes qui peuvent signer (toutes celles du compte, ou la seule carte de la Pocket).
    func prepare(
        call: ContractCall,
        legs: [ContractCall]? = nil,
        authorizer: CallAuthorizer,
        shape: any AuthShape,
        acceptedKeys: [ChipPublicKey]
    ) async throws -> PreparedIntegrationCall {
        let invocation = try Self.declaredInvocation(call: call, legs: legs, authorizer: authorizer, shape: shape)
        switch authorizer {
        case .account(let account):
            let prepared = try await AuthorizedCall.prepareAccountEntry(
                client: client, source: try await client.account(config.feePayer), account: account,
                contract: call.contract, function: call.function, arguments: call.arguments,
                passphrase: config.passphrase, expectedInvocation: invocation
            )
            return PreparedIntegrationCall(
                authorizer: authorizer, call: call, entry: prepared.entry, digest: prepared.digest,
                expirationLedger: prepared.expirationLedger, preparedAtLedger: prepared.simulatedLedger, acceptedKeys: acceptedKeys
            )
        case .pocket(let pocket):
            return try Self.declaredPocketCall(
                call, pocket: pocket, invocation: invocation, passphrase: config.passphrase,
                currentLedger: try await client.latestLedger(), nonce: try SorobanAuth.randomNonce(), acceptedKeys: acceptedKeys
            )
        }
    }

    /// Ordre 1, sans réseau : l'entrée déclarée par la Pocket (`build` de `preSignedAuthEntries`, credentials V1),
    /// expiration = `currentLedger` + 120, et le digest que la puce signera.
    static func declaredPocketCall(
        _ call: ContractCall,
        pocket: String,
        invocation: SorobanAuthorizedInvocationXDR,
        passphrase: String,
        currentLedger: UInt32,
        nonce: Int64,
        acceptedKeys: [ChipPublicKey]
    ) throws -> PreparedIntegrationCall {
        let declared = try DeclaredAuthorization(
            authorizer: pocket, invocation: invocation, passphrase: passphrase,
            expirationLedger: currentLedger + SorobanAuth.expirationLedgers, nonce: nonce
        )
        return PreparedIntegrationCall(
            authorizer: .pocket(pocket), call: call, entry: declared.entry, digest: declared.digest,
            expirationLedger: declared.expirationLedger, preparedAtLedger: currentLedger, acceptedKeys: acceptedKeys
        )
    }

    /// Juste avant d'ouvrir la session NFC : refus si l'autorisation a moins de 20 ledgers devant elle.
    static func checkFresh(expirationLedger: UInt32, currentLedger: UInt32) throws {
        if SorobanAuth.needsRefresh(expirationLedger: expirationLedger, currentLedger: currentLedger) {
            throw SigningError.authorizationExpiring(expirationLedger: expirationLedger, currentLedger: currentLedger)
        }
    }

    func checkFresh(_ prepared: PreparedIntegrationCall) async throws {
        try Self.checkFresh(expirationLedger: prepared.expirationLedger, currentLedger: try await client.latestLedger())
    }

    // MARK: Après le tap

    /// Met la signature de la carte dans l'entrée (`ChipAuth` pour une Pocket, `AccountAuth` pour le Main account),
    /// construit la transaction (source = payeur de frais), la simule et l'assemble ; Infineon : `recovery_id` cherché par
    /// simulation (`#201` Pocket, `#301` compte). Puis frais par le serveur de frais, envoi, attente. Renvoie le hash.
    /// Refus si la carte n'est pas acceptée ou si l'autorisation a déjà expiré.
    ///
    /// Comme `PaymentClient.submit` : toute erreur est rendue dans un `PaymentFailure` qui porte `trace` (complétée de la
    /// limite de temps et du hash de la transaction) ; l'entrée signée a pu sortir du téléphone, l'issue se vérifie avec
    /// `PaymentClient.check` (le nonce de l'entrée identifie notre autorisation dans n'importe quelle transaction).
    func submit(
        _ prepared: PreparedIntegrationCall,
        signed: CardSignatures,
        trace: PaymentTrace,
        feeSigner: FeeSigner,
        onProgress: ((PaymentProgress) -> Void)? = nil
    ) async throws -> String {
        var trace = trace
        do {
            return try await sendSigned(prepared, signed: signed, feeSigner: feeSigner, onProgress: onProgress) { maxTime in
                trace.transactionMaxTime = maxTime
            }
        } catch {
            trace.transactionHash = PaymentClient.sentHash(in: error)
            throw PaymentFailure(trace: trace, underlying: error)
        }
    }

    /// Le cœur de `submit`, sans trace de paiement : carte acceptée, une signature, autorisation pas expirée, transaction
    /// assemblée (`recovery_id` cherché par simulation), frais, envoi, attente. Les erreurs remontent telles quelles.
    /// Sert aussi aux mises à jour du code (`ContractUpdateClient`), qui se vérifient en relisant le contrat.
    func sendSigned(
        _ prepared: PreparedIntegrationCall,
        signed: CardSignatures,
        feeSigner: FeeSigner,
        onProgress: ((PaymentProgress) -> Void)? = nil,
        onAssembled: (UInt64?) -> Void = { _ in }
    ) async throws -> String {
        onProgress?(.checking)
        guard prepared.acceptedKeys.contains(signed.card.publicKey) else {
            throw ChipError.cardNotAccepted(tapped: signed.card.publicKey)
        }
        guard signed.signatures.count == 1, let signature = signed.signatures.first else {
            throw ChipError.malformedResponse("expected 1 signature, got \(signed.signatures.count)")
        }
        let current = try await client.latestLedger()
        guard current < prepared.expirationLedger else {
            throw SigningError.authorizationExpiring(expirationLedger: prepared.expirationLedger, currentLedger: current)
        }
        let transaction = try await AuthorizedCall.assembled(
            client: client, source: try await client.account(config.feePayer),
            contract: prepared.call.contract, function: prepared.call.function, arguments: prepared.call.arguments,
            entry: prepared.entry, curve: signed.card.curve, signature: signature, rejectionCodes: prepared.rejectionCodes,
            envelope: { prepared.envelope($0, card: signed.card.publicKey) }
        )
        onAssembled(transaction.preconditions?.timeBounds?.maxTime)
        onProgress?(.sending)
        return try await client.refitAndSubmit(transaction, feeSigner: feeSigner) { onProgress?(.confirming) }
    }
}

/// Ce qui est prêt avant le tap : l'appel, l'entrée à faire signer, son digest, et les cartes qui peuvent la signer.
struct PreparedIntegrationCall {
    let authorizer: CallAuthorizer
    /// L'appel racine (simple, ou `batch` du router).
    let call: ContractCall
    /// Entrée à signer : expiration posée, signature vide.
    let entry: SorobanAuthorizationEntryXDR
    /// Les 32 octets que la carte signera.
    let digest: Data
    let expirationLedger: UInt32
    /// Ledger connu à la préparation : l'autorisation n'a pas pu servir avant.
    let preparedAtLedger: UInt32
    /// Clés des cartes qui peuvent signer, vérifiées **avant** tout PIN.
    let acceptedKeys: [ChipPublicKey]

    /// Codes d'erreur du contrat quand le `recovery_id` essayé n'est pas le bon.
    var rejectionCodes: Set<Int> {
        authorizer.isPocket ? RecoveryIDSearch.RejectionCode.pocket : RecoveryIDSearch.RejectionCode.account
    }

    /// La signature placée dans l'entrée : `ChipAuth` tel quel pour une Pocket, `AccountAuth { auth, key }` pour un compte.
    func envelope(_ chipAuth: SCValXDR, card: ChipPublicKey) -> SCValXDR {
        authorizer.isPocket ? chipAuth : ChipAuthEncoding.accountAuth(publicKey: card, chipAuth: chipAuth)
    }

    var nonce: Int64 {
        (try? SorobanAuth.addressCredentials(entry))?.nonce ?? 0
    }

    /// La trace de « Check again » : `token` est l'actif que l'autorisateur fait partir (ses `transfer` sont relus pour
    /// trouver notre nonce), `destination` et `units` ce qui part, pour l'affichage.
    func trace(token: String, destination: String, units: UInt64) -> PaymentTrace {
        PaymentTrace(
            token: token, from: authorizer.address, destination: destination, units: units, nonce: nonce,
            preparedAtLedger: preparedAtLedger, expirationLedger: expirationLedger
        )
    }
}
