import Foundation
import UIKit

/// Le dessin imprimé d'une carte, lu depuis son NFT. Portage de `src/services/ipfs.ts` et `src/services/cards.ts` du
/// site des NFT (`rad:z36Dbu792DiGfpAWxES2bktHYCcUe`), réponse de Pamphile du 2026-11-16 : **tout passe par Filebase**.
///
/// Le contrat donne l'adresse des métadonnées (`token_uri`), les métadonnées donnent l'image. Les cartes d'un même
/// dessin partagent le même fichier : une campagne de 195 cartes ne demande qu'une poignée de fichiers à la passerelle.
///
/// Rien de tout cela ne touche à l'argent : un dessin qui ne se charge pas laisse simplement la carte de sa couleur.
struct CardArtMetadata: Equatable, Sendable {
    /// « Chimp · Hamac ».
    var name: String?
    /// La face de la carte (`image`), telle qu'imprimée.
    var image: String?
    /// Le dos de la carte (`back_image`).
    var backImage: String?
    /// Attributs du NFT (« Design » : Hamac ; « Edition » : OG ; « Code » : 1a).
    var attributes: [String: String] = [:]

    var design: String? { attributes["Design"] }
    var edition: String? { attributes["Edition"] }
}

enum CardArtGateway {
    /// La passerelle de ChimpDAO. `ipfs.io` ne sert plus les fichiers par URL (vérifié le 2026-11-16 : « switching to a
    /// service worker gateway only »), et les anciennes métadonnées nomment leurs fichiers par cette adresse-là.
    static let gateway = "https://ipfs.filebase.io/ipfs/"

    /// Toute adresse vers une URL Filebase (`toHttpUrl`) :
    /// - `ipfs://<chemin>` devient une URL Filebase ;
    /// - toute `http(s)://<hôte>/ipfs/<chemin>` est ramenée sur Filebase ;
    /// - le reste est rendu tel quel (et refusé si ce n'est pas une URL).
    static func httpURL(_ uri: String) -> URL? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        if let path = trimmed.components(separatedBy: "ipfs://").last, trimmed.hasPrefix("ipfs://") {
            return URL(string: gateway + path)
        }
        if let range = trimmed.range(of: #"^https?://[^/]+/ipfs/"#, options: .regularExpression) {
            return URL(string: gateway + String(trimmed[range.upperBound...]))
        }
        return URL(string: trimmed)
    }

    /// Décode les métadonnées d'un NFT. Tolérant : un champ absent n'est pas une erreur, le dessin s'affichera ou non.
    static func decode(_ data: Data) throws -> CardArtMetadata {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CardArtError.malformedMetadata
        }
        var attributes: [String: String] = [:]
        for case let entry as [String: Any] in object["attributes"] as? [Any] ?? [] {
            guard let trait = entry["trait_type"] as? String else { continue }
            if let value = entry["value"] as? String {
                attributes[trait] = value
            } else if let value = entry["value"] as? NSNumber {
                attributes[trait] = value.stringValue
            }
        }
        return CardArtMetadata(
            name: object["name"] as? String,
            image: object["image"] as? String,
            backImage: object["back_image"] as? String,
            attributes: attributes
        )
    }

    /// La couleur de fond d'un dessin : celle qui domine **sur ses bords**, là où il n'y a que le fond de la carte et
    /// pas le personnage. C'est elle que le bandeau de la page du tiroir reprend (demande de Barth du 2026-11-16 :
    /// « le fond de la carte en elle-même »).
    ///
    /// L'image est d'abord réduite à 32 × 32 (une poignée d'octets, quelle que soit sa taille d'origine), puis on ne
    /// garde que son anneau extérieur. Les couleurs sont regroupées par paquets grossiers pour que les traits du motif
    /// ne comptent pas comme des couleurs à part ; la couleur rendue est la moyenne exacte du paquet le plus nombreux.
    /// `nil` si l'image ne peut pas être lue : le bandeau garde alors la couleur de la carte.
    static func backgroundColor(of image: UIImage, side: Int = 32) -> UIColor? {
        guard side >= 3, let pixels = edgePixels(of: image, side: side), !pixels.isEmpty else { return nil }
        // Paquets de 32 niveaux par canal : deux bruns voisins tombent ensemble, le noir du trait reste à part.
        var counts: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        for pixel in pixels {
            let key = (Int(pixel.0) / 32) << 10 | (Int(pixel.1) / 32) << 5 | (Int(pixel.2) / 32)
            var bucket = counts[key] ?? (0, 0, 0, 0)
            bucket.count += 1
            bucket.r += Int(pixel.0); bucket.g += Int(pixel.1); bucket.b += Int(pixel.2)
            counts[key] = bucket
        }
        // À égalité, le paquet le plus clair : le fond d'une carte est plus clair que ses traits.
        guard let winner = counts.values.max(by: { ($0.count, $0.r + $0.g + $0.b) < ($1.count, $1.r + $1.g + $1.b) }) else {
            return nil
        }
        let n = CGFloat(winner.count)
        return UIColor(red: CGFloat(winner.r) / n / 255, green: CGFloat(winner.g) / n / 255,
                       blue: CGFloat(winner.b) / n / 255, alpha: 1)
    }

    /// L'anneau extérieur de l'image réduite à `side` × `side`, en composantes rouge/vert/bleu.
    private static func edgePixels(of image: UIImage, side: Int) -> [(UInt8, UInt8, UInt8)]? {
        let bytesPerRow = side * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * side)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &buffer, width: side, height: side, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let cgImage = image.cgImage else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        var pixels: [(UInt8, UInt8, UInt8)] = []
        for y in 0..<side {
            for x in 0..<side where x == 0 || y == 0 || x == side - 1 || y == side - 1 {
                let offset = y * bytesPerRow + x * 4
                // Un bord transparent n'est pas un fond : on l'ignore.
                guard buffer[offset + 3] > 200 else { continue }
                pixels.append((buffer[offset], buffer[offset + 1], buffer[offset + 2]))
            }
        }
        return pixels
    }

    /// Un dessin est utilisable comme face de carte s'il a **les proportions d'une carte** (décision de Barth du
    /// 2026-11-16 : seuls les dessins en forme de carte sont utilisés ; les portraits carrés des campagnes de collection
    /// laissent la carte de sa couleur). Tolérance de 8 % autour de 1,58:1.
    static func isCardShaped(width: Double, height: Double) -> Bool {
        guard width > 0, height > 0 else { return false }
        let ratio = width / height
        return abs(ratio - ChimpSize.cardAspectRatio) / ChimpSize.cardAspectRatio <= 0.08
    }
}

enum CardArtError: Error, Equatable, LocalizedError {
    case malformedMetadata
    case notAnImage
    /// L'adresse rendue par le contrat n'est pas une URL exploitable.
    case malformedURI(String)

    var errorDescription: String? {
        switch self {
        case .malformedMetadata: "This card's design couldn't be read."
        case .notAnImage: "This card's design isn't an image."
        case .malformedURI(let uri): "This card's design is at an address I can't open (\(uri))."
        }
    }
}

/// D'où viennent les fichiers d'un dessin : Filebase dans l'app, un faux dans les tests.
protocol CardArtFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

/// Lecture par le réseau, sans en-tête ni identifiant : la passerelle ne reçoit que l'adresse publique du fichier, et les
/// cartes d'un même dessin demandent le même (rien n'identifie une carte).
struct FilebaseFetcher: CardArtFetching {
    var session: URLSession = .shared
    var timeout: TimeInterval = 20

    func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StellarError.rpc("\(url.host ?? "gateway") answered \(http.statusCode)")
        }
        return data
    }
}
