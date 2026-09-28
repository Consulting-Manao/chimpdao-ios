import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Vérification des adresses du destinataire (C1) et pliage du memo ID dans une adresse M.
struct StellarAddressParserTests {
    private let maya = MockSendService.mayaAddress
    private let exchange = MockSendService.exchangeAddress

    private func issue(_ input: String) -> RecipientIssue? {
        guard case .failure(let issue)? = StellarAddressParser.parse(input) else { return nil }
        return issue
    }

    private func recipient(_ input: String) -> StellarRecipient? {
        guard case .success(let recipient)? = StellarAddressParser.parse(input) else { return nil }
        return recipient
    }

    // MARK: Adresses acceptées

    @Test("Champ vide : ni erreur ni adresse")
    func emptyInput() {
        #expect(StellarAddressParser.parse("") == nil)
        #expect(StellarAddressParser.parse("  \n ") == nil)
    }

    @Test("Adresse G valide")
    func validAccount() {
        let result = recipient(maya)
        #expect(result == StellarRecipient(address: maya, kind: .account, memoID: nil))
    }

    @Test("Espaces et retours à la ligne d'un copier-coller ignorés")
    func whitespaceIsIgnored() {
        let pasted = " \(maya.prefix(20))\n\(maya.dropFirst(20)) \n"
        #expect(recipient(pasted)?.address == maya)
    }

    @Test("Adresse en minuscules : même compte, remise en majuscules")
    func lowercaseIsAccepted() {
        #expect(recipient(maya.lowercased())?.address == maya)
    }

    @Test("Adresse C valide (contrat)")
    func validContract() {
        let address = MockReceiveDataSource.jungleAddress
        #expect(recipient(address) == StellarRecipient(address: address, kind: .contract, memoID: nil))
    }

    @Test("Adresse M valide : le memo ID est relu")
    func validMuxed() {
        let result = recipient(MockSendService.exchangeMuxedAddress)
        #expect(result?.kind == .muxed)
        #expect(result?.memoID == 1_234_567_890)
    }

    // MARK: Cas d'erreur

    @Test("Clé secrète S… : prévenir, même si elle est fausse")
    func secretKey() throws {
        let realLooking = try KeyPair.generateRandomKeyPair().secretSeed!
        #expect(issue(realLooking) == .secretKey)
        #expect(issue("S" + maya.dropFirst()) == .secretKey)
    }

    @Test("Fédération nom*domaine")
    func federation() {
        #expect(issue("maya*chimp.xyz") == .federation)
    }

    @Test("Adresse XRP Ledger")
    func xrpl() {
        #expect(issue("rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh") == .xrpl)
    }

    @Test("Adresse Ethereum")
    func evm() {
        #expect(issue("0x52908400098527886E0F7030069857D2E4169EE7") == .evm)
    }

    @Test("Un caractère faux : la somme de contrôle ne correspond plus")
    func typo() {
        #expect(issue(String(maya.dropLast()) + "Q") == .typo)
        let muxed = MockSendService.exchangeMuxedAddress
        #expect(issue(String(muxed.dropLast()) + "A") == .typo)
        let contract = MockReceiveDataSource.mainAddress
        #expect(issue(String(contract.dropLast()) + "A") == .typo)
    }

    @Test("Adresse coupée ou trop longue")
    func wrongLength() {
        #expect(issue(String(maya.prefix(40))) == .wrongLength)
        #expect(issue(maya + "A") == .wrongLength)
        #expect(issue(String(MockSendService.exchangeMuxedAddress.dropLast(3))) == .wrongLength)
    }

    @Test("Rien de reconnaissable")
    func notStellar() {
        #expect(issue("hello") == .notStellar)
        #expect(issue("12345") == .notStellar)
    }

    @Test("Son propre tiroir : il faut passer par Move")
    func ownDrawer() async {
        let model = SendFlowModel(service: MockSendService(delay: .zero))
        await model.load()

        model.addressText = MockReceiveDataSource.mainAddress
        #expect(model.recipientState == .invalid(.ownDrawer(name: "Main account", isMain: true)))

        model.addressText = MockReceiveDataSource.jungleAddress
        #expect(model.recipientState == .invalid(.ownDrawer(name: "Jungle's wallet", isMain: false)))
        #expect(!model.canContinueFromRecipient)

        model.addressText = maya
        #expect(model.recipientState == .valid(StellarRecipient(address: maya, kind: .account, memoID: nil)))
    }

    // MARK: Memo ID

    @Test("Memo ID : chiffres seulement, 64 bits")
    func memoID() {
        #expect(StellarAddressParser.parseMemoID("") == nil)
        #expect(StellarAddressParser.parseMemoID(" 42 ") == .success(42))
        #expect(StellarAddressParser.parseMemoID("1234567890") == .success(1_234_567_890))
        #expect(StellarAddressParser.parseMemoID("18446744073709551615") == .success(UInt64.max))
        #expect(StellarAddressParser.parseMemoID("18446744073709551616") == .failure(.tooLarge))
        #expect(StellarAddressParser.parseMemoID("12a") == .failure(.notANumber))
        #expect(StellarAddressParser.parseMemoID("-1") == .failure(.notANumber))
        // Chiffres arabo-indiens : des « nombres » pour Swift, pas pour un memo ID.
        #expect(StellarAddressParser.parseMemoID("٣") == .failure(.notANumber))
    }

    // MARK: Adresse M construite (G + memo ID)

    /// G de l'exchange factice + memo ID 1234567890. Valeur calculée par le SDK Stellar et vérifiée par un calcul
    /// SEP-23 indépendant (clé de 32 octets puis ID de 8 octets, 2026-09-28).
    private let exchangeWithMemo = "MB53FJ3TWAR2IFCHTD4Y2MWYMMOZ7PDCW4DU5OXPZMULLJQQ4PL44AAAAAAETFQC2J5EQ"

    @Test("G + 1234567890 donne l'adresse M de référence")
    func foldingMatchesReference() throws {
        let base = try #require(recipient(exchange))
        let folded = try #require(StellarAddressParser.folding(memoID: 1_234_567_890, into: base))
        #expect(folded.address == exchangeWithMemo)
        #expect(folded.kind == .muxed)
        #expect(folded.memoID == 1_234_567_890)

        // Même valeur que le SDK, calculée ici indépendamment de l'app.
        let sdk = try MuxedAccount(accountId: exchange, id: 1_234_567_890).accountId
        #expect(folded.address == sdk)

        // L'adresse M désigne bien le même compte G.
        let decoded = try exchangeWithMemo.decodeMuxedAccount()
        #expect(decoded.ed25519AccountId == exchange)
        #expect(decoded.id == 1_234_567_890)
    }

    @Test("Exemple de la norme SEP-23 (clé puis ID)")
    func sep23Vector() throws {
        let account = "GA7QYNF7SOWQ3GLR2BGMZEHXAVIRZA4KVWLTJJFC7MGXUA74P7UJVSGZ"
        // Adresse M donnée en exemple par SEP-23, avec l'ID 9223372036854775808.
        let example = "MA7QYNF7SOWQ3GLR2BGMZEHXAVIRZA4KVWLTJJFC7MGXUA74P7UJVAAAAAAAAAAAAAJLK"
        let parsed = try #require(recipient(example))
        #expect(parsed.memoID == 9_223_372_036_854_775_808)

        let base = try #require(recipient(account))
        let folded = try #require(StellarAddressParser.folding(memoID: 9_223_372_036_854_775_808, into: base))
        #expect(folded.address == example)
        // L'ordre inverse (ID puis clé, comme `withMemoId` du terminal) donnerait une adresse qui commence par « MAAAAAAA ».
        #expect(folded.address.hasPrefix("MA7QYNF7SOWQ3GLR2BGMZEHXAVIRZA4KVWLTJJFC7MGXUA74P7UJ"))
    }

    @Test("Pas de memo ID sur une adresse M ou C")
    func foldingOnlyOnAccounts() throws {
        let muxed = try #require(recipient(MockSendService.exchangeMuxedAddress))
        #expect(StellarAddressParser.folding(memoID: 1, into: muxed) == nil)
        let contract = try #require(recipient(MockReceiveDataSource.mainAddress))
        #expect(StellarAddressParser.folding(memoID: 1, into: contract) == nil)
    }

    @Test("Adresse raccourcie : 4 premiers…4 derniers")
    func shortAddress() {
        #expect(StellarAddressParser.short(maya) == "GCQF…GXPO")
        #expect(StellarAddressParser.short("GABC") == "GABC")
    }
}
