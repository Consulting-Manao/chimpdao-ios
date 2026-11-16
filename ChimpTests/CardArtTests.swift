import Foundation
import UIKit
import SwiftUI
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

    // MARK: Couleur de fond

    /// Un dessin fabriqué : un fond uni, et un personnage qui mange le milieu. Les bords ne voient que le fond.
    private func drawing(background: UIColor, subject: UIColor) -> UIImage {
        let size = CGSize(width: 200, height: 126)
        return UIGraphicsImageRenderer(size: size).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            subject.setFill()
            context.fill(CGRect(x: 40, y: 25, width: 120, height: 76))
        }
    }

    @Test("Le fond du dessin est relevé sur ses bords, pas sur le personnage au milieu")
    func backgroundColor() throws {
        // Le brun des cartes OG, à peu près.
        let taupe = UIColor(red: 0.42, green: 0.37, blue: 0.31, alpha: 1)
        let found = try #require(CardArtGateway.backgroundColor(of: drawing(background: taupe, subject: .black)))
        var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        found.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 0.42) < 0.02 && abs(g - 0.37) < 0.02 && abs(b - 0.31) < 0.02)
    }

    @Test("Des traits de motif sur le fond ne changent pas la couleur relevée")
    func backgroundIgnoresPattern() throws {
        let taupe = UIColor(red: 0.42, green: 0.37, blue: 0.31, alpha: 1)
        let size = CGSize(width: 200, height: 126)
        let patterned = UIGraphicsImageRenderer(size: size).image { context in
            taupe.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            // Quelques traits plus sombres, comme le motif imprimé sur une vraie carte.
            UIColor.black.withAlphaComponent(0.5).setFill()
            for x in stride(from: 0, to: 200, by: 24) {
                context.fill(CGRect(x: x, y: 0, width: 3, height: 126))
            }
        }
        let found = try #require(CardArtGateway.backgroundColor(of: patterned))
        var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        found.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 0.42) < 0.06 && abs(g - 0.37) < 0.06 && abs(b - 0.31) < 0.06,
                "Le fond l'emporte : les traits sont minoritaires")
    }

    @Test("Image trop petite pour être échantillonnée : pas de couleur, le bandeau garde celle de la carte")
    func backgroundRefuses() {
        #expect(CardArtGateway.backgroundColor(of: drawing(background: .brown, subject: .black), side: 2) == nil)
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

    @Test("Le bandeau d'un tiroir : le fond du dessin quand il est affiché, la couleur de la carte sinon")
    @MainActor
    func bannerFollowsTheDesign() {
        let taupe = Color(uiColor: UIColor(red: 0.42, green: 0.37, blue: 0.31, alpha: 1))
        let art = CardArt(image: UIImage(), design: "Hamac", background: taupe)
        let reader: (String) -> CardArt? = { $0 == "04ab" ? art : nil }

        // Le dessin est affiché (la clé n'est passée que dans ce cas) : son fond.
        let withDesign = ChimpDrawerScene.card(name: "Jungle", color: .pink, number: "0011", key: "04ab")
        #expect(withDesign.banner(art: reader) == taupe)
        // Une couleur choisie : rien ne change.
        let withColour = ChimpDrawerScene.card(name: "Jungle", color: .pink, number: "0011")
        #expect(withColour.banner(art: reader) == ChimpCardColor.pink.sceneBanner)
        // Dessin pas encore arrivé : la couleur, en attendant.
        let pending = ChimpDrawerScene.card(name: "Jungle", color: .pink, number: "0011", key: "04ff")
        #expect(pending.banner(art: reader) == ChimpCardColor.pink.sceneBanner)
        #expect(ChimpDrawerScene.main.banner(art: reader) == Color(.chimpCardLeaf))
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
