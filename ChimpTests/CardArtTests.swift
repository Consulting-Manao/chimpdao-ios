import Foundation
import UIKit
import Testing
@testable import ChimpDAO

/// Le dessin imprimé d'une carte (NFT), lu par Filebase : portage de `src/services/ipfs.ts` et `cards.ts` du site des
/// NFT. Valeurs relevées sur le vrai testnet le 2026-11-16.
struct CardArtTests {
    // MARK: Adresses

    @Test("ipfs:// passe par Filebase")
    func ipfsScheme() {
        #expect(CardArtGateway.httpURL("ipfs://bafyabc")?.absoluteString == "https://ipfs.filebase.io/ipfs/bafyabc")
    }

    @Test("Une adresse d'une autre passerelle est ramenée sur Filebase (ipfs.io ne sert plus les fichiers)")
    func otherGateway() {
        // Ce que rend vraiment `token_uri(7)` de la campagne chi4.
        let uri = "https://ipfs.io/ipfs/bafybeihfqx4pstq4au6ueuzj4ns2ovmw237zfh2z2qvz6rxssdjzlnpcna/7"
        #expect(CardArtGateway.httpURL(uri)?.absoluteString
            == "https://ipfs.filebase.io/ipfs/bafybeihfqx4pstq4au6ueuzj4ns2ovmw237zfh2z2qvz6rxssdjzlnpcna/7")
        #expect(CardArtGateway.httpURL("http://dweb.link/ipfs/bafy/3")?.absoluteString == "https://ipfs.filebase.io/ipfs/bafy/3")
    }

    @Test("Une adresse qui n'est pas IPFS est gardée telle quelle")
    func otherURL() {
        #expect(CardArtGateway.httpURL("https://nft.chimpdao.xyz/card/7")?.absoluteString == "https://nft.chimpdao.xyz/card/7")
    }

    // MARK: Métadonnées

    /// Les métadonnées d'une carte OG, telles que la passerelle les rend (campagne `og`, testnet et mainnet).
    static let ogMetadata = Data("""
    {
      "name": "Chimp · Hamac",
      "description": "Chimp OG card. Gone chillin', back in 5 bananas.",
      "image": "ipfs://bafybeiglve7xqybzoc5f6u6gd7x2aweithamlgy42bxyyhbi6k6vex65ay",
      "back_image": "ipfs://bafybeibou66hxyyczkvyp5vzrmmjsmgcq4wlfp74jyuzpdhjgrhqp7sdkq",
      "attributes": [
        { "trait_type": "Edition", "value": "OG" },
        { "trait_type": "Design", "value": "Hamac" },
        { "trait_type": "Code", "value": "1a" }
      ]
    }
    """.utf8)

    @Test("Métadonnées d'une carte OG : la face, le dos, le dessin et l'édition")
    func decodeOG() throws {
        let metadata = try CardArtGateway.decode(Self.ogMetadata)
        #expect(metadata.name == "Chimp · Hamac")
        #expect(metadata.image == "ipfs://bafybeiglve7xqybzoc5f6u6gd7x2aweithamlgy42bxyyhbi6k6vex65ay")
        #expect(metadata.backImage == "ipfs://bafybeibou66hxyyczkvyp5vzrmmjsmgcq4wlfp74jyuzpdhjgrhqp7sdkq")
        #expect(metadata.design == "Hamac")
        #expect(metadata.edition == "OG")
        #expect(metadata.attributes["Code"] == "1a")
    }

    @Test("Métadonnées d'une carte de collection (Palta Chimpy, chi4) : pas de dessin ni de dos")
    func decodeCollection() throws {
        let data = Data("""
        {"attributes": [{"trait_type": "Background", "value": "pink"}, {"trait_type": "Headwear", "value": "stellar_cap"}],
         "image": "https://ipfs.io/ipfs/bafybeihen2ofzjprjcbpw7aopvcbcxg7opeugdoebix4rsa3b3xh3fqwve/7.png",
         "name": "Palta Chimpy #7"}
        """.utf8)
        let metadata = try CardArtGateway.decode(data)
        #expect(metadata.name == "Palta Chimpy #7")
        #expect(metadata.design == nil)
        #expect(metadata.backImage == nil)
        #expect(metadata.attributes["Background"] == "pink")
    }

    @Test("Des métadonnées illisibles sont une erreur, jamais un dessin vide")
    func decodeRefuses() {
        #expect(throws: CardArtError.malformedMetadata) { try CardArtGateway.decode(Data("[1,2]".utf8)) }
    }

    @Test("Un attribut qui n'est pas du texte est lu quand même (nombre), les autres sont ignorés")
    func decodeAttributes() throws {
        let data = Data(#"{"attributes":[{"trait_type":"Code","value":12},{"value":"orphan"},{"trait_type":"X","value":{"a":1}}]}"#.utf8)
        let metadata = try CardArtGateway.decode(data)
        #expect(metadata.attributes == ["Code": "12"])
    }

    // MARK: Forme

    @Test("Seul un dessin en forme de carte devient la face")
    func cardShaped() {
        // La vraie carte OG « Hamac ».
        #expect(CardArtGateway.isCardShaped(width: 2022, height: 1276))
        // Le vrai Palta Chimpy n°7 : carré, donc refusé (décision de Barth du 2026-11-16).
        #expect(!CardArtGateway.isCardShaped(width: 2048, height: 2048))
        #expect(!CardArtGateway.isCardShaped(width: 1920, height: 1080), "16:9 n'est pas une carte")
        #expect(!CardArtGateway.isCardShaped(width: 0, height: 0))
        // Tolérance : un rognage de quelques pour cent reste une carte.
        #expect(CardArtGateway.isCardShaped(width: 1000, height: 650))
    }

    // MARK: Lecture complète

    /// Une fausse passerelle : chaque adresse rend ce qu'on lui a donné.
    struct FakeFetcher: CardArtFetching {
        let files: [String: Data]
        func data(from url: URL) async throws -> Data {
            guard let found = files[url.absoluteString] else { throw StellarError.rpc("404") }
            return found
        }
    }

    @Test("Le magasin ne demande qu'une fois par carte, et une carte sans dessin reste de sa couleur")
    @MainActor
    func storeAsksOnce() async {
        let reader = CountingReader()
        let store = CardArtStore(reader: reader)
        let withArt = MockChipReader.secp256k1Key
        let without = MockChipReader.p256Key
        reader.art = [withArt.hex: CardArt(image: UIImage(), design: "Hamac")]

        await store.load(cards: [withArt, without])
        #expect(store.art(forKey: withArt.hex)?.design == "Hamac")
        #expect(store.art(forKey: without.hex) == nil)
        #expect(reader.calls == 2)

        await store.load(cards: [withArt, without])
        #expect(reader.calls == 2, "déjà demandées : rien de plus")

        // Une relecture du Wallet redonne sa chance à la carte sans dessin, pas à celle qui en a un.
        store.forgetFailures()
        await store.load(cards: [withArt, without])
        #expect(reader.calls == 3)
    }

    final class CountingReader: CardArtReading, @unchecked Sendable {
        var art: [String: CardArt] = [:]
        private(set) var calls = 0
        func art(forCard publicKey: ChipPublicKey) async throws -> CardArt? {
            calls += 1
            return art[publicKey.hex]
        }
    }
}
