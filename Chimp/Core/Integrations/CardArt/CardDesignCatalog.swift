#if CHIMP_ADMIN
import Foundation
import UIKit
import stellarsdk

/// Les dessins qu'une campagne a déjà imprimés : ce que Chimp Admin propose au moment d'enregistrer une carte.
/// Portage de `getTokenUris` (`src/services/stellar.ts`) et `groupByDesign` (`src/services/cards.ts`) du site des NFT.
///
/// Les cartes d'un même dessin partagent **la même adresse de métadonnées** : la liste des dessins est donc la liste
/// des adresses distinctes parmi les jetons déjà frappés. C'est aussi ce qu'on passe au `mint` d'une carte neuve pour
/// qu'elle ait ce dessin-là.
struct CardDesign: Identifiable, Sendable {
    /// L'adresse des métadonnées, telle que le contrat la rend : c'est elle qu'on passe au `mint`.
    let uri: String
    /// « Hamac » (attribut `Design`), sinon le nom du NFT.
    let name: String
    /// « 1a » (attribut `Code`) : l'ordre dans lequel les dessins ont été imprimés.
    let code: String?
    /// « OG » (attribut `Edition`).
    let edition: String?
    /// Combien de cartes portent déjà ce dessin.
    let count: Int
    /// L'image de la face, prête à afficher.
    let image: UIImage?

    var id: String { uri }
}

extension CardDesign: Equatable {
    /// Deux dessins sont le même s'ils ont la même adresse de métadonnées (l'image n'est qu'un rendu).
    static func == (lhs: CardDesign, rhs: CardDesign) -> Bool { lhs.uri == rhs.uri }
}

enum CardDesignCatalog {
    /// Le RPC limite une requête à 200 clés ; on reste bien en dessous (comme `FleetClient`).
    static let keysPerRequest = 100

    /// La clé de l'adresse de métadonnées d'un jeton (`TokenUri(id)`), dans le stockage persistant du contrat.
    static func tokenURIKey(contract: String, tokenID: UInt32) throws -> LedgerKeyXDR {
        .contractData(LedgerKeyContractDataXDR(
            contract: try SCAddressXDR(contractId: contract),
            key: .vec([.symbol("TokenUri"), .u32(tokenID)]),
            durability: .persistent
        ))
    }

    /// Combien de jetons sont frappés, et l'adresse de repli de la campagne (`NextTokenId` et `Uri` de son instance).
    static func instanceFacts(_ instance: SCContractInstanceXDR) -> (next: UInt32, baseURI: String?) {
        var next: UInt32 = 0
        var base: String?
        for field in instance.storage ?? [] {
            let name: String? = switch field.key {
            case .vec(let parts): parts?.first.flatMap { if case .symbol(let s) = $0 { s } else { nil } }
            case .symbol(let s): s
            default: nil
            }
            if name == "NextTokenId", let value = field.val.u32 { next = value }
            if name == "Uri", let value = field.val.string { base = value }
        }
        return (next, base)
    }

    /// Les dessins de la campagne, du plus anciennement imprimé au plus récent. Un jeton sans adresse propre retombe sur
    /// `{base_uri}/{id}`, qui n'est pas un fichier de métadonnées : ces jetons-là sont **ignorés** (ils n'ont pas de dessin).
    static func designs(
        contract: String, client: SorobanClient, fetcher: CardArtFetching = FilebaseFetcher()
    ) async throws -> [CardDesign] {
        guard let instanceKey = try FleetClient.instanceKey(contract).xdrEncoded,
              let entry = try await client.ledgerEntries([instanceKey]).first,
              case .contractData(let data)? = entry.valueXdr, case .contractInstance(let instance) = data.val else {
            throw StellarError.invalidResponse("\(contract.prefix(8))… has no contract instance")
        }
        let facts = instanceFacts(instance)
        guard facts.next > 0 else { return [] }

        // Combien de cartes par adresse, dans l'ordre où les jetons ont été frappés.
        var order: [String] = []
        var counts: [String: Int] = [:]
        for start in stride(from: UInt32(0), to: facts.next, by: keysPerRequest) {
            let ids = (start..<min(start + UInt32(keysPerRequest), facts.next))
            let keys = try ids.compactMap { try tokenURIKey(contract: contract, tokenID: $0).xdrEncoded }
            for found in try await client.ledgerEntries(keys) {
                guard case .contractData(let row)? = found.valueXdr, let uri = row.val.string else { continue }
                if counts[uri] == nil { order.append(uri) }
                counts[uri, default: 0] += 1
            }
        }

        var designs: [CardDesign] = []
        for uri in order {
            guard let metadataURL = CardArtGateway.httpURL(uri),
                  let metadata = try? CardArtGateway.decode(try await fetcher.data(from: metadataURL)) else { continue }
            var image: UIImage?
            if let drawing = metadata.image, let url = CardArtGateway.httpURL(drawing),
               let data = try? await fetcher.data(from: url) {
                image = UIImage(data: data)
            }
            designs.append(CardDesign(
                uri: uri,
                name: metadata.design ?? metadata.name ?? String(localized: "Design"),
                code: metadata.attributes["Code"],
                edition: metadata.edition,
                count: counts[uri] ?? 0,
                image: image
            ))
        }
        // Comme le site : par code d'impression quand il existe, sinon par nom.
        return designs.sorted { ($0.code ?? $0.name) < ($1.code ?? $1.name) }
    }
}
#endif
