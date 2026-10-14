import Foundation

/// Les bornes d'une action d'intégration, **relues dans l'appel réellement construit** (principe 4 de la tranche 2) :
/// contrat cible, autorisateur, actif et montant donnés, actif reçu et minimum garanti, route, échéance.
///
/// L'écran de vérification affiche ces bornes-là, décodées de l'appel que la carte va signer, et non une copie tenue à
/// part : ce qui est affiché est ce qui est signé (principe 3). Un écart après la signature fait échouer la transaction,
/// parce que chaque borne est un argument de l'appel signé. Uniquement des quantités, jamais de dollars (`Slippage`).
struct SignedTerms: Equatable {
    enum Action: String, Equatable {
        case swap, deposit, withdraw
    }

    let action: Action
    /// Le contrat appelé (router, vault).
    let contract: String
    /// Qui autorise et reçoit (Main account ou Pocket).
    let authorizer: String
    /// Ce qui part : actif (SAC, ou jeton de parts d'un vault) et montant exact, en unités on-chain.
    let assetIn: String
    let amountIn: Int128
    /// Ce qui arrive : actif, et minimum garanti par l'appel (`nil` quand l'appel n'en fixe pas, comme un dépôt).
    let assetOut: String?
    let minimumOut: Int128?
    /// Route complète d'un swap (premier actif → dernier), vide sinon.
    let route: [String]
    /// Échéance en secondes Unix (`deadline` de Soroswap), `nil` si l'appel n'en porte pas.
    let deadline: UInt64?
}

/// Vérification des bornes avant la préparation de la signature.
enum BoundsCheck {
    /// Une échéance de swap ne dépasse jamais 5 minutes (`SWAP_DEADLINE_SECS`), bien à l'intérieur de la fenêtre
    /// d'autorisation de la carte (~10 minutes).
    static let maximumDeadlineSeconds: UInt64 = 300

    enum BoundsError: Error, Equatable, LocalizedError {
        /// L'appel construit ne porte pas ce que l'écran montre.
        case differs(field: String)
        /// Un swap ou un retrait sans minimum reçu (ou à 0) : refusé.
        case noMinimum
        /// Le minimum signé laisse filer plus que le slippage maximum (3 %) sous le devis.
        case slippageAboveMaximum(minimum: Int128, floor: Int128)
        case deadlinePassed
        case deadlineTooFar

        var errorDescription: String? {
            switch self {
            case .differs(let field): "The prepared call doesn't match what is shown (\(field))."
            case .noMinimum: "The prepared call guarantees no minimum amount."
            case .slippageAboveMaximum(let minimum, let floor): "The minimum \(minimum) is below the \(Slippage.maximumBasisPoints / 100) % floor \(floor)."
            case .deadlinePassed: "The deadline has already passed."
            case .deadlineTooFar: "The deadline is too far away."
            }
        }
    }

    /// `shown` : ce que l'écran affiche. `signed` : les bornes décodées de l'appel construit. `quotedOut` : le dernier
    /// devis (quantité reçue attendue), s'il y en a un. `now` : l'heure en secondes Unix.
    static func verify(shown: SignedTerms, signed: SignedTerms, quotedOut: Int128?, now: UInt64) throws {
        let fields: [(String, Bool)] = [
            ("action", shown.action == signed.action),
            ("contract", shown.contract == signed.contract),
            ("authorizer", shown.authorizer == signed.authorizer),
            ("asset given", shown.assetIn == signed.assetIn),
            ("amount given", shown.amountIn == signed.amountIn),
            ("asset received", shown.assetOut == signed.assetOut),
            ("minimum received", shown.minimumOut == signed.minimumOut),
            ("route", shown.route == signed.route),
            ("deadline", shown.deadline == signed.deadline),
        ]
        if let differing = fields.first(where: { !$0.1 }) { throw BoundsError.differs(field: differing.0) }

        if signed.action != .deposit {
            guard let minimum = signed.minimumOut, minimum > 0 else { throw BoundsError.noMinimum }
            if let quotedOut {
                let floor = Slippage.minimum(of: quotedOut, basisPoints: Slippage.maximumBasisPoints)
                guard minimum >= floor else { throw BoundsError.slippageAboveMaximum(minimum: minimum, floor: floor) }
            }
        }
        if let deadline = signed.deadline {
            guard deadline > now else { throw BoundsError.deadlinePassed }
            guard deadline - now <= maximumDeadlineSeconds else { throw BoundsError.deadlineTooFar }
        }
    }
}
