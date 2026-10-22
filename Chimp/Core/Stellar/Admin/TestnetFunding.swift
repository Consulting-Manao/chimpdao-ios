#if CHIMP_ADMIN
import Foundation
import stellarsdk

/// Argent de test sur **testnet**, mode admin uniquement. Portage fidèle de `chain.fund` et `fundFromAdmin`
/// (`reference/terminal/src/chain/stellar.ts`) : une adresse G est financée par friendbot ; une adresse C (Main account,
/// Pocket) reçoit 1000 XLM de testnet par un `transfer` du SAC XLM, signé et payé par la clé admin. L'admin est d'abord
/// rechargé par friendbot s'il a moins de 2000 XLM. Aucune clé n'est créée : il n'y a que l'admin.
protocol TestnetFunding {
    /// G → friendbot ; C → `units` (en stroops) de XLM depuis l'admin. Renvoie le hash de la transaction de l'admin
    /// (`nil` pour friendbot).
    @discardableResult func fund(_ address: String, units: UInt64) async throws -> String?
    /// « Send test money » (Chimp Admin, onglet Money) : `units` depuis l'admin vers une adresse C, ou vers un compte G
    /// déjà ouvert. Un compte G pas encore ouvert sur le réseau est ouvert par friendbot (10 000 XLM, montant imposé).
    func send(_ address: String, units: UInt64) async throws -> TestMoneySend
}

/// Résultat de `send`.
enum TestMoneySend: Equatable {
    /// `transfer` du montant demandé, depuis l'admin (hash de la transaction).
    case sent(hash: String)
    /// Compte G inconnu du réseau : friendbot l'a ouvert avec 10 000 XLM de testnet (le montant demandé ne compte pas).
    case openedByFriendbot
}

extension TestnetFunding {
    /// « Testnet money » : 1000 XLM (`FUND_STROOPS` du terminal).
    @discardableResult func fund(_ address: String) async throws -> String? {
        try await fund(address, units: TestnetFunder.fundUnits)
    }
}

/// Ce que le financement demande au réseau (faux dans les tests).
protocol FundingNetwork {
    /// Solde XLM d'un compte G lu sur Horizon (`horizon.loadAccount`).
    func nativeBalance(of account: String) async throws -> Decimal
    /// Un appel à friendbot pour cette adresse ; lève `FundingError.friendbot` si la réponse n'est pas un succès.
    func friendbot(_ address: String) async throws
    /// Construit, prépare (simulation), signe par l'admin et envoie le `transfer` XLM, puis attend la confirmation.
    func transferXLM(from admin: KeyPair, to address: String, units: UInt64) async throws -> String
}

enum FundingError: Error, Equatable, LocalizedError {
    /// Pas de clé admin dans le trousseau (« Funding a contract address needs the admin key »).
    case noAdminKey
    /// Ni une adresse G ni une adresse C (« Fund needs a G-address or a chip C-address »).
    case unsupportedAddress
    /// Friendbot a refusé ou n'a pas répondu (texte du dernier essai).
    case friendbot(String)

    var errorDescription: String? {
        switch self {
        case .noAdminKey: "Funding a contract address needs the admin key: save it in the admin panel first."
        case .unsupportedAddress: "Fund needs a G-address or a C-address."
        case .friendbot(let detail): detail
        }
    }
}

struct TestnetFunder: TestnetFunding {
    /// `FUND_STROOPS` : 1000 XLM.
    static let fundUnits: UInt64 = 10_000_000_000
    /// `FUND_FLOOR_XLM` : l'admin est rechargé en dessous de deux recharges, pour ne jamais tomber à sec en cours de lot.
    static let adminFloor: Decimal = 2_000
    /// Friendbot flanche sous la charge : 4 essais, pauses de 1, 2, 3 puis 4 s.
    static let friendbotAttempts = 4

    let keyStore: AdminKeyStore
    let network: FundingNetwork
    var sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    func fund(_ address: String, units: UInt64) async throws -> String? {
        if (try? KeyPair(accountId: address)) != nil {
            try await fundG(address)
            return nil
        }
        guard address.hasPrefix("C"), (try? SCAddressXDR(contractId: address)) != nil else {
            throw FundingError.unsupportedAddress
        }
        return try await fundFromAdmin(address, units: units)
    }

    func send(_ address: String, units: UInt64) async throws -> TestMoneySend {
        if (try? KeyPair(accountId: address)) != nil {
            // Un compte G doit exister pour recevoir un `transfer` : sinon friendbot l'ouvre (Horizon ne le connaît pas).
            guard (try? await network.nativeBalance(of: address)) != nil else {
                try await fundG(address)
                return .openedByFriendbot
            }
            return .sent(hash: try await fundFromAdmin(address, units: units))
        }
        guard address.hasPrefix("C"), (try? SCAddressXDR(contractId: address)) != nil else {
            throw FundingError.unsupportedAddress
        }
        return .sent(hash: try await fundFromAdmin(address, units: units))
    }

    /// `fundG` : friendbot, avec quelques nouvelles tentatives.
    private func fundG(_ address: String) async throws {
        var last = ""
        for attempt in 0..<Self.friendbotAttempts {
            do {
                try await network.friendbot(address)
                return
            } catch {
                last = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
            try await sleep(.seconds(attempt + 1))
        }
        throw FundingError.friendbot(last.isEmpty ? "Friendbot failed" : last)
    }

    /// `fundFromAdmin` : recharge de l’admin si besoin, puis `transfer` du montant demandé, signé par l’admin.
    private func fundFromAdmin(_ address: String, units: UInt64) async throws -> String {
        guard let admin = try keyStore.keyPair() else { throw FundingError.noAdminKey }
        // Solde illisible (compte absent, panne) : 0, comme le terminal, donc une recharge par friendbot.
        let held = (try? await network.nativeBalance(of: admin.accountId)) ?? 0
        if held < Self.adminFloor { try await fundG(admin.accountId) }
        return try await network.transferXLM(from: admin, to: address, units: units)
    }
}

/// `FundingNetwork` sur testnet : Horizon, friendbot et RPC de la configuration. Refuse tout autre réseau.
struct ChainFundingNetwork: FundingNetwork {
    let config: ChimpNetworkConfig
    private let client: SorobanClient
    private let friendbotURL: URL

    init(config: ChimpNetworkConfig) throws {
        try CardEnrolment.requireTestnet(config)
        guard let friendbot = config.endpoints.friendbot else { throw CardEnrolmentError.notTestnet }
        self.config = config
        client = SorobanClient(config: config)
        friendbotURL = friendbot
    }

    func nativeBalance(of account: String) async throws -> Decimal {
        switch await StellarSDK(withHorizonUrl: config.endpoints.horizon.absoluteString).accounts.getAccountDetails(accountId: account) {
        case .success(let details):
            let native = details.balances.first { $0.assetType == AssetTypeAsString.NATIVE }
            return native.flatMap { Decimal(string: $0.balance) } ?? 0
        case .failure(let error):
            throw StellarError.rpc("\(error)")
        }
    }

    func friendbot(_ address: String) async throws {
        var components = URLComponents(url: friendbotURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "addr", value: address)]
        let (_, response) = try await URLSession.shared.data(from: components.url!)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw FundingError.friendbot("Friendbot refused: \(status)") }
    }

    func transferXLM(from admin: KeyPair, to address: String, units: UInt64) async throws -> String {
        let token = try SACClient.contractID(for: Asset(type: AssetType.ASSET_TYPE_NATIVE)!, network: client.network)
        let operation = try SACClient.transferOperation(token: token, from: admin.accountId, to: address, units: units)
        // `builderFor` : un `getAccount` neuf, puis `prepareTransaction` (simulation + assemblage), signature, envoi.
        let transaction = try client.singleOperation(source: try await client.account(admin.accountId), operation: operation)
        try client.assemble(transaction, with: try await client.simulate(transaction))
        try transaction.sign(keyPair: admin, network: client.network)
        return try await client.submitAndWait(transaction)
    }
}

/// Faux financement pour le simulateur : aucune requête réseau.
final class MockTestnetFunding: TestnetFunding {
    var delay: Duration = .milliseconds(600)
    var failing: Set<String> = []
    private(set) var funded: [String] = []

    init(failing: Set<String> = []) {
        self.failing = failing
    }

    func fund(_ address: String, units: UInt64) async throws -> String? {
        try await Task.sleep(for: delay)
        if failing.contains(address) { throw FundingError.friendbot("Friendbot refused: 502") }
        funded.append(address)
        return String(repeating: "0", count: 64)
    }

    /// Envois de `send` (adresse, montant en stroops).
    private(set) var sent: [(address: String, units: UInt64)] = []

    func send(_ address: String, units: UInt64) async throws -> TestMoneySend {
        try await Task.sleep(for: delay)
        if failing.contains(address) { throw FundingError.friendbot("Friendbot refused: 502") }
        sent.append((address, units))
        return .sent(hash: String(repeating: "0", count: 64))
    }
}
#endif
