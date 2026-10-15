import Foundation

/// Message de « Share » d'un reçu (Activity et C9), dans le ton de Chimpy : textes validés par Barth le 2026-10-02.
///
/// Il garde les faits utiles (montant exact, autre partie en court, date, réseau, lien Stellar Expert comme preuve) et
/// ajoute une petite chute tirée dans une liste. Le tirage dépend de la transaction : le même reçu donne toujours le même
/// texte. Sur testnet, « (play money) » : personne ne doit croire à de vrais fonds.
enum ShareMessage {
    enum Story: Equatable {
        /// Envoi vers une adresse (déjà raccourcie).
        case sent(to: String)
        /// Paiement reçu d'une adresse, dans un tiroir (« Main account »).
        case received(from: String, into: String)
        /// Move entre deux tiroirs.
        case moved(from: String, to: String)
        /// Carte ajoutée, et la carte qui a dit oui si on la connaît.
        case cardAdded(card: String, approvedBy: String?)
        /// Swap dans un tiroir : ce qui est arrivé (exact), si on le sait.
        case swapped(received: String?, in: String)
        /// Dépôt dans un vault (« DeFindex XLM »), depuis un tiroir.
        case deposited(vault: String, from: String)
        /// Retrait d'un vault, vers un tiroir.
        case withdrawn(vault: String, into: String)
        /// Clawback : l'émetteur (« Etherfuse ») a repris des jetons d'un tiroir.
        case takenBack(by: String, from: String)
        /// Arrivée d'une autre blockchain (« Ethereum ») par Circle CCTP, dans un tiroir.
        case arrived(from: String, into: String)
    }

    static let sentPunchlines: [LocalizedStringResource] = [
        "Tap. Sign. Swing. Done.",
        "Faster than a monkey on a vine.",
        "No banana was harmed.",
    ]

    static let receivedPunchlines: [LocalizedStringResource] = [
        "Chimpy is doing his happy dance.",
        "The jungle provides.",
        "Ripe and ready.",
    ]

    static func text(_ story: Story, amount: String?, date: String, network: StellarNetwork, explorerURL: URL?, hash: String) -> String {
        let networkName = network == .mainnet ? network.displayName : String(localized: "\(network.displayName) (play money)")
        let amount = amount ?? ""
        let proof = explorerURL.map { String(localized: "Proof, straight from the jungle: \($0.absoluteString)") }
        var lines: [String]
        switch story {
        case .sent(let to):
            lines = [
                String(localized: "🍌 Swoosh! I just sent \(amount) to \(to) with ChimpDAO."),
                String(localized: pick(sentPunchlines, hash: hash)),
                "\(networkName) · \(date)",
            ]
            if let proof { lines.append(proof) }
        case let .received(from, into):
            lines = [
                String(localized: "🐵 Bananas incoming! \(from) sent me \(amount)."),
                String(localized: pick(receivedPunchlines, hash: hash)),
                String(localized: "Landed in my \(into) · \(networkName) · \(date)"),
            ]
            if let proof { lines.append(proof) }
        case let .moved(from, to):
            lines = [
                String(localized: "🌴 Moved \(amount) from \(from) to \(to)."),
                String(localized: "Same jungle, different branch."),
                "\(networkName) · \(date)",
            ]
        case let .swapped(received, drawer):
            lines = [
                received.map { String(localized: "🔄 Swapped \(amount) for \($0) with ChimpDAO.") }
                    ?? String(localized: "🔄 Swapped \(amount) with ChimpDAO."),
                String(localized: "Same drawer, different coin."),
                String(localized: "In my \(drawer) · \(networkName) · \(date)"),
            ]
            if let proof { lines.append(proof) }
        case let .deposited(vault, drawer):
            // Aucun rendement promis, même pour rire : seulement ce qui a été fait.
            lines = [
                String(localized: "🌱 Planted \(amount) in the \(vault) vault with ChimpDAO."),
                String(localized: "Not guaranteed, not advice. Just bananas in the ground."),
                String(localized: "From my \(drawer) · \(networkName) · \(date)"),
            ]
            if let proof { lines.append(proof) }
        case let .withdrawn(vault, drawer):
            lines = [
                String(localized: "🧺 Took \(amount) out of the \(vault) vault with ChimpDAO."),
                String(localized: "Back home, ready to use."),
                String(localized: "Into my \(drawer) · \(networkName) · \(date)"),
            ]
            if let proof { lines.append(proof) }
        case let .arrived(chain, drawer):
            lines = [
                String(localized: "🌉 \(amount) just arrived from \(chain) with ChimpDAO."),
                String(localized: "Native USDC, via Circle CCTP."),
                String(localized: "Landed in my \(drawer) · \(networkName) · \(date)"),
            ]
            if let proof { lines.append(proof) }
        case let .takenBack(issuer, drawer):
            // Rien de festif : ce qui s'est passé, avec la preuve.
            lines = [
                String(localized: "\(issuer) took back \(amount) from my \(drawer)."),
                "\(networkName) · \(date)",
            ]
            if let proof { lines.append(proof) }
        case let .cardAdded(card, approvedBy):
            lines = [
                approvedBy.map { String(localized: "🃏 \(card) just joined my jungle! \($0) said yes.") }
                    ?? String(localized: "🃏 \(card) just joined my jungle!"),
                String(localized: "The gang keeps growing."),
                "\(networkName) · \(date)",
            ]
        }
        return lines.joined(separator: "\n")
    }

    /// Chute choisie par la transaction : toujours la même pour un même hash (somme des caractères, pas `hashValue`, qui
    /// change à chaque lancement de l'app).
    static func pick(_ lines: [LocalizedStringResource], hash: String) -> LocalizedStringResource {
        let seed = hash.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return lines[seed % lines.count]
    }
}
