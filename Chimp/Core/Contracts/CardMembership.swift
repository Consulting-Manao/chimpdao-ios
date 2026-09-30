import Foundation
import stellarsdk

/// Ajouter une carte à un compte (ARCHITECTURE §3.12), découpé pour l'iPhone en avant / pendant / après chaque tap.
/// Portage de `assertAddable` et `startAddCard` (`modules/card/useCardCeremonies.ts`), `purseAction` et
/// `linkCardToAccount` (`modules/card/ceremonies.ts`), `addCard` (`chain/provisioning.ts`).
///
/// Ordre du terminal, « les pointeurs d'abord à l'entrée » : 1) la **nouvelle carte** signe `pocket.set_owner(compte)`
/// (ordre 1, sa Pocket l'autorise) ; 2) une **carte déjà membre** signe `account.add_card(CardSigner{nouvelle})` (ordre 2,
/// le compte l'autorise, n'importe laquelle de ses cartes). Chaque étape relit la chaîne et se saute si elle est déjà
/// faite : une cérémonie interrompue reprend sans rien refaire (« a failed run resumes instead of duplicating »).
struct CardMembershipClient {
    let client: SorobanClient
    let config: ChimpNetworkConfig

    enum MembershipError: Error, Equatable, LocalizedError {
        /// Pas de Pocket : la carte n'a pas été enregistrée par ChimpDAO (`linkCardToAccount` : « not been set up »).
        case notEnrolled
        /// La carte est déjà dans ce compte, et sa Pocket le nomme : il n'y a rien à faire.
        case alreadyInAccount
        /// La carte est encore membre d'un autre compte : elle doit être **donnée** par son titulaire, pas prise
        /// (`assertAddable` : « That card belongs to another account »).
        case belongsToAnotherAccount(String)

        var errorDescription: String? {
            switch self {
            case .notEnrolled: "This card has not been set up by ChimpDAO yet."
            case .alreadyInAccount: "This card is already on this account."
            case .belongsToAnotherAccount(let account): "That card belongs to another account (\(account))."
            }
        }
    }

    /// Ce que `checkAddable` a établi pour la nouvelle carte.
    struct AddableCard: Equatable, Sendable {
        let state: CardState
        /// Sa Pocket (elle existe : sinon, `notEnrolled`).
        let pocket: String
        /// `purseAction` = « repoint » : la Pocket ne nomme pas encore ce compte, la carte doit signer `set_owner`.
        let needsLink: Bool
        /// Déjà dans `cards()` du compte (cérémonie reprise) : `add_card` sera sauté.
        let isMember: Bool
    }

    private var accounts: ChimpAccountClient { ChimpAccountClient(client: client, config: config) }

    // MARK: Avant le premier tap de la nouvelle carte

    /// `assertAddable` + `readCardState`. Une carte peut entrer si elle est neuve (sa Pocket pointe vers elle-même) ou
    /// orpheline (sa Pocket nomme un compte qui ne la liste plus). Refusée si elle est encore listée par un autre compte.
    /// Les lectures remontent leurs erreurs au lieu de répondre « ajoutable » : une panne réseau ne doit jamais faire
    /// prendre la carte d'un autre compte (« There is no safe default »). Sur une Pocket, `has_card` « trappe » : c'est
    /// une réponse (« pas un compte »), pas une panne.
    func checkAddable(_ key: ChipPublicKey, to account: String) async throws -> AddableCard {
        let source = try await client.account(config.feePayer)
        let state = try await ChainCardResolver.readCardState(
            key, source: try PocketClient.copy(source),
            factory: PocketFactoryClient(client: client, contract: config.contracts.factory),
            nfcNft: NfcNftClient(client: client, defaultContract: config.contracts.nfcNft, collection: config.contracts.collection),
            pocketClient: PocketClient(client: client)
        )
        guard let pocket = state.pocket, let owner = state.pocketOwner else { throw MembershipError.notEnrolled }
        let isMember = try await accounts.hasCard(account: account, publicKey: key, source: try PocketClient.copy(source))
        let needsLink = owner != account
        if isMember {
            guard needsLink else { throw MembershipError.alreadyInAccount }
        } else if needsLink, owner != pocket {
            let listed: Bool
            do {
                listed = try await accounts.hasCard(account: owner, publicKey: key, source: try PocketClient.copy(source))
            } catch let error as StellarError where error.isContractTrap {
                listed = false
            }
            if listed { throw MembershipError.belongsToAnotherAccount(owner) }
        }
        return AddableCard(state: state, pocket: pocket, needsLink: needsLink, isMember: isMember)
    }

    // MARK: set_owner (nouvelle carte, ordre 1)

    /// Avant le tap qui signe : l'entrée `set_owner(compte)` que la Pocket autorise (ledger actuel + 120, nonce aléatoire).
    func declareLink(pocket: String, account: String) async throws -> DeclaredAuthorization {
        try PocketClient.declareSetOwner(
            pocket: pocket, newOwner: account, passphrase: config.passphrase,
            currentLedger: try await client.latestLedger(), nonce: try SorobanAuth.randomNonce()
        )
    }

    /// Après le tap : signature posée, simulation (`recovery_id`), frais par le serveur de frais, envoi. Renvoie le hash.
    func submitLink(_ declared: DeclaredAuthorization, pocket: String, account: String, curve: ChipCurve,
                    signed: ChipSignedDigest, feeSigner: FeeSigner) async throws -> String {
        let prepared = try await PocketClient(client: client).prepareSetOwner(
            declared: declared, pocket: pocket, newOwner: account, curve: curve, signed: signed, feePayer: config.feePayer
        )
        return try await client.refitAndSubmit(prepared.transaction, feeSigner: feeSigner)
    }

    // MARK: add_card (une carte du compte, ordre 2)

    /// Arguments de `add_card(card: CardSigner)` (`scCardSigner(pubBytesFromHex(newPublicKey), newCurve)`).
    static func addCardArguments(publicKey: ChipPublicKey, curve: ChipCurve) -> [SCValXDR] {
        [ChipAuthEncoding.cardSigner(publicKey: publicKey, curve: curve)]
    }

    /// `add_card` prêt pour la carte membre : l'entrée du compte (simulée, vérifiée) et les cartes qui peuvent la signer.
    struct PreparedAddCard {
        let account: String
        let newCard: ChipPublicKey
        let newCurve: ChipCurve
        let authorization: AuthorizedCall.AccountEntry
        /// Cartes du compte (`cards()`), la nouvelle exclue : une carte ne peut pas s'inviter elle-même.
        let acceptedKeys: [ChipPublicKey]

        var digest: Data { authorization.digest }
    }

    /// Avant le tap de la carte membre : `cards()` du compte, puis simulation de `add_card` (ordre 2).
    func prepareAddCard(account: String, newCard: ChipPublicKey, curve: ChipCurve) async throws -> PreparedAddCard {
        let source = try await client.account(config.feePayer)
        let members = try await accounts.cards(account: account, source: try PocketClient.copy(source)).map(\.publicKey)
        let authorization = try await AuthorizedCall.prepareAccountEntry(
            client: client, source: source, account: account, contract: account, function: "add_card",
            arguments: Self.addCardArguments(publicKey: newCard, curve: curve), passphrase: config.passphrase
        )
        return PreparedAddCard(
            account: account, newCard: newCard, newCurve: curve, authorization: authorization,
            acceptedKeys: members.filter { $0 != newCard }
        )
    }

    /// Juste avant le tap : l'autorisation a-t-elle encore 20 ledgers devant elle ? Sinon, la préparer de nouveau.
    func needsRefresh(_ prepared: PreparedAddCard) async throws -> Bool {
        SorobanAuth.needsRefresh(expirationLedger: prepared.authorization.expirationLedger, currentLedger: try await client.latestLedger())
    }

    /// Après le tap : `AccountAuth { auth, key: carte membre }` dans l'entrée, simulation (`recovery_id`, refus `#301`),
    /// frais par le serveur de frais, envoi. Renvoie le hash.
    func submitAddCard(_ prepared: PreparedAddCard, signed: CardSignatures, feeSigner: FeeSigner) async throws -> String {
        guard prepared.acceptedKeys.contains(signed.card.publicKey) else {
            throw ChipError.cardNotAccepted(tapped: signed.card.publicKey)
        }
        guard signed.signatures.count == 1, let signature = signed.signatures.first else {
            throw ChipError.malformedResponse("expected 1 signature, got \(signed.signatures.count)")
        }
        let transaction = try await AuthorizedCall.assembled(
            client: client, source: try await client.account(config.feePayer),
            contract: prepared.account, function: "add_card",
            arguments: Self.addCardArguments(publicKey: prepared.newCard, curve: prepared.newCurve),
            entry: prepared.authorization.entry, curve: signed.card.curve, signature: signature,
            rejectionCode: RecoveryIDSearch.RejectionCode.account,
            envelope: { ChipAuthEncoding.accountAuth(publicKey: signed.card.publicKey, chipAuth: $0) }
        )
        return try await client.refitAndSubmit(transaction, feeSigner: feeSigner)
    }

    // MARK: Relectures

    func pocketOwner(_ pocket: String) async throws -> String {
        try await PocketClient(client: client).owner(of: pocket, source: try await client.account(config.feePayer))
    }

    func hasCard(account: String, publicKey: ChipPublicKey) async throws -> Bool {
        try await accounts.hasCard(account: account, publicKey: publicKey, source: try await client.account(config.feePayer))
    }
}
