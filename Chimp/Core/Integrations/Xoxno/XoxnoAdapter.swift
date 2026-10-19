import Foundation
import stellarsdk

/// L'état du marché XOXNO d'un actif, en unités on-chain : ce qui est déposé, prêté, l'argent disponible, la limite
/// d'utilisation, les drapeaux et le plafond du profil de risque. Lu par `get_sync_data` (réserve), `get_spoke_asset` et
/// `get_spoke_usage` (contrôleur). Vérifié le 2026-10-16 contre `get_supplied_amount` / `get_borrowed_amount` (à une unité
/// près).
struct XoxnoMarketState: Equatable, Sendable {
    /// Déposé et prêté, au dernier index enregistré (déposé arrondi vers le bas, prêté vers le haut, comme le contrat).
    let supplied: Int128
    let borrowed: Int128
    /// L'argent réellement dans la réserve.
    let cash: Int128
    /// Limite d'utilisation (RAY, 10^27 = 100 %) : un retrait qui la dépasserait est refusé (erreur #127).
    let maxUtilization: Int128
    /// Profil de risque : `paused` bloque tout (retraits compris), `frozen` bloque les dépôts.
    let paused: Bool
    let frozen: Bool
    /// Plafond de dépôt du profil de risque, et ce qui y est déjà déposé.
    let supplyCap: Int128
    let suppliedInSpoke: Int128

    static let ray: Int128 = 1_000_000_000_000_000_000_000_000_000

    /// Ce que le marché laisse retirer maintenant, toutes positions confondues : le plus petit de l'argent disponible et de
    /// `déposé − prêté ÷ limite` (au-delà, l'utilisation dépasserait la limite). Une marge couvre les intérêts courus
    /// depuis le dernier index (1 % de ce qui est prêté) : le retrait proposé passe encore au moment de la signature.
    var marketWithdrawable: Int128 {
        // Revue de sécurité F8 : des valeurs négatives ou extrêmes (RPC menteur) donnent 0, jamais un plantage.
        guard maxUtilization > 0, supplied >= 0, borrowed >= 0, cash >= 0 else { return 0 }
        let byUtilization: Int128
        if borrowed == 0 || maxUtilization >= Self.ray {
            byUtilization = supplied
        } else {
            guard let floor = XoxnoMath.mulDiv(borrowed, Self.ray, maxUtilization, roundUp: true) else { return 0 }
            byUtilization = supplied - floor
        }
        let margin = borrowed / 100 + 1
        let limit = min(cash, byUtilization)
        return limit > margin ? limit - margin : 0
    }

    /// Ce qu'une position de `value` peut retirer maintenant.
    func withdrawable(position value: Int128) -> Int128 {
        max(0, min(value, marketWithdrawable))
    }

    /// Ce qu'on peut encore déposer avant le plafond.
    var remainingCap: Int128 {
        guard supplyCap > 0, suppliedInSpoke >= 0, supplyCap > suppliedInSpoke else { return 0 }
        return supplyCap - suppliedInSpoke
    }
}

/// Une position XOXNO d'un tiroir : le numéro de son jeton et ce qu'on en sait.
struct XoxnoPosition: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// Lue : valeur dans l'actif du marché, profil de risque, dette éventuelle (jamais créée par l'app : une position
        /// avec dette est montrée sans action possible).
        case live(value: Int128, spokeID: UInt32, hasDebt: Bool)
        /// Les données de la position ont expiré sur la chaîne (durée de vie des entrées Soroban) : elle doit être
        /// renouvelée avant d'être lue ou déplacée. L'argent est toujours là (décision de Barth du 2026-10-16).
        case needsRenewal
    }

    let accountID: UInt64
    let holder: String
    let status: Status

    var value: Int128? {
        if case .live(let value, _, _) = status { value } else { nil }
    }

    var canMove: Bool {
        if case .live(_, _, let hasDebt) = status { return !hasDebt }
        return false
    }
}

/// Les entrées d'une position et leur durée de vie (`getLedgerEntries`), derrière un protocole pour les tests.
protocol XoxnoLedgerReading {
    func latestLedger() async throws -> UInt32
    /// Clé (base64) → ledger jusqu'auquel l'entrée vit ; une entrée absente n'apparaît pas.
    func liveUntil(_ base64Keys: [String]) async throws -> [String: UInt32]
}

struct SorobanXoxnoLedger: XoxnoLedgerReading {
    let client: SorobanClient

    func latestLedger() async throws -> UInt32 { try await client.latestLedger() }

    func liveUntil(_ base64Keys: [String]) async throws -> [String: UInt32] {
        var out: [String: UInt32] = [:]
        for entry in try await client.ledgerEntries(base64Keys) {
            out[entry.key] = UInt32(clamping: entry.liveUntilLedgerSeq ?? 0)
        }
        return out
    }
}

/// XOXNO comme lieu de dépôt (phase 7) : USDC seulement, **jamais d'emprunt**, uniquement par appels de contrats, sans clé
/// d'API. Positions retrouvées **sur la chaîne** à partir du tiroir (jeton de position OpenZeppelin « Enumerable » :
/// `balance`, `get_owner_token_id`), jamais seulement sur le téléphone. **Absent de `reference/`.**
final class XoxnoAdapter {
    let market: IntegrationConfig.Xoxno
    let asset: IntegrationAsset
    private let reader: ContractReading
    private let ledger: XoxnoLedgerReading

    init(market: IntegrationConfig.Xoxno, asset: IntegrationAsset, reader: ContractReading, ledger: XoxnoLedgerReading) {
        self.market = market
        self.asset = asset
        self.reader = reader
        self.ledger = ledger
    }

    private func key() throws -> SCValXDR {
        try XoxnoCalls.hubAssetKey(asset: asset.contract, hubID: market.hubID)
    }

    // MARK: Marché

    func state() async throws -> XoxnoMarketState {
        let sync = try await read(market.pool, "get_sync_data", [try key()])
        let flags = try await read(market.controller, "get_spoke_asset", [.u32(market.spokeID), try key()])
        let usage = try await read(market.controller, "get_spoke_usage", [.u32(market.spokeID), try key()])
        return try Self.state(sync: sync, spokeAsset: flags, spokeUsage: usage, asset: asset.contract)
    }

    // MARK: Positions

    /// Les positions de `holder` : chaque jeton qu'il détient, lu ou marqué « à renouveler ». Une panne réseau remonte
    /// (jamais « pas de position »).
    func positions(holder: String) async throws -> [XoxnoPosition] {
        let count = try Self.u32(try await read(market.positionNFT, "balance", [try ContractArgument.address(holder)]), "balance")
        guard count > 0 else { return [] }
        var ids: [UInt64] = []
        for index in 0..<min(count, 20) {
            let id = try Self.u32(try await read(market.positionNFT, "get_owner_token_id", [try ContractArgument.address(holder), .u32(index)]), "token id")
            ids.append(UInt64(id))
        }
        let latest = try await ledger.latestLedger()
        let keys = try ids.flatMap { id in [try Self.entryKey("AccountMeta", id: id, controller: market.controller), try Self.entryKey("SupplyPositions", id: id, controller: market.controller)] }
        let lives = try await ledger.liveUntil(keys)
        var out: [XoxnoPosition] = []
        for id in ids {
            let meta = lives[try Self.entryKey("AccountMeta", id: id, controller: market.controller)]
            let supply = lives[try Self.entryKey("SupplyPositions", id: id, controller: market.controller)]
            guard Self.isLive(meta: meta, supply: supply, latest: latest) else {
                out.append(XoxnoPosition(accountID: id, holder: holder, status: .needsRenewal))
                continue
            }
            let attributes = try await read(market.controller, "get_account_attributes", [.u64(id)])
            guard let spoke = Self.field("spoke_id", in: attributes).flatMap(Self.u32Value) else {
                throw ContractArgument.ArgumentError.malformed("account attributes are malformed")
            }
            let value = try Self.int128(try await read(market.controller, "get_collateral_amount", [.u64(id), try key()]), "collateral")
            let debt = try Self.int128(try await read(market.controller, "get_total_borrow_usd", [.u64(id)]), "debt")
            out.append(XoxnoPosition(accountID: id, holder: holder, status: .live(value: value, spokeID: spoke, hasDebt: debt > 0)))
        }
        return out
    }

    /// Une position est lisible si son entrée `AccountMeta` vit encore, et `SupplyPositions` aussi quand elle existe.
    /// Le tiroir détient le jeton mais l'entrée est absente ou expirée : la donnée a expiré (une position fermée brûle son
    /// jeton, elle n'est plus détenue).
    static func isLive(meta: UInt32?, supply: UInt32?, latest: UInt32) -> Bool {
        guard let meta, meta >= latest else { return false }
        if let supply, supply < latest { return false }
        return true
    }

    /// Clé (base64) d'une entrée persistante du contrôleur : `ControllerKey::AccountMeta(id)` ou `SupplyPositions(id)`.
    static func entryKey(_ name: String, id: UInt64, controller: String) throws -> String {
        let key = LedgerKeyXDR.contractData(LedgerKeyContractDataXDR(
            contract: try SCAddressXDR(contractId: controller), key: .vec([.symbol(name), .u64(id)]), durability: .persistent
        ))
        guard let encoded = key.xdrEncoded else { throw StellarError.invalidResponse("could not encode ledger key") }
        return encoded
    }

    // MARK: Appels

    /// Dépôt, **toujours dans une nouvelle position** (`account_id = 0`). Revue de sécurité F4 (2026-10-16) : le contrôleur
    /// laisse un tiers alimenter n'importe quelle position existante (« Third parties may only top up existing supply
    /// positions »), et la liste des positions d'un tiroir vient du RPC : réutiliser un numéro lu pourrait envoyer le dépôt
    /// dans la position d'un autre. Vérifier le propriétaire n'aiderait pas, la réponse viendrait du même RPC.
    func supplyCall(from holder: String, units: TokenAmount) throws -> ContractCall {
        guard units.units > 0 else { throw YieldError.amountTooSmall }
        return try XoxnoCalls.supply(market: market, asset: asset.contract, from: holder, accountID: 0, units: units.units)
    }

    /// Retrait de `units` (ou de tout, `all`) de la position.
    func withdrawCall(position: XoxnoPosition, units: TokenAmount, all: Bool) throws -> ContractCall {
        guard position.canMove else { throw YieldError.vaultUnavailable }
        guard all || units.units > 0 else { throw YieldError.amountTooSmall }
        return try XoxnoCalls.withdraw(market: market, asset: asset.contract, from: position.holder, accountID: position.accountID, units: all ? 0 : units.units)
    }

    func authShape() -> any AuthShape {
        XoxnoAuthShape(market: market, asset: asset.contract)
    }

    func terms(of call: ContractCall, allValue: TokenAmount? = nil) throws -> SignedTerms {
        try XoxnoCalls.terms(of: call, market: market, asset: asset.contract, allValue: allValue?.units)
    }

    // MARK: Réponses

    static func state(sync: SCValXDR, spokeAsset: SCValXDR, spokeUsage: SCValXDR, asset: String) throws -> XoxnoMarketState {
        let malformed = ContractArgument.ArgumentError.malformed("XOXNO market data is malformed")
        guard let params = field("params", in: sync), let state = field("state", in: sync),
              field("asset_id", in: params)?.address.flatMap({ try? $0.toStrKey() }) == asset,
              let decimals = field("asset_decimals", in: params).flatMap({ u32Value($0) }), decimals <= 27,
              let maxUtilization = field("max_utilization", in: params).flatMap({ ContractArgument.int128($0) }),
              let suppliedScaled = field("supplied", in: state).flatMap({ ContractArgument.int128($0) }),
              let supplyIndex = field("supply_index", in: state).flatMap({ ContractArgument.int128($0) }),
              let borrowedScaled = field("borrowed", in: state).flatMap({ ContractArgument.int128($0) }),
              let borrowIndex = field("borrow_index", in: state).flatMap({ ContractArgument.int128($0) }),
              let cash = field("cash", in: state).flatMap({ ContractArgument.int128($0) }),
              case .bool(let paused) = field("paused", in: spokeAsset) ?? .void,
              case .bool(let frozen) = field("frozen", in: spokeAsset) ?? .void,
              let cap = field("supply_cap", in: spokeAsset).flatMap({ ContractArgument.int128($0) }),
              let spokeScaled = field("supplied_scaled_ray", in: spokeUsage).flatMap({ ContractArgument.int128($0) }) else { throw malformed }
        // Montants « RAY » (10^27 par jeton) × index (RAY) → unités de l'actif (10^décimales par jeton).
        var perUnit: Int128 = 1
        for _ in 0..<(27 - Int(decimals)) { perUnit *= 10 }
        let ray = XoxnoMarketState.ray
        guard let suppliedRay = XoxnoMath.mulDiv(suppliedScaled, supplyIndex, ray, roundUp: false),
              let borrowedRay = XoxnoMath.mulDiv(borrowedScaled, borrowIndex, ray, roundUp: true),
              let spokeRay = XoxnoMath.mulDiv(spokeScaled, supplyIndex, ray, roundUp: false) else { throw malformed }
        // Prêté arrondi vers le haut sans addition qui pourrait dépasser (revue de sécurité F8).
        let borrowedUnits = borrowedRay / perUnit + (borrowedRay % perUnit > 0 ? 1 : 0)
        return XoxnoMarketState(
            supplied: suppliedRay / perUnit, borrowed: borrowedUnits, cash: cash,
            maxUtilization: maxUtilization, paused: paused, frozen: frozen, supplyCap: cap, suppliedInSpoke: spokeRay / perUnit
        )
    }

    static func field(_ name: String, in value: SCValXDR) -> SCValXDR? {
        value.map?.first { $0.key.symbol == name }?.val
    }

    static func u32Value(_ value: SCValXDR) -> UInt32? {
        if case .u32(let number) = value { number } else { nil }
    }

    private static func u32(_ value: SCValXDR, _ what: String) throws -> UInt32 {
        guard let number = u32Value(value) else { throw ContractArgument.ArgumentError.malformed("\(what) is not a u32") }
        return number
    }

    private static func int128(_ value: SCValXDR, _ what: String) throws -> Int128 {
        guard let amount = ContractArgument.int128(value) else { throw ContractArgument.ArgumentError.malformed("\(what) is not an i128") }
        return amount
    }

    /// Les refus du contrôleur et de la réserve (`common/src/errors.rs`) traduits ; `nil` : autre erreur, telle quelle.
    static func yieldError(for error: Error) -> YieldError? {
        let message: String
        switch error {
        case StellarError.simulationFailed(let text), StellarError.submitFailed(let text): message = text
        case StellarError.transactionFailed(_, let detail): message = detail
        default: return nil
        }
        let codes: [(Int, YieldError)] = [
            (112, .notEnoughLiquidity), (127, .notEnoughLiquidity),             // InsufficientLiquidity, UtilizationAboveMax
            (315, .vaultUnavailable), (316, .vaultUnavailable), (1000, .vaultUnavailable), // pause, gel, pause générale
            (311, .capReached),                                                 // SpokeSupplyCapReached
            (13, .notEnoughShares), (24, .notEnoughShares), (110, .notEnoughShares), (121, .notEnoughShares),
            (14, .amountTooSmall), (49, .amountTooSmall), (51, .amountTooSmall),
            (10, .insufficientBalance),                                         // le SAC : solde insuffisant
        ]
        for (code, yieldError) in codes
        where message.range(of: #"Error\(Contract,\s*#\#(code)\)"#, options: .regularExpression) != nil {
            return yieldError
        }
        return nil
    }

    // MARK: Réseau

    private func read(_ contract: String, _ function: String, _ arguments: [SCValXDR]) async throws -> SCValXDR {
        do {
            return try await reader.readValue(contract: contract, function: function, arguments: arguments)
        } catch {
            throw Self.yieldError(for: error) ?? error
        }
    }
}

/// `a × b ÷ c` sans débordement (produit sur 256 bits), pour des valeurs positives ; `nil` si le résultat ne tient pas.
enum XoxnoMath {
    static func mulDiv(_ a: Int128, _ b: Int128, _ c: Int128, roundUp: Bool) -> Int128? {
        guard a >= 0, b >= 0, c > 0 else { return nil }
        let divisor = UInt128(c)
        let product = UInt128(a).multipliedFullWidth(by: UInt128(b))
        guard product.high < divisor else { return nil }
        let (quotient, remainder) = divisor.dividingFullWidth(product)
        let rounded = roundUp && remainder > 0 ? quotient + 1 : quotient
        guard rounded <= UInt128(Int128.max) else { return nil }
        return Int128(rounded)
    }
}
