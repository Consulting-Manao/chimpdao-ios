import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

// Mode admin (CHIMP_ADMIN) : absent de la Release, donc du schéma « Chimp Release Tests ».
#if CHIMP_ADMIN

/// Étape 5B : argent de test (mode admin, testnet). Portage de `chain.fund` / `fundFromAdmin` (`chain/stellar.ts`) et du
/// `FundBlock` (`Settings.tsx`). Vecteur XDR calculé avec `@stellar/stellar-sdk` 17.0.1.
@MainActor
struct TestnetFundingTests {
    private static let main = "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"
    private static let pocket = "CCGYGX2HBP464WZWXHHFOMS25CMIBKH3PUKOKRESOM3Z2W4UJRLLJ72Q"
    private static let admin = try! KeyPair.generateRandomKeyPair()

    private func funder(_ network: FakeFundingNetwork, withKey: Bool = true) -> (TestnetFunder, SleepRecorder) {
        let sleeps = SleepRecorder()
        var funder = TestnetFunder(
            keyStore: InMemoryAdminKeyStore(seed: withKey ? Self.admin.secretSeed : nil),
            network: network
        )
        funder.sleep = { sleeps.durations.append($0) }
        return (funder, sleeps)
    }

    // MARK: Opération `transfer`

    @Test("`transfer` de 1000 XLM, admin → Main account : opération identique au SDK JS")
    func transferOperationVector() throws {
        let token = try SACClient.contractID(for: Asset(type: AssetType.ASSET_TYPE_NATIVE)!, network: .testnet)
        #expect(token == "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC")
        let operation = try SACClient.transferOperation(
            token: token, from: "GBLWPGXVH47YGMODIUHZJ7FETRISFU3TB7JGADTRIMU36OLWJ7PYEZ6M", to: Self.main,
            units: TestnetFunder.fundUnits
        )
        let encoded = Data(try XDREncoder.encode(try operation.toXDR())).base64EncodedString()
        #expect(encoded == "AAAAAAAAABgAAAAAAAAAAdeSi3LCcDzP6vfrn/TvTVBKVai5efybRQ6iyEK00c5hAAAACHRyYW5zZmVyAAAAAwAAABIAAAAAAAAAAFdnmvU/P4Mxw0UPlPyknFEi03MP0mAOcUMpvzl2T9+CAAAAEgAAAAGG7yf2cZ81ZB/ZbEEJCf9nNzDsFZZDPxZBRNkhrPbokQAAAAoAAAAAAAAAAAAAAAJUC+QAAAAAAA==")
    }

    // MARK: fundFromAdmin

    @Test("Adresse C, admin à 2000 XLM ou plus : pas de friendbot, 1000 XLM (10 000 000 000 stroops) depuis l'admin")
    func fundsContractFromAdmin() async throws {
        let network = FakeFundingNetwork(adminBalance: 2000)
        let (funder, _) = funder(network)
        try await funder.fund(Self.pocket)
        #expect(network.friendbotCalls.isEmpty)
        #expect(network.transfers == [.init(from: Self.admin.accountId, to: Self.pocket, units: 10_000_000_000)])
    }

    @Test("Send test money : le montant demandé vers une adresse C ou un compte G ouvert ; un G inconnu est ouvert par friendbot")
    func sendTestMoney() async throws {
        let account = try KeyPair.generateRandomKeyPair().accountId
        let fresh = try KeyPair.generateRandomKeyPair().accountId
        let network = FakeFundingNetwork(adminBalance: 5000)
        network.openAccounts = [Self.admin.accountId, account]
        let (funder, _) = funder(network)
        #expect(try await funder.send(Self.pocket, units: 1_200_000_000) == .sent(hash: "hash"))
        #expect(try await funder.send(account, units: 50_000_000) == .sent(hash: "hash"))
        #expect(network.transfers == [
            .init(from: Self.admin.accountId, to: Self.pocket, units: 1_200_000_000),
            .init(from: Self.admin.accountId, to: account, units: 50_000_000),
        ])
        #expect(try await funder.send(fresh, units: 50_000_000) == .openedByFriendbot)
        #expect(network.friendbotCalls == [fresh] && network.transfers.count == 2, "Pas de transfert vers un compte G pas encore ouvert")
        await #expect(throws: FundingError.unsupportedAddress) { try await funder.send("SNOTANADDRESS", units: 1) }
    }

    @Test("Admin sous 2000 XLM : rechargé par friendbot, puis le transfert")
    func topsUpAdmin() async throws {
        let network = FakeFundingNetwork(adminBalance: Decimal(string: "1999.9999999")!)
        let (funder, _) = funder(network)
        try await funder.fund(Self.main)
        #expect(network.friendbotCalls == [Self.admin.accountId])
        #expect(network.transfers.map(\.to) == [Self.main])
    }

    @Test("Solde de l'admin illisible : compté 0, donc recharge (comme le terminal)")
    func unreadableBalanceMeansTopUp() async throws {
        let network = FakeFundingNetwork(adminBalance: nil)
        let (funder, _) = funder(network)
        try await funder.fund(Self.main)
        #expect(network.friendbotCalls == [Self.admin.accountId])
        #expect(network.transfers.count == 1)
    }

    @Test("Friendbot : 4 essais (pauses 1, 2, 3, 4 s), puis le dernier motif ; aucun transfert")
    func friendbotGivesUp() async {
        let network = FakeFundingNetwork(adminBalance: 0, friendbotFailures: 10)
        let (funder, sleeps) = funder(network)
        await #expect(throws: FundingError.friendbot("Friendbot refused: 502")) { try await funder.fund(Self.main) }
        #expect(network.friendbotCalls.count == 4)
        #expect(sleeps.durations == [.seconds(1), .seconds(2), .seconds(3), .seconds(4)])
        #expect(network.transfers.isEmpty)
    }

    @Test("Friendbot qui flanche deux fois puis répond : le transfert part")
    func friendbotRetries() async throws {
        let network = FakeFundingNetwork(adminBalance: 0, friendbotFailures: 2)
        let (funder, _) = funder(network)
        try await funder.fund(Self.main)
        #expect(network.friendbotCalls.count == 3)
        #expect(network.transfers.count == 1)
    }

    @Test("Adresse G : friendbot directement, sans clé admin")
    func fundsAccountWithFriendbot() async throws {
        let network = FakeFundingNetwork(adminBalance: 5000)
        let (funder, _) = funder(network, withKey: false)
        let account = try KeyPair.generateRandomKeyPair().accountId
        #expect(try await funder.fund(account) == nil)
        #expect(network.friendbotCalls == [account])
        #expect(network.transfers.isEmpty)
    }

    @Test("Adresse C sans clé admin, ou adresse invalide : erreur, rien n'est envoyé")
    func refusals() async {
        let network = FakeFundingNetwork(adminBalance: 5000)
        let (withoutKey, _) = funder(network, withKey: false)
        await #expect(throws: FundingError.noAdminKey) { try await withoutKey.fund(Self.main) }
        let (withKey, _) = funder(network)
        await #expect(throws: FundingError.unsupportedAddress) { try await withKey.fund("hello") }
        await #expect(throws: FundingError.unsupportedAddress) { try await withKey.fund("CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYA") }
        #expect(network.transfers.isEmpty)
        #expect(network.friendbotCalls.isEmpty)
    }

    @Test("Le financement refuse tout autre réseau que testnet")
    func testnetOnly() throws {
        _ = try ChainFundingNetwork(config: .testnet)
        let testnet = ChimpNetworkConfig.testnet
        let mainnet = ChimpNetworkConfig(
            network: .mainnet, passphrase: "Public Global Stellar Network ; September 2015",
            endpoints: testnet.endpoints, contracts: testnet.contracts, feeSignerURL: testnet.feeSignerURL,
            feePayer: testnet.feePayer, usdcIssuer: testnet.usdcIssuer, usdcFaucet: nil, features: .none
        )
        #expect(throws: CardEnrolmentError.notTestnet) { try ChainFundingNetwork(config: mainnet) }
    }

    // MARK: FundBlock

    private func session(cards: [SavedCard]) -> AppSession {
        var wallet = LocalWallet()
        wallet.account = SavedAccount(address: Self.main, cards: cards)
        return AppSession(store: InMemoryLocalWalletStore(wallet), config: .testnet)
    }

    private static let cardKey = MockChipReader.secp256k1Key
    private static let otherKey = MockChipReader.p256Key

    @Test("Destinations : le Main account, puis la Pocket de chaque carte du compte (mémorisée, sinon la factory)")
    func targets() async {
        let chain = FakeCardsChain(members: [Self.cardKey, Self.otherKey], pockets: [Self.otherKey: "COTHER"])
        let saved = SavedCard(publicKey: Self.cardKey.hex, chip: "infineon2Go", tokenID: 7, pocket: Self.pocket, name: "Banana", color: "banana")
        let model = AdminFundModel(session: session(cards: [saved]), chain: chain, funder: MockTestnetFunding())
        await model.loadTargets()
        #expect(model.targets.map(\.address) == [Self.main, Self.pocket, "COTHER"])
        #expect(model.targets.map(\.label) == ["Main account", "Banana's wallet", "Card's wallet"])
    }

    @Test("« Fund this account » : chaque adresse à son tour ; succès, ou « k/N funded — premier motif »")
    func fundMessages() async {
        let chain = FakeCardsChain(members: [Self.cardKey], pockets: [Self.cardKey: Self.pocket])
        let funding = MockTestnetFunding(failing: [Self.pocket])
        funding.delay = .zero
        let model = AdminFundModel(session: session(cards: []), chain: chain, funder: funding)
        await model.loadTargets()
        await model.fund()
        #expect(funding.funded == [Self.main])
        #expect(model.message == .failed("1/2 funded — Friendbot refused: 502"))

        funding.failing = []
        await model.fund()
        #expect(model.message == .ok("Funded 2 balances. Pull to refresh the Wallet."))
    }

    @Test("Sans compte sur le téléphone : rien à financer")
    func nothingToFund() async {
        let session = AppSession(store: InMemoryLocalWalletStore(), config: .testnet)
        let model = AdminFundModel(session: session, chain: FakeCardsChain(members: [], pockets: [:]), funder: MockTestnetFunding())
        await model.loadTargets()
        await model.fund()
        #expect(model.targets.isEmpty)
        #expect(model.message == .failed("Nothing to fund yet — sign in or add a card first"))
    }

    @Test("« Any address » (Chimp Admin, sans compte) : seule une adresse G ou C de 56 caractères est financée")
    func customAddress() async {
        let session = AppSession(store: InMemoryLocalWalletStore(), config: .testnet)
        let funding = MockTestnetFunding()
        funding.delay = .zero
        let model = AdminFundModel(session: session, chain: FakeCardsChain(members: [], pockets: [:]), funder: funding)
        let wallet = String(repeating: "C", count: 56)
        for bad in ["", "hello", String(repeating: "S", count: 56), String(wallet.dropLast())] {
            model.customAddress = bad
            #expect(model.customTarget == nil, "Refusé : \(bad)")
            await model.fundCustom()
        }
        #expect(funding.funded.isEmpty)
        model.customAddress = "  " + wallet.lowercased() + "\n"
        #expect(model.customTarget == wallet)
        await model.fundCustom()
        #expect(funding.funded == [wallet])
        #expect(model.message == .ok("Sent 1000 test XLM to CCCCCC…CCCC."))
    }
}

// MARK: Faux

@MainActor
private final class SleepRecorder {
    var durations: [Duration] = []
}

@MainActor
private final class FakeFundingNetwork: FundingNetwork {
    struct Transfer: Equatable {
        let from: String
        let to: String
        let units: UInt64
    }

    let adminBalance: Decimal?
    /// Comptes G ouverts sur le réseau (`nil` : tous) ; un autre compte n'a pas de solde lisible.
    var openAccounts: Set<String>?
    var friendbotFailures: Int
    private(set) var friendbotCalls: [String] = []
    private(set) var transfers: [Transfer] = []

    init(adminBalance: Decimal?, friendbotFailures: Int = 0) {
        self.adminBalance = adminBalance
        self.friendbotFailures = friendbotFailures
    }

    func nativeBalance(of account: String) async throws -> Decimal {
        if let openAccounts, !openAccounts.contains(account) { throw StellarError.rpc("404 not found") }
        guard let adminBalance else { throw URLError(.timedOut) }
        return adminBalance
    }

    func friendbot(_ address: String) async throws {
        friendbotCalls.append(address)
        if friendbotFailures > 0 {
            friendbotFailures -= 1
            throw FundingError.friendbot("Friendbot refused: 502")
        }
    }

    func transferXLM(from admin: KeyPair, to address: String, units: UInt64) async throws -> String {
        transfers.append(Transfer(from: admin.accountId, to: address, units: units))
        return "hash"
    }
}

@MainActor
private final class FakeCardsChain: WalletChain {
    let members: [ChipPublicKey]
    let pockets: [ChipPublicKey: String]

    init(members: [ChipPublicKey], pockets: [ChipPublicKey: String]) {
        self.members = members
        self.pockets = pockets
    }

    func cards(of account: String) async throws -> [AccountCard] { members.map { AccountCard(publicKey: $0, curve: .secp256k1) } }
    func balances(of address: String) async throws -> [AssetAmount] { [] }
    func pocket(of card: ChipPublicKey) async throws -> String? { pockets[card] }
    func tokenID(of card: ChipPublicKey) async throws -> UInt32 { 1 }
}
#endif
