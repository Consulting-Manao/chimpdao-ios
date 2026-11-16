import Observation
import stellarsdk
import SwiftUI

/// Le dessin imprimé d'une carte, prêt à afficher.
struct CardArt: Equatable, Sendable {
    let image: UIImage
    /// « Hamac » : le nom du dessin, pour VoiceOver.
    let design: String?
}

/// D'où viennent les dessins : la chaîne et Filebase dans l'app, un faux dans le catalogue et les tests.
protocol CardArtReading: Sendable {
    /// Le dessin de cette carte, ou `nil` si elle n'en a pas d'utilisable (pas de NFT, pas d'image, ou une image qui
    /// n'a pas les proportions d'une carte). Une panne réseau remonte.
    func art(forCard publicKey: ChipPublicKey) async throws -> CardArt?
}

/// La chaîne (quelle campagne, quel jeton, quelle adresse de métadonnées) puis Filebase (métadonnées, image).
struct ChainCardArtReader: CardArtReading {
    let config: ChimpNetworkConfig
    var fetcher: CardArtFetching = FilebaseFetcher()

    func art(forCard publicKey: ChipPublicKey) async throws -> CardArt? {
        let client = SorobanClient(config: config)
        let source = try Account(accountId: config.feePayer, sequenceNumber: 0)
        let nfcNft = NfcNftClient(client: client, defaultContract: config.contracts.nfcNft, collection: config.contracts.collection)
        // La campagne de la carte, pas celle de `Config/` : une carte OG et une carte de campagne ne sont pas au même endroit.
        let token = try await nfcNft.token(of: publicKey, source: source)
        let uri = try await nfcNft.tokenURI(tokenID: token.tokenID, contract: token.contract, source: source)
        guard let metadataURL = CardArtGateway.httpURL(uri) else { throw CardArtError.malformedURI(uri) }
        let metadata = try CardArtGateway.decode(try await fetcher.data(from: metadataURL))
        guard let image = metadata.image, let imageURL = CardArtGateway.httpURL(image) else { return nil }
        guard let drawing = UIImage(data: try await fetcher.data(from: imageURL)) else { throw CardArtError.notAnImage }
        // Décision de Barth du 2026-11-16 : seuls les dessins en forme de carte deviennent la face ; un portrait carré
        // (campagnes de collection) laisse la carte de sa couleur.
        guard CardArtGateway.isCardShaped(width: drawing.size.width, height: drawing.size.height) else { return nil }
        return CardArt(image: drawing, design: metadata.design)
    }
}

/// Les dessins des cartes du compte, lus une fois et gardés en mémoire. Jamais bloquant : tant qu'un dessin n'est pas là,
/// la carte s'affiche de sa couleur, exactement comme avant. Un échec n'est pas réessayé en boucle : il est retenu, et
/// une relecture du Wallet lui donne une nouvelle chance.
@Observable
@MainActor
final class CardArtStore {
    private(set) var art: [String: CardArt] = [:]
    /// Cartes déjà demandées (trouvées, sans dessin, ou en échec) : on ne redemande pas à chaque affichage.
    private var asked: Set<String> = []
    private let reader: CardArtReading

    init(reader: CardArtReading) {
        self.reader = reader
    }

    func art(forKey key: String) -> CardArt? { art[key] }

    /// Charge les dessins manquants des cartes données, en parallèle. À appeler avec les soldes du Wallet.
    func load(cards: [ChipPublicKey]) async {
        let missing = cards.filter { !asked.contains($0.hex) }
        guard !missing.isEmpty else { return }
        for card in missing { asked.insert(card.hex) }
        await withTaskGroup(of: (String, CardArt?).self) { group in
            for card in missing {
                group.addTask { [reader] in
                    ((try? await reader.art(forCard: card)).flatMap { $0 }).map { (card.hex, $0) } ?? (card.hex, nil)
                }
            }
            for await (key, found) in group {
                guard let found else { continue }
                art[key] = found
            }
        }
    }

    /// Une relecture du Wallet redonne sa chance à une carte dont le dessin n'est pas arrivé.
    func forgetFailures() {
        asked = Set(art.keys)
    }
}

/// Faux dessins : une image embarquée, pour le catalogue et les tests (rien n'est demandé au réseau).
struct MockCardArtReader: CardArtReading {
    /// Clés des cartes qui ont un dessin ; les autres restent de leur couleur.
    var withArt: Set<String> = []
    var design: String? = "Hamac"
    var delay: Duration = .milliseconds(300)

    func art(forCard publicKey: ChipPublicKey) async throws -> CardArt? {
        try await Task.sleep(for: delay)
        guard withArt.contains(publicKey.hex), let image = UIImage(named: "CardArtSample") else { return nil }
        return CardArt(image: image, design: design)
    }
}

extension EnvironmentValues {
    /// Le dessin d'une carte, par sa clé publique : `ChimpCard` le prend quand il existe. Vide par défaut, pour que tous
    /// les aperçus et les écrans qui ne connaissent pas la carte gardent la couleur.
    @Entry var chimpCardArt: @MainActor (String) -> CardArt? = { _ in nil }
    /// Le magasin lui-même, pour les écrans qui doivent **demander** le dessin d'une carte qu'ils viennent de lire
    /// (nommer une carte neuve, reconnexion) : le Wallet, lui, les charge déjà avec les soldes. `nil` au catalogue et
    /// dans les aperçus : pas de dessin proposé, la carte garde sa couleur.
    @Entry var chimpCardArtStore: CardArtStore? = nil
}
