import Foundation
import stellarsdk

/// État d'une carte sur la chaîne (`CardState` de `reference/terminal/src/chain/provisioning.ts`).
struct CardState: Equatable, Sendable {
    /// Pocket déployée, ou `nil` si la carte n'a jamais été enregistrée.
    let pocket: String?
    /// Main account indiqué par la Pocket (`pocket.owner`), ou `nil` sans Pocket. Égal à `pocket` juste après l'enregistrement.
    let pocketOwner: String?
    /// Campagne `nfc-nft` qui connaît la carte, et numéro du NFT, ou `nil`.
    let nftContract: String?
    let tokenID: UInt32?
    /// Propriétaire du NFT (la Pocket), ou `nil`.
    let nftOwner: String?
}

/// Ce qu'une carte tapée se révèle être (`CardResolution` de `reference/terminal/src/chain/resolve.ts`).
enum CardResolution: Equatable, Sendable {
    enum CandidateSource: String, Equatable, Sendable {
        /// Compte mémorisé sur le téléphone pour cette carte.
        case hint
        /// Compte indiqué par la Pocket (`pocket.owner`).
        case pocket
    }

    /// La carte est membre de ce Main account (`has_card` l'a confirmé).
    case signIn(account: String, source: CandidateSource)
    /// Pas de Pocket, rien ne la nomme : **carte non enregistrée**, refusée par le wallet.
    case newCard
    /// Enregistrée et à personne : sa Pocket pointe vers elle-même. Une carte neuve qui rencontre son premier propriétaire.
    case enrolled
    /// Tous les comptes qu'on a pu nommer ont refusé la carte (retirée d'un compte). `lastKnown` sert seulement au texte.
    case orphan(lastKnown: String?)
    /// Au moins une question n'a pas pu être posée (réseau) : **re-taper**, ne jamais conclure « orphelin ».
    case unknown(detail: String)
}

/// Ce que les lectures ont établi (`Evidence` de `resolve.ts`).
struct CardEvidence: Equatable {
    struct Tried: Equatable {
        let account: String
        let source: CardResolution.CandidateSource
        let member: Bool
    }

    /// Comptes interrogés, dans l'ordre, avec la réponse de `has_card`.
    var tried: [Tried] = []
    /// Une recherche de candidat ou une vérification d'appartenance a échoué pour de bon (réseau).
    var failed = false
    /// Pocket de la carte, si elle existe. Une Pocket qui se possède elle-même est la marque de l'enregistrement.
    var ownPocket: String?

    /// `decideResolution` : toute la décision en une fonction pure, testable sans réseau.
    func decide() -> CardResolution {
        if let member = tried.first(where: \.member) {
            return .signIn(account: member.account, source: member.source)
        }
        // Quelqu'un a refusé mais un autre n'a pas pu être interrogé : « orphelin » est destructeur, on fait re-taper.
        if failed { return .unknown(detail: "Couldn't check this card") }
        if let first = tried.first {
            if let ownPocket, first.account == ownPocket { return .enrolled }
            return .orphan(lastKnown: first.account)
        }
        // Rien ne nomme la carte et sa Pocket est absente : carte vierge.
        return .newCard
    }
}

/// Lit l'état d'une carte et décide ce qu'elle est. Implémenté par `ChainCardResolver` (testnet) et `MockCardResolver`.
protocol CardResolving {
    /// `resolveAccountForCard` : `hint` = compte mémorisé sur le téléphone pour cette carte, vérifié en premier.
    func resolve(_ publicKey: ChipPublicKey, hint: String?) async throws -> CardResolution
    /// `readCardState` : tout ce dont l'onboarding a besoin, en une lecture.
    func state(of publicKey: ChipPublicKey) async throws -> CardState
}

/// Lectures sur la chaîne, en simulation (rien n'est signé ni payé). Source des simulations : le payeur de frais,
/// comme `simBuilderFor` du terminal.
struct ChainCardResolver: CardResolving {
    let config: ChimpNetworkConfig
    let client: SorobanClient

    init(config: ChimpNetworkConfig) {
        self.config = config
        client = SorobanClient(config: config)
    }

    private var factory: PocketFactoryClient { PocketFactoryClient(client: client, contract: config.contracts.factory) }
    private var nfcNft: NfcNftClient { NfcNftClient(client: client, defaultContract: config.contracts.nfcNft, collection: config.contracts.collection) }
    private var pocketClient: PocketClient { PocketClient(client: client) }
    private var accountClient: ChimpAccountClient { ChimpAccountClient(client: client, config: config) }

    func state(of publicKey: ChipPublicKey) async throws -> CardState {
        try await Self.readCardState(publicKey, source: try await client.account(config.feePayer),
                                     factory: factory, nfcNft: nfcNft, pocketClient: pocketClient)
    }

    /// `readCardState`. `token_id` qui « trappe » = carte jamais enregistrée (état normal d'une carte vierge) ;
    /// une panne réseau remonte, sinon une carte enregistrée passerait pour vierge.
    static func readCardState(
        _ publicKey: ChipPublicKey,
        source: Account,
        factory: PocketFactoryClient,
        nfcNft: NfcNftClient,
        pocketClient: PocketClient
    ) async throws -> CardState {
        let pocket = try await factory.pocket(of: publicKey, source: source)
        var pocketOwner: String?
        if let pocket {
            pocketOwner = try await pocketClient.owner(of: pocket, source: source)
        }
        var nftContract: String?
        var tokenID: UInt32?
        var nftOwner: String?
        do {
            let found = try await nfcNft.token(of: publicKey, source: source)
            nftContract = found.contract
            tokenID = found.tokenID
            nftOwner = try await nfcNft.owner(ofToken: found.tokenID, contract: found.contract, source: source)
        } catch let error as StellarError where error.isContractTrap {
            // Carte jamais enregistrée (ou NFT d'un ancien contrat sans propriétaire) : « on n'a pas pu l'apprendre ».
        }
        return CardState(pocket: pocket, pocketOwner: pocketOwner, nftContract: nftContract, tokenID: tokenID, nftOwner: nftOwner)
    }

    func resolve(_ publicKey: ChipPublicKey, hint: String?) async throws -> CardResolution {
        let source = try await client.account(config.feePayer)
        var evidence = CardEvidence()
        var seen = Set<String>()

        func check(_ account: String, _ origin: CardResolution.CandidateSource) async -> Bool {
            guard seen.insert(account).inserted else { return false }
            do {
                let member = try await accountClient.hasCard(account: account, publicKey: publicKey, source: source)
                evidence.tried.append(.init(account: account, source: origin, member: member))
            } catch let error as StellarError where error.isContractTrap {
                // Un « trap » est une RÉPONSE : ce n'est pas un Main account (souvent une Pocket qui pointe vers elle-même).
                evidence.tried.append(.init(account: account, source: origin, member: false))
            } catch {
                // Réseau, délai, nœud qui refuse : vraiment « pas demandé », jamais « orphelin ».
                evidence.failed = true
            }
            return evidence.tried.last?.member ?? false
        }

        if let hint, await check(hint, .hint) { return evidence.decide() }

        do {
            // La Pocket de la carte est le seul pointeur que la chaîne porte toujours : c'est le candidat qui fait foi.
            if let pocket = try await factory.pocket(of: publicKey, source: source) {
                evidence.ownPocket = pocket
                let owner = try await pocketClient.owner(of: pocket, source: source)
                if await check(owner, .pocket) { return evidence.decide() }
            }
        } catch {
            evidence.failed = true
        }
        return evidence.decide()
    }
}

/// Faux résolveur pour le simulateur : aucune requête réseau.
struct MockCardResolver: CardResolving {
    var resolution: CardResolution = .enrolled
    var delay: Duration = .milliseconds(600)

    func resolve(_ publicKey: ChipPublicKey, hint: String?) async throws -> CardResolution {
        try await Task.sleep(for: delay)
        return resolution
    }

    func state(of publicKey: ChipPublicKey) async throws -> CardState {
        try await Task.sleep(for: delay)
        let pocket = try PocketFactoryClient.predictedPocket(
            factory: ChimpNetworkConfig.testnet.contracts.factory, publicKey: publicKey, network: .testnet
        )
        return CardState(pocket: pocket, pocketOwner: pocket, nftContract: ChimpNetworkConfig.testnet.contracts.nfcNft, tokenID: 7, nftOwner: pocket)
    }
}
