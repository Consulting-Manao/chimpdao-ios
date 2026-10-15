import Foundation
import stellarsdk

/// DeFindex comme protocole de rendement (D1) : portage de `vaultDeposit`, `vaultWithdraw`, `discoverDefindexPositions` et
/// `loadDefindexDetail` (`reference/terminal/src/modules/earn/defindex/`), uniquement par appels de contrats.
///
/// - Lecture : `get_assets` (l'actif du vault, vérifié avant tout mouvement, `assertVaultAsset`), `balance(holder)` (parts),
///   `get_asset_amounts_per_shares(parts)` (valeur), `fetch_total_managed_funds` et `total_supply` (fonds gérés, valeur
///   d'une part).
/// - Dépôt : `deposit([montant], [montant], from, true)`, forme `DeFindexAuthShape` (une prise : le montant, vers le vault).
/// - Retrait : `withdraw(parts, [minimum], from)` ; parts au prorata (`dfAmountFor`), tout par parts pour « All »,
///   minimum = valeur attendue − 0,5 % (`VAULT_SLIPPAGE_BPS`). Ne prend rien : vérifié par simulation sur testnet le
///   2026-10-15 (lot du router dépôt puis retrait, Main account `CCDO6J…DDYB`).
///
/// Ajouts à l'iPhone : chaque valeur lue est confrontée aux fonds du vault (vraisemblance, comme le swap) ; montants en
/// `TokenAmount` à travers les fonctions `async` ; refus du vault traduits en `YieldError`.
final class DeFindexAdapter: YieldAdapter {
    let id = "defindex"
    let name = "DeFindex"
    let category = "Vaults"
    let openActions = [YieldAction(id: "deposit", label: "Deposit", maxFrom: .balance)]
    let manageActions = [
        YieldAction(id: "deposit", label: "Deposit", maxFrom: .balance),
        YieldAction(id: "withdraw", label: "Withdraw", maxFrom: .position),
    ]

    /// 0,5 % (`VAULT_SLIPPAGE_BPS`) : la liquidation côté stratégie (Blend) peut rogner un peu.
    static let withdrawSlippageBasisPoints = 50

    private let vaults: [YieldVenue]
    private let reader: ContractReading
    /// Vaults dont l'actif a été vérifié (`verified` du terminal).
    private var verifiedVaults: Set<String> = []

    /// `vaults` : la liste choisie dans `Config/` (jamais toute l'usine), avec le SAC de leur actif.
    init(vaults: [YieldVenue], reader: ContractReading) {
        self.vaults = vaults
        self.reader = reader
    }

    func venues() -> [YieldVenue] { vaults }

    // MARK: Lecture

    /// L'état du vault : fonds gérés (idle + investis) et parts émises. Une part vaut `totalManaged / totalSupply`.
    struct VaultState: Equatable, Sendable {
        let totalManaged: Int128
        let invested: Int128
        let totalSupply: Int128

        /// Parts que `amount` achète au prix du moment (affichage : « about N shares »), arrondi vers le bas.
        func shares(for amount: Int128) -> Int128 {
            guard totalManaged > 0, totalSupply > 0, amount > 0 else { return 0 }
            let (product, overflow) = amount.multipliedReportingOverflow(by: totalSupply)
            return overflow ? 0 : product / totalManaged
        }

        /// Valeur de `shares` au prix des fonds gérés, arrondi vers le bas.
        func value(of shares: Int128) -> Int128 {
            guard totalManaged > 0, totalSupply > 0, shares > 0 else { return 0 }
            let (product, overflow) = shares.multipliedReportingOverflow(by: totalManaged)
            return overflow ? 0 : product / totalSupply
        }
    }

    func state(of venue: YieldVenue) async throws -> VaultState {
        try await verifyAsset(of: venue)
        let funds = try await read(venue.id, "fetch_total_managed_funds", [])
        let supply = try await read(venue.id, "total_supply", [])
        return try Self.state(funds: funds, supply: supply, asset: venue.asset.contract)
    }

    func discover(holder: String) async throws -> [YieldPosition] {
        var out: [YieldPosition] = []
        for venue in vaults {
            // Un solde illisible fait échouer la découverte (jamais « pas de position ») : `discoverDefindexPositions`.
            let shares = try Self.int128(try await read(venue.id, "balance", [try ContractArgument.address(holder)]), "balance")
            guard shares > 0 else { continue }
            let value = try await valueOf(shares: TokenAmount(shares), in: venue)
            out.append(YieldPosition(protocolID: id, venueID: venue.id, holder: holder, shares: shares, value: value))
        }
        return out
    }

    /// `get_asset_amounts_per_shares(parts)`, vérifié contre les fonds du vault : une valeur plus grande que le vault
    /// entier, ou éloignée de `parts × fonds / parts émises`, est refusée (`YieldError.implausibleValue`).
    func valueOf(shares: TokenAmount, in venue: YieldVenue) async throws -> Int128 {
        let state = try await state(of: venue)
        let value = try Self.firstAmount(try await read(venue.id, "get_asset_amounts_per_shares", [ContractArgument.i128(shares.units)]))
        guard Self.isPlausible(value: value, shares: shares.units, state: state) else { throw YieldError.implausibleValue }
        return value
    }

    // MARK: Appels

    func depositCall(venue: YieldVenue, amount: TokenAmount, authorizer: String) async throws -> ContractCall {
        try await verifyAsset(of: venue)
        guard amount.units > 0 else { throw YieldError.amountTooSmall }
        return try DeFindexCalls.deposit(vault: venue.id, from: authorizer, units: amount.units)
    }

    func withdrawCall(position: YieldPosition, amount: TokenAmount, all: Bool) async throws -> ContractCall {
        guard let venue = vaults.first(where: { $0.id == position.venueID }) else { throw YieldError.unknownVault }
        try await verifyAsset(of: venue)
        // Parts et valeur relues juste avant (jamais celles de l'écran) : le vault grandit à chaque ledger.
        let shareBalance = try Self.int128(
            try await read(venue.id, "balance", [try ContractArgument.address(position.holder)]), "balance"
        )
        guard shareBalance > 0 else { throw YieldError.notEnoughShares }
        let total = try await valueOf(shares: TokenAmount(shareBalance), in: venue)
        let shares = all ? shareBalance : Self.shares(
            balance: shareBalance, wanted: amount.units, total: total, dust: Self.dust(total: total)
        )
        guard shares > 0 else { throw YieldError.amountTooSmall }
        let expected = shares == shareBalance ? total : try await valueOf(shares: TokenAmount(shares), in: venue)
        let minimum = Slippage.minimum(of: expected, basisPoints: Self.withdrawSlippageBasisPoints)
        guard minimum > 0 else { throw YieldError.amountTooSmall }
        return try DeFindexCalls.withdraw(vault: venue.id, from: position.holder, shares: shares, minimumOut: minimum)
    }

    func authShape() -> any AuthShape {
        DeFindexAuthShape(underlying: Dictionary(uniqueKeysWithValues: vaults.map { ($0.id, $0.asset.contract) }))
    }

    func terms(of call: ContractCall) throws -> SignedTerms {
        guard let venue = vaults.first(where: { $0.id == call.contract }) else { throw YieldError.unknownVault }
        return try DeFindexCalls.terms(of: call, underlying: venue.asset.contract)
    }

    // MARK: Règles (sans réseau)

    /// `dfAmountFor` : parts pour retirer `wanted` d'une position de `total`, arrondi vers le bas (jamais trop). À moins de
    /// `dust` du total, toute la position (sinon « tout retirer » laisserait de la poussière pour toujours).
    static func shares(balance: Int128, wanted: Int128, total: Int128, dust: Int128) -> Int128 {
        guard balance > 0, wanted > 0, total > 0 else { return 0 }
        if total - wanted <= dust { return balance }
        let (product, overflow) = balance.multipliedReportingOverflow(by: wanted)
        return overflow ? 0 : product / total
    }

    /// La marge du « tout retirer » : un quantum du pavé (XLM : 7 décimales, 1 unité) ou 1/100 000 de la position, le plus
    /// grand (le terminal : troncature de l'affichage et rendement accumulé depuis la lecture).
    static func dust(total: Int128) -> Int128 {
        max(1, total / 100_000)
    }

    /// Une valeur lue est vraisemblable si elle n'excède pas les fonds du vault et reste à 1 pb (plus 1 unité) de
    /// `parts × fonds / parts émises`.
    static func isPlausible(value: Int128, shares: Int128, state: VaultState) -> Bool {
        guard value >= 0, shares >= 0, value <= state.totalManaged else { return false }
        let expected = state.value(of: shares)
        let tolerance = expected / 10_000 + 1
        return abs(value - expected) <= tolerance
    }

    // MARK: Réponses

    static func state(funds: SCValXDR, supply: SCValXDR, asset: String) throws -> VaultState {
        guard let rows = funds.vec, let row = rows.first(where: { field("asset", in: $0).flatMap { try? $0.address?.toStrKey() } == asset }),
              let total = field("total_amount", in: row).flatMap(ContractArgument.int128),
              let invested = field("invested_amount", in: row).flatMap(ContractArgument.int128) else {
            throw ContractArgument.ArgumentError.malformed("total managed funds are malformed")
        }
        return VaultState(totalManaged: total, invested: invested, totalSupply: try int128(supply, "total_supply"))
    }

    /// Le SAC déclaré par `get_assets` (premier actif).
    static func underlying(_ value: SCValXDR) throws -> String {
        guard let first = value.vec?.first, let address = field("address", in: first).flatMap({ try? $0.address?.toStrKey() }) else {
            throw ContractArgument.ArgumentError.malformed("this vault does not declare its asset")
        }
        return address
    }

    /// Le premier montant d'un `Vec<i128>` (`get_asset_amounts_per_shares`, montants retirés).
    static func firstAmount(_ value: SCValXDR) throws -> Int128 {
        guard let first = value.vec?.first, let amount = ContractArgument.int128(first) else {
            throw ContractArgument.ArgumentError.malformed("amounts are not a list of i128")
        }
        return amount
    }

    private static func int128(_ value: SCValXDR, _ what: String) throws -> Int128 {
        guard let amount = ContractArgument.int128(value) else { throw ContractArgument.ArgumentError.malformed("\(what) is not an i128") }
        return amount
    }

    private static func field(_ name: String, in value: SCValXDR) -> SCValXDR? {
        value.map?.first { $0.key.symbol == name }?.val
    }

    // MARK: Réseau

    private func read(_ contract: String, _ function: String, _ arguments: [SCValXDR]) async throws -> SCValXDR {
        do {
            return try await reader.readValue(contract: contract, function: function, arguments: arguments)
        } catch {
            throw Self.yieldError(for: error) ?? error
        }
    }

    /// `assertVaultAsset` : le vault tient bien l'actif de `Config/`, une fois par session.
    private func verifyAsset(of venue: YieldVenue) async throws {
        guard !verifiedVaults.contains(venue.id) else { return }
        guard try Self.underlying(try await read(venue.id, "get_assets", [])) == venue.asset.contract else {
            throw YieldError.wrongAsset
        }
        verifiedVaults.insert(venue.id)
    }

    /// Les refus du vault (spécification lue sur testnet) et du jeton traduits. `nil` : autre erreur, telle quelle.
    static func yieldError(for error: Error) -> YieldError? {
        let message: String
        switch error {
        case StellarError.simulationFailed(let text), StellarError.submitFailed(let text): message = text
        case StellarError.transactionFailed(_, let detail): message = detail
        default: return nil
        }
        let codes: [(Int, YieldError)] = [
            (160, .belowMinimum),                                               // InsufficientOutputAmount
            (111, .notEnoughShares), (124, .notEnoughShares),                   // InsufficientBalance, AmountOverTotalSupply
            (117, .amountTooSmall), (110, .amountTooSmall),                     // InsufficientAmount, AmountNotAllowed
            (114, .notEnoughLiquidity), (128, .notEnoughLiquidity),             // InsufficientManagedFunds, UnwindMoreThanAvailable
            (141, .vaultUnavailable), (144, .vaultUnavailable), (142, .vaultUnavailable), (143, .vaultUnavailable), (100, .vaultUnavailable),
            (10, .insufficientBalance),                                         // le SAC : solde insuffisant
        ]
        for (code, yieldError) in codes
        where message.range(of: #"Error\(Contract,\s*#\#(code)\)"#, options: .regularExpression) != nil {
            return yieldError
        }
        return nil
    }
}

/// Pourquoi un dépôt ou un retrait ne peut pas se faire, dit simplement (D1).
enum YieldError: Error, Equatable, LocalizedError {
    /// Pas assez de l'actif dans le tiroir.
    case insufficientBalance
    /// Plus de parts que la position n'en a.
    case notEnoughShares
    /// Montant nul ou trop petit pour le vault.
    case amountTooSmall
    /// Le vault rendrait moins que le minimum signé.
    case belowMinimum
    /// Le vault ne peut pas rendre ce montant maintenant (fonds prêtés).
    case notEnoughLiquidity
    /// Stratégie en pause ou en erreur.
    case vaultUnavailable
    /// Une valeur lue n'est pas vraisemblable : rien n'est affiché ni signé.
    case implausibleValue
    /// Le vault ne tient pas l'actif attendu (erreur de configuration).
    case wrongAsset
    /// Vault absent de `Config/`.
    case unknownVault

    var errorDescription: String? {
        switch self {
        case .insufficientBalance: "Not enough in this drawer."
        case .notEnoughShares: "The position doesn't hold that much."
        case .amountTooSmall: "The amount is too small for the vault."
        case .belowMinimum: "The vault would pay back less than the minimum you agreed to."
        case .notEnoughLiquidity: "The vault can't pay that much back right now."
        case .vaultUnavailable: "The vault is unavailable right now."
        case .implausibleValue: "The vault's numbers don't look right."
        case .wrongAsset: "This vault holds a different asset than this app."
        case .unknownVault: "This vault isn't one the app knows."
        }
    }
}
