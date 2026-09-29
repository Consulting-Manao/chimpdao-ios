import Foundation
import stellarsdk

/// Un paiement signé par une carte : `SAC.transfer(from, to, montant)`, frais payés par ChimpDAO.
/// Portage de `payFromChipAccount` / `paySmartAccount` (`reference/terminal/src/chain/stellar.ts`), découpé en trois
/// temps pour l'iPhone : **avant le tap** (réseau, règle 9), **le tap** (fait par l'appelant avec `ChipSigner`),
/// **après le tap** (simulation, frais, envoi).
///
/// Deux ordres (ARCHITECTURE §3.3, règle 3) :
/// - **Main account, ordre 2** « simuler puis signer » : la simulation découvre l'entrée d'autorisation du compte,
///   n'importe quelle carte du compte la signe, enveloppée dans `AccountAuth`.
/// - **Wallet d'une carte (Pocket), ordre 1** « signer puis simuler » : l'entrée est déclarée sans simulation (une
///   simulation « recording » échoue sur une Pocket `Managed`, CAP-85), seule la carte de cette Pocket la signe.
///
/// Adaptation à l'iPhone (DESIGN_NOTES §13) : en ordre 2, la transaction simulée avant le tap n'est pas gardée. Après le
/// tap, une transaction neuve (séquence fraîche, 60 s de validité) porte l'entrée signée, exactement comme en ordre 1.
/// La carte ne signe que l'entrée (réseau, nonce, expiration, appel), jamais l'enveloppe : rien n'est à refaire signer.
struct PaymentClient {
    let client: SorobanClient
    let config: ChimpNetworkConfig

    /// Durée estimée d'un ledger, pour afficher l'heure d'expiration d'une autorisation. Volontairement un peu longue
    /// (testnet ferme un ledger toutes les ~5 s) : l'heure annoncée arrive rarement trop tôt, et on revérifie de toute façon.
    static let estimatedLedgerSeconds: TimeInterval = 6

    enum PaymentError: Error, Equatable, LocalizedError {
        /// Solde insuffisant (`Insufficient XLM`). Rien n'est signé.
        case insufficientBalance(held: Decimal)
        /// Solde illisible : on ne dépense jamais sur un solde inconnu (« fail-closed »).
        case balanceUnknown
        /// La simulation n'a rendu aucune autorisation (`simulation missing auth for … transfer`).
        case missingAuthorization
        /// La simulation a rendu autre chose qu'une seule autorisation, ou une autre opération que celle demandée.
        case unexpectedAuthorization(String)

        var errorDescription: String? {
            switch self {
            case .insufficientBalance(let held): "Insufficient balance (\(held) units held)."
            case .balanceUnknown: "The balance couldn't be read, so nothing was signed."
            case .missingAuthorization: "The simulation returned no authorization for the transfer."
            case .unexpectedAuthorization(let detail): "Unexpected authorization from the simulation: \(detail)"
            }
        }
    }

    // MARK: Avant le tap

    /// Main account (ordre 2) : solde (refus s'il est insuffisant ou illisible), cartes du compte, puis simulation du
    /// transfert, qui rend l'entrée d'autorisation du compte. Expiration = ledger de la simulation + 120 (`sim.latestLedger
    /// + AUTH_EXPIRATION_LEDGERS`), digest calculé sur la variante reçue.
    ///
    /// Défense en profondeur, absente du terminal : l'entrée rendue doit être **exactement** l'appel demandé (même
    /// contrat, `transfer`, mêmes arguments, aucun sous-appel), sinon rien n'est signé. Sans cela, un serveur RPC
    /// malveillant pourrait faire signer à la carte un autre transfert que celui affiché (règle 8).
    func prepareFromAccount(account: String, token: String, destination: String, units: UInt64) async throws -> PreparedPayment {
        let source = try await client.account(config.feePayer)
        async let heldRead = SACClient(client: client).balance(token: token, holder: account, source: try PocketClient.copy(source))
        async let cardsRead = ChimpAccountClient(client: client, config: config).cards(account: account, source: try PocketClient.copy(source))
        try Self.checkBalance(try await heldRead, units: units)
        let cards = try await cardsRead

        let arguments = try SACClient.transferArguments(from: account, to: destination, units: units)
        let transaction = try client.contractCall(source: try PocketClient.copy(source), contract: token, function: "transfer", arguments: arguments)
        let simulation = try await client.simulate(transaction)
        guard let entries = simulation.sorobanAuth, !entries.isEmpty else { throw PaymentError.missingAuthorization }
        let simulatedLedger = UInt32(clamping: simulation.latestLedger)
        let expiration = simulatedLedger + SorobanAuth.expirationLedgers
        let pending = try SorobanAuth.pendingEntries(entries, signer: account, passphrase: config.passphrase, expirationLedger: expiration)
        guard pending.count == 1, let only = pending.first else {
            throw PaymentError.unexpectedAuthorization("\(pending.count) entries to sign")
        }
        let expected = try SorobanAuth.contractInvocation(contract: token, function: "transfer", arguments: arguments)
        guard try XDREncoder.encode(only.entry.rootInvocation) == XDREncoder.encode(expected) else {
            throw PaymentError.unexpectedAuthorization("the authorized call is not the requested transfer")
        }
        return PreparedPayment(
            authorizer: .account(account), token: token, destination: destination, units: units,
            entry: only.entry, digest: only.digest, expirationLedger: expiration,
            preparedAtLedger: simulatedLedger, acceptedKeys: cards.map(\.publicKey)
        )
    }

    /// Wallet d'une carte (ordre 1) : solde (refus s'il est insuffisant ou illisible), dernier ledger, puis entrée
    /// `transfer` déclarée par la Pocket (`purseSignedCallOn` → `preSignedAuthEntry`). Seule `card` peut la signer.
    func prepareFromPocket(pocket: String, card: ChipPublicKey, token: String, destination: String, units: UInt64) async throws -> PreparedPayment {
        let source = try await client.account(config.feePayer)
        try Self.checkBalance(try await SACClient(client: client).balance(token: token, holder: pocket, source: source), units: units)
        let ledger = try await client.latestLedger()
        let declared = try SACClient.declareTransfer(
            token: token, pocket: pocket, to: destination, units: units,
            passphrase: config.passphrase, currentLedger: ledger, nonce: try SorobanAuth.randomNonce()
        )
        return PreparedPayment(
            authorizer: .pocket(pocket), token: token, destination: destination, units: units,
            entry: declared.entry, digest: declared.digest, expirationLedger: declared.expirationLedger,
            preparedAtLedger: ledger, acceptedKeys: [card]
        )
    }

    /// Juste avant d'ouvrir la session NFC : l'autorisation a-t-elle encore au moins 20 ledgers devant elle
    /// (`EXPIRATION_MARGIN_LEDGERS`) ? Sinon, il faut la préparer de nouveau (nouveau digest).
    func needsRefresh(_ prepared: PreparedPayment) async throws -> Bool {
        SorobanAuth.needsRefresh(expirationLedger: prepared.expirationLedger, currentLedger: try await client.latestLedger())
    }

    /// `if (held == null || held < amount) throw new Error("Insufficient …")`.
    static func checkBalance(_ held: Decimal?, units: UInt64) throws {
        guard let held else { throw PaymentError.balanceUnknown }
        guard held >= Decimal(units) else { throw PaymentError.insufficientBalance(held: held) }
    }

    // MARK: Après le tap

    /// Met la signature de la carte dans l'entrée (`ChipAuth` pour une Pocket, `AccountAuth` pour le Main account),
    /// construit la transaction (source = payeur de frais), la simule et l'assemble ; Infineon : `recovery_id` cherché
    /// par simulation (refus = `#201` Pocket, `#301` compte). Puis `refitAndSubmit` : frais par le serveur de frais,
    /// envoi, attente. Renvoie le hash.
    ///
    /// Toute erreur est rendue dans un `PaymentFailure` qui porte la trace de l'envoi : l'entrée signée est sortie du
    /// téléphone (simulation, serveur de frais), il faudra `check` pour savoir ce qu'il est devenu.
    func submit(_ prepared: PreparedPayment, signed: CardSignatures, feeSigner: FeeSigner) async throws -> String {
        var trace = prepared.trace
        do {
            guard prepared.acceptedKeys.contains(signed.card.publicKey) else {
                throw ChipError.cardNotAccepted(tapped: signed.card.publicKey)
            }
            guard signed.signatures.count == 1, let signature = signed.signatures.first else {
                throw ChipError.malformedResponse("expected 1 signature, got \(signed.signatures.count)")
            }
            let source = try await client.account(config.feePayer)
            let arguments = try SACClient.transferArguments(from: prepared.from, to: prepared.destination, units: prepared.units)
            let build = { (chipAuth: SCValXDR) async throws -> Transaction in
                let entry = try SorobanAuth.restamped(prepared.entry, signature: prepared.envelope(chipAuth, card: signed.card.publicKey))
                let transaction = try client.contractCall(
                    source: try PocketClient.copy(source), contract: prepared.token, function: "transfer",
                    arguments: arguments, auth: [entry]
                )
                // Une entrée signée est jointe : le RPC simule en mode `enforce` (`prepareTransaction` du terminal).
                try client.assemble(transaction, with: try await client.simulate(transaction))
                return transaction
            }
            let transaction: Transaction
            switch (signed.card.curve, signature) {
            case (.secp256k1, .secp256k1(let bytes)):
                transaction = try await RecoveryIDSearch.first(rejectionCode: prepared.rejectionCode) { recoveryID in
                    try await build(try ChipAuthEncoding.chipAuthSecp256k1(signature: bytes, recoveryID: recoveryID))
                }.result
            case (.p256, .p256(let bytes, let rndB)):
                transaction = try await build(try ChipAuthEncoding.chipAuthSecp256r1(signature: bytes, rndB: rndB))
            default:
                throw ChipError.malformedResponse("the signature doesn't match the card's curve")
            }
            trace.transactionMaxTime = transaction.preconditions?.timeBounds?.maxTime
            return try await client.refitAndSubmit(transaction, feeSigner: feeSigner)
        } catch {
            trace.transactionHash = Self.sentHash(in: error)
            throw PaymentFailure(trace: trace, underlying: error)
        }
    }

    /// Hash d'une transaction peut-être partie, porté par l'erreur. `submitFailed` (refusée à l'envoi) n'en a pas besoin :
    /// cette transaction-là ne sera jamais incluse.
    static func sentHash(in error: Error) -> String? {
        switch error {
        case StellarError.notConfirmed(let hash), StellarError.sendUnanswered(let hash, _), StellarError.transactionFailed(let hash, _):
            hash
        default:
            nil
        }
    }

    // MARK: « Check again »

    /// Que sait-on de ce paiement ? Décision de Barth (2026-09-29, DESIGN_NOTES §12) :
    /// 1. notre transaction est confirmée → `sent` ;
    /// 2. elle peut encore être incluse (le dernier ledger lu par le RPC a fermé avant sa limite de 60 s) → `pending` ;
    /// 3. elle ne passera plus, mais l'autorisation signée reste valable jusqu'à son ledger d'expiration : n'importe qui
    ///    l'ayant vue (RPC, serveur de frais) pourrait encore la soumettre dans une autre transaction → `waiting` ;
    /// 4. le ledger d'expiration est fermé : on cherche **notre autorisation** (son nonce) dans toutes les transactions
    ///    qui ont fait bouger de l'argent depuis `from` entre la préparation et l'expiration. Trouvée → `sent` avec cette
    ///    transaction ; absente et historique complet → `nothingSent` (certain) ; historique incomplet → `undetermined`.
    func check(_ trace: PaymentTrace) async throws -> PaymentCheck {
        try await Self.check(trace, ledger: client)
    }

    static func check(_ trace: PaymentTrace, ledger: some PaymentLedger) async throws -> PaymentCheck {
        let latest: (sequence: UInt32, closeTime: UInt64)
        if let hash = trace.transactionHash {
            let lookup = try await ledger.lookUpTransaction(hash)
            if lookup.status == .success { return .sent(hash: hash) }
            if lookup.status == .notFound, lookup.latestLedgerCloseTime <= trace.transactionMaxTime ?? .max {
                return .pending
            }
            latest = (lookup.latestLedger, lookup.latestLedgerCloseTime)
        } else {
            latest = try await ledger.latestLedgerInfo()
        }
        if latest.sequence <= trace.expirationLedger {
            return .waiting(
                untilLedger: trace.expirationLedger,
                estimatedEnd: estimatedClose(of: trace.expirationLedger + 1, latest: latest)
            )
        }
        let scan = try await ledger.eventTransactions(
            contract: trace.token,
            topics: try transferTopics(from: trace.from),
            startLedger: trace.preparedAtLedger,
            endLedger: trace.expirationLedger
        )
        guard let oldest = scan.oldestLedger, oldest <= trace.preparedAtLedger, scan.latestLedger > trace.expirationLedger else {
            return .undetermined("Stellar RPC no longer keeps ledgers \(trace.preparedAtLedger) to \(trace.expirationLedger)")
        }
        for hash in scan.transactionHashes {
            guard let envelope = try await ledger.transactionEnvelope(hash) else {
                return .undetermined("transaction \(hash) is not readable")
            }
            if try self.envelope(envelope, contains: trace.nonce, from: trace.from) { return .sent(hash: hash) }
        }
        return .nothingSent
    }

    /// Heure estimée de fermeture d'un ledger, à partir du dernier ledger fermé.
    static func estimatedClose(of ledger: UInt32, latest: (sequence: UInt32, closeTime: UInt64)) -> Date {
        let ledgersLeft = ledger > latest.sequence ? Double(ledger - latest.sequence) : 0
        return Date(timeIntervalSince1970: TimeInterval(latest.closeTime) + ledgersLeft * estimatedLedgerSeconds)
    }

    /// Sujets d'un événement `transfer` d'un SAC dont l'expéditeur est `from` (`["transfer", from, to, actif]`,
    /// comme les filtres de `backfillChainHistory`) : XDR base64, `*` pour « n'importe lequel ».
    static func transferTopics(from: String) throws -> [String] {
        guard let name = SCValXDR.symbol("transfer").xdrEncoded,
              let sender = SCValXDR.address(try SACClient.address(from)).xdrEncoded else {
            throw StellarError.invalidResponse("could not encode the transfer topics")
        }
        return [name, sender, "*", "*"]
    }

    /// L'enveloppe (base64, simple ou « fee bump ») contient-elle une entrée d'autorisation de `from` avec ce nonce ?
    /// Un nonce ne sert qu'une fois par adresse : c'est la signature de notre carte qui a été utilisée.
    static func envelope(_ base64: String, contains nonce: Int64, from: String) throws -> Bool {
        let operations: [OperationXDR] = switch try TransactionEnvelopeXDR(fromBase64: base64) {
        case .v0(let envelope): envelope.tx.operations
        case .v1(let envelope): envelope.tx.operations
        case .feeBump(let envelope):
            switch envelope.tx.innerTx {
            case .v1(let inner): inner.tx.operations
            }
        }
        for operation in operations {
            guard case .invokeHostFunctionOp(let invoke) = operation.body else { continue }
            for entry in invoke.auth {
                guard let credentials = try? SorobanAuth.addressCredentials(entry) else { continue }
                if credentials.nonce == nonce, try credentials.address.toStrKey() == from { return true }
            }
        }
        return false
    }
}

/// Lectures dont « Check again » a besoin. `SorobanClient` dans l'app, un faux dans les tests.
protocol PaymentLedger {
    func lookUpTransaction(_ hash: String) async throws -> SorobanClient.TransactionLookup
    func latestLedgerInfo() async throws -> (sequence: UInt32, closeTime: UInt64)
    func eventTransactions(contract: String, topics: [String], startLedger: UInt32, endLedger: UInt32) async throws -> SorobanClient.EventScan
    func transactionEnvelope(_ hash: String) async throws -> String?
}

extension SorobanClient: PaymentLedger {}

/// Ce qui est prêt avant le tap : l'entrée à faire signer, son digest, et les cartes qui peuvent la signer.
struct PreparedPayment {
    enum Authorizer: Equatable {
        /// Main account : `AccountAuth`, n'importe quelle carte du compte.
        case account(String)
        /// Wallet d'une carte : `ChipAuth`, seulement cette carte.
        case pocket(String)
    }

    let authorizer: Authorizer
    /// SAC de l'actif.
    let token: String
    /// Adresse G, M ou C du destinataire.
    let destination: String
    /// Montant en unités on-chain (7 décimales).
    let units: UInt64
    /// Entrée à signer : expiration posée, signature vide.
    let entry: SorobanAuthorizationEntryXDR
    /// Les 32 octets que la carte signera.
    let digest: Data
    let expirationLedger: UInt32
    /// Ledger connu à la préparation : l'autorisation n'a pas pu servir avant.
    let preparedAtLedger: UInt32
    /// Clés des cartes qui peuvent signer, vérifiées **avant** tout PIN.
    let acceptedKeys: [ChipPublicKey]

    var from: String {
        switch authorizer {
        case .account(let address), .pocket(let address): address
        }
    }

    /// Code d'erreur du contrat quand le `recovery_id` essayé n'est pas le bon.
    var rejectionCode: Int {
        switch authorizer {
        case .account: RecoveryIDSearch.RejectionCode.account
        case .pocket: RecoveryIDSearch.RejectionCode.pocket
        }
    }

    /// La signature placée dans l'entrée : `ChipAuth` tel quel pour une Pocket, `AccountAuth { auth, key }` pour un compte.
    func envelope(_ chipAuth: SCValXDR, card: ChipPublicKey) -> SCValXDR {
        switch authorizer {
        case .pocket: chipAuth
        case .account: ChipAuthEncoding.accountAuth(publicKey: card, chipAuth: chipAuth)
        }
    }

    var trace: PaymentTrace {
        let nonce = (try? SorobanAuth.addressCredentials(entry))?.nonce ?? 0
        return PaymentTrace(
            token: token, from: from, destination: destination, units: units, nonce: nonce,
            preparedAtLedger: preparedAtLedger, expirationLedger: expirationLedger
        )
    }
}

/// Ce qu'il faut garder d'un paiement après le tap pour « Check again » : rien de secret (des adresses, un montant,
/// un nonce public et des numéros de ledger).
struct PaymentTrace: Equatable, Sendable {
    let token: String
    let from: String
    let destination: String
    let units: UInt64
    /// Nonce de l'entrée signée : il identifie notre autorisation dans n'importe quelle transaction.
    let nonce: Int64
    let preparedAtLedger: UInt32
    /// Dernier ledger où l'autorisation signée peut encore être utilisée.
    let expirationLedger: UInt32
    /// Hash de notre transaction, si elle a peut-être été envoyée.
    var transactionHash: String?
    /// Limite de temps de notre transaction (secondes depuis 1970) : au-delà, elle ne peut plus être incluse.
    var transactionMaxTime: UInt64?
}

/// Un échec **après** le tap : l'autorisation signée a pu sortir du téléphone. `trace` sert à `PaymentClient.check`.
struct PaymentFailure: Error, LocalizedError {
    let trace: PaymentTrace
    let underlying: Error

    var errorDescription: String? {
        (underlying as? LocalizedError)?.errorDescription ?? "\(underlying)"
    }
}

/// Réponse de « Check again ».
enum PaymentCheck: Equatable {
    /// L'argent est parti, par cette transaction.
    case sent(hash: String)
    /// Notre transaction peut encore être incluse : revérifier dans un instant.
    case pending
    /// Notre transaction ne passera plus, mais l'autorisation signée reste valable jusqu'au ledger `untilLedger` inclus.
    /// « Not sent. Please wait until {heure} before trying again » : aucun renvoi possible avant.
    case waiting(untilLedger: UInt32, estimatedEnd: Date)
    /// Certain : l'autorisation a expiré sans avoir servi.
    case nothingSent
    /// Impossible de trancher (historique du RPC trop court) : vérifier dans l'explorateur.
    case undetermined(String)
}
