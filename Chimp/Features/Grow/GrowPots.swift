import Foundation

/// Un « pot » de Grow (maquette « Chimp Grow Final », 2026-10-18) : ce qu'un tiroir a mis à pousser chez un protocole.
/// Un pot par protocole et par tiroir, jamais fusionnés entre tiroirs. Seule la croissance **réelle** est montrée (valeur
/// actuelle moins ce qui a été mis), jamais un taux.
struct GrowPot: Identifiable, Equatable {
    enum State: Equatable {
        case growing
        /// XOXNO : une position dont les données ont expiré (valeur inconnue, jamais montrée comme zéro).
        case needsRenewal
        /// XOXNO : une position avec dette (jamais créée par l'app) : montrée, sans action.
        case hasDebt
        /// CETES gelés par l'émetteur.
        case frozen
    }

    var id: String { "\(mark.rawValue):\(drawerID)" }
    /// Clé de l'historique : le protocole et l'adresse du tiroir (unique, quel que soit le compte ouvert).
    var historyKey: String { "\(mark.rawValue):\(drawerAddress)" }
    let mark: ChimpPotProtocol
    let drawerID: String
    let drawerAddress: String
    let asset: SendAsset
    let state: State
    /// Quantité détenue, dans l'actif du pot ; `nil` quand elle n'est pas connue (position à renouveler).
    let value: Decimal?
    /// Ce qui a été mis, et depuis quand (DeFindex, XOXNO) ; `nil` sans historique.
    let putIn: Decimal?
    let since: Date?
    /// CETES : le prix d'un jeton en dollars au moment de l'obtention, et maintenant (Etherfuse).
    let basisPriceUSD: Decimal?
    let priceUSD: Decimal?
    /// Ce qui peut sortir maintenant (XOXNO, DeFindex), dans l'actif du pot.
    let withdrawableNow: Decimal?
    /// Nombre de positions regroupées dans ce pot (XOXNO : chaque dépôt en ouvre une).
    var positions = 1

    /// La croissance réelle, dans l'actif du pot (DeFindex, XOXNO) ; `nil` sans base ou sans valeur.
    var growth: Decimal? {
        guard mark != .etherfuse, let value, let putIn else { return nil }
        return value - putIn
    }

    /// CETES : l'évolution du prix depuis l'obtention (fraction, 0.0062 = +0,62 %).
    var priceChange: Decimal? {
        guard mark == .etherfuse, let basis = basisPriceUSD, basis > 0, let price = priceUSD else { return nil }
        return (price - basis) / basis
    }

    /// CETES : ce que valent les jetons, au prix d'Etherfuse.
    var worthUSD: Decimal? {
        guard mark == .etherfuse, let value, let price = priceUSD else { return nil }
        return value * price
    }

    /// La croissance en dollars, pour l'en-tête : XLM au prix de l'oracle, USDC à 1 $, CETES au prix d'Etherfuse ;
    /// `nil` si un prix ou une base manque (l'en-tête n'affiche alors pas de total partiel).
    func growthUSD(xlmUSD: Decimal?) -> Decimal? {
        switch mark {
        case .etherfuse:
            guard let value, let basis = basisPriceUSD, let price = priceUSD else { return nil }
            return value * (price - basis)
        default:
            guard let growth else { return nil }
            switch asset {
            case .usdc: return growth
            case .xlm: return xlmUSD.map { growth * $0 }
            default: return nil
            }
        }
    }

    var canMove: Bool { state == .growing || (mark == .etherfuse && state != .frozen) }
}

/// Les pots d'un compte, construits à partir des trois services (vault, prêt, CETES).
enum GrowPots {
    /// Les tiroirs dans l'ordre de l'app (Main, puis les cartes), tels qu'au moins un service les a lus.
    static func drawers(vault: VaultContext?, lending: VaultContext?, savings: SavingsContext?) -> [SendDrawer] {
        for context in [vault?.drawers, lending?.drawers, savings?.drawers] {
            if let drawers = context, !drawers.isEmpty { return drawers }
        }
        return []
    }

    static func build(vault: VaultContext?, lending: VaultContext?, savings: SavingsContext?) -> [GrowPot] {
        var pots: [GrowPot] = []
        for drawer in drawers(vault: vault, lending: lending, savings: savings) {
            if let vault, let holding = vault.holdings.first(where: { $0.drawerID == drawer.id }) {
                pots.append(GrowPot(
                    mark: .defindex, drawerID: drawer.id, drawerAddress: drawer.address, asset: vault.vault.asset, state: .growing,
                    value: holding.value, putIn: holding.basis?.putIn, since: holding.basis?.since, basisPriceUSD: nil, priceUSD: nil,
                    withdrawableNow: min(holding.value, vault.vault.availableNow)
                ))
            }
            if let lending {
                let mine = lending.holdings.filter { $0.drawerID == drawer.id }
                if !mine.isEmpty {
                    let movable = mine.filter { $0.condition == .movable }
                    let state: GrowPot.State = !movable.isEmpty ? .growing : mine.contains { $0.condition == .needsRenewal } ? .needsRenewal : .hasDebt
                    let value = movable.isEmpty ? nil : movable.map(\.value).reduce(0, +)
                    let largest = movable.map(\.value).max()
                    pots.append(GrowPot(
                        mark: .xoxno, drawerID: drawer.id, drawerAddress: drawer.address, asset: lending.vault.asset, state: state,
                        value: value, putIn: movable.first?.basis?.putIn, since: movable.first?.basis?.since, basisPriceUSD: nil, priceUSD: nil,
                        withdrawableNow: largest.map { min($0, lending.vault.availableNow) }, positions: mine.count
                    ))
                }
            }
            if let savings, let holding = savings.holding(drawerAddress: drawer.address) {
                pots.append(GrowPot(
                    mark: .etherfuse, drawerID: drawer.id, drawerAddress: drawer.address, asset: savings.asset,
                    state: holding.frozen ? .frozen : .growing, value: holding.amount, putIn: nil, since: holding.basis?.since,
                    basisPriceUSD: holding.basis?.unitPriceUSD, priceUSD: savings.price.price?.usd, withdrawableNow: nil
                ))
            }
        }
        return pots
    }

    /// La somme en dollars de `pots`, ou `nil` si l'une manque (jamais de total partiel).
    static func totalUSD(_ pots: [GrowPot], xlmUSD: Decimal?) -> Decimal? {
        var total: Decimal = 0
        for pot in pots where pot.state != .needsRenewal {
            guard let growth = pot.growthUSD(xlmUSD: xlmUSD) else { return nil }
            total += growth
        }
        return total
    }
}

// MARK: Historique

/// Une valeur relevée un jour donné : la croissance (DeFindex, XOXNO, dans l'actif du pot) ou le prix d'un jeton (CETES).
struct PotReading: Codable, Equatable {
    let day: Date
    let value: Decimal
}

/// Les valeurs relevées sur ce téléphone, une par jour et par pot (décision de Barth du 2026-10-18 : la courbe et « THIS
/// WEEK » ne montrent que des valeurs réelles). On garde la **croissance** (valeur − mis) plutôt que la valeur, pour qu'un
/// dépôt ou un retrait ne dessine pas une fausse pousse ; pour les CETES, le prix d'un jeton.
protocol PotHistoryStore: AnyObject {
    func readings(_ potID: String) -> [PotReading]
    func record(_ reading: PotReading, potID: String)
}

enum PotHistory {
    /// Jours gardés.
    static let keptDays = 120

    /// Ce qu'un pot relève aujourd'hui, `nil` s'il n'y a rien d'honnête à garder.
    static func reading(of pot: GrowPot, day: Date) -> PotReading? {
        switch pot.mark {
        case .etherfuse: pot.priceUSD.map { PotReading(day: day, value: $0) }
        default: pot.growth.map { PotReading(day: day, value: $0) }
        }
    }

    /// La série de la courbe : le point de départ (rien n'a encore poussé, ou le prix d'obtention), puis les relevés
    /// depuis ce jour-là, dans l'ordre. Une seule valeur → ligne plate.
    static func series(of pot: GrowPot, readings: [PotReading]) -> [Double] {
        let start: Decimal? = pot.mark == .etherfuse ? pot.basisPriceUSD : (pot.putIn == nil ? nil : 0)
        let kept = readings.filter { reading in pot.since.map { reading.day >= Calendar.current.startOfDay(for: $0) } ?? true }
            .sorted { $0.day < $1.day }
        let values = (start.map { [$0] } ?? []) + kept.map(\.value)
        return values.map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    /// « THIS WEEK » : ce qui a poussé depuis 7 jours. Planté cette semaine : toute la croissance. Sinon, il faut un relevé
    /// d'il y a au moins 7 jours ; sans lui, `nil` (la ligne est masquée).
    static func thisWeek(of pot: GrowPot, readings: [PotReading], now: Date = .now) -> Decimal? {
        guard pot.mark != .etherfuse, let growth = pot.growth else { return nil }
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        if let since = pot.since, since >= weekAgo { return growth }
        guard let old = readings.filter({ $0.day <= weekAgo }).max(by: { $0.day < $1.day }) else { return nil }
        return growth - old.value
    }

    /// Jours de croissance (« GROWING FOR 26 DAYS »).
    static func days(since: Date?, now: Date = .now) -> Int? {
        since.map { max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: $0), to: Calendar.current.startOfDay(for: now)).day ?? 0) }
    }
}

/// Les relevés dans les préférences du téléphone (des nombres et des dates, rien de secret).
/// Relu à chaque fois, sans copie en mémoire : après « Erase everything », rien ne peut réécrire l'ancien historique.
final class DefaultsPotHistoryStore: PotHistoryStore {
    static let key = "potHistory"

    private var all: [String: [PotReading]] {
        UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([String: [PotReading]].self, from: $0) } ?? [:]
    }

    func readings(_ potID: String) -> [PotReading] { all[potID] ?? [] }

    func record(_ reading: PotReading, potID: String) {
        var store = all
        let day = Calendar.current.startOfDay(for: reading.day)
        var list = (store[potID] ?? []).filter { $0.day != day }
        list.append(PotReading(day: day, value: reading.value))
        let oldest = day.addingTimeInterval(-Double(PotHistory.keptDays) * 86_400)
        store[potID] = list.filter { $0.day >= oldest }.sorted { $0.day < $1.day }
        if let data = try? JSONEncoder().encode(store) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

final class MemoryPotHistoryStore: PotHistoryStore {
    private var store: [String: [PotReading]]
    init(_ store: [String: [PotReading]] = [:]) { self.store = store }
    func readings(_ potID: String) -> [PotReading] { store[potID] ?? [] }
    func record(_ reading: PotReading, potID: String) {
        let day = Calendar.current.startOfDay(for: reading.day)
        store[potID] = (store[potID] ?? []).filter { $0.day != day } + [PotReading(day: day, value: reading.value)]
    }
}
