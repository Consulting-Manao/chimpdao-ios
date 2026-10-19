import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Onboarding, étape 4 : le vrai onboarding. SET PIN et PUK (APDU comparés à `infineon2go.js`), création avec
/// reprise, enregistrement sur le téléphone seulement après confirmation sur la chaîne.
struct RealOnboardingTests {
    private let k1Key = MockChipReader.secp256k1Key
    private let pocket = "CALWOI2Z6NZ5ULEYRXZZTN7M35CMWMS6YJXTQTVPIOQXKEKWKTVELEMX"
    private let digestA = Data(repeating: 0xA1, count: 32)
    private let digestB = Data(repeating: 0xB2, count: 32)

    // MARK: SET PIN (Core)

    @Test("SET PIN : 00 40 00 00 <Lc> <PIN> 08, comme setPin() du bridge ; PIN de 4 à 62 octets")
    func setPINAPDU() throws {
        #expect(try Infineon2Go.setPINAPDU(pin: "1234").hexString == "00400000043132333408")
        #expect(throws: ChipError.invalidPINLength) { try Infineon2Go.setPINAPDU(pin: "123") }
    }

    @Test("Réponse à SET PIN : PUK = 8 premiers octets ; erreurs comme pinError")
    func setPINResponse() throws {
        let puk = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF])
        #expect(try Infineon2Go.parseSetPIN(APDUResponse(data: puk, sw1: 0x90, sw2: 0x00)) == puk)
        #expect(throws: ChipError.malformedResponse("SET PIN returned 4 bytes, expected a 8-byte PUK")) {
            try Infineon2Go.parseSetPIN(APDUResponse(data: Data(count: 4), sw1: 0x90, sw2: 0x00))
        }
        #expect(throws: ChipError.status(command: "SET PIN", statusWord: 0x6985)) {
            try Infineon2Go.parseSetPIN(APDUResponse(data: Data(), sw1: 0x69, sw2: 0x85))
        }
    }

    @Test("Un tap : lecture, SELECT, SET PIN, puis SELECT → VERIFY PIN → SIGN pour chaque digest ; le PUK est rendu")
    func setPINAndSignSequence() async throws {
        let card = PINCard(key: k1Key, pinActive: false)
        let result = try await ChipSigning.setPINAndSign(card, digests: [digestA, digestB], expectedKey: k1Key, newPIN: "1234")
        #expect(result.puk?.hexString == "0123456789abcdef")
        #expect(result.signatures.count == 2)
        let commands = card.sent.map { $0.prefix(2).hexString }
        // Détection (SELECT), lecture (SELECT, GET KEY INFO), SET PIN, puis deux signatures.
        #expect(commands == ["00a4", "00a4", "0016", "00a4", "0040", "00a4", "0044", "0018", "00a4", "0044", "0018"])
        #expect(card.sent.filter { $0.prefix(2).hexString == "0040" }.count == 1)
    }

    @Test("Carte qui a déjà un PIN (essai précédent) : jamais de SET PIN, le PIN est vérifié, pas de PUK")
    func setPINSkippedWhenAlreadySet() async throws {
        let card = PINCard(key: k1Key, pinActive: true, pin: "1234")
        let result = try await ChipSigning.setPINAndSign(card, digests: [digestA, digestB], expectedKey: k1Key, newPIN: "1234")
        #expect(result.puk == nil)
        #expect(!card.sent.contains { $0.prefix(2).hexString == "0040" })
    }

    @Test("Autre carte : refus avant SET PIN ; DUOX : refus, pas de PIN")
    func setPINGuards() async throws {
        let other = PINCard(key: MockChipReader.p256Key, pinActive: false)
        await #expect(throws: ChipError.wrongCard) {
            try await ChipSigning.setPINAndSign(other, digests: [digestA], expectedKey: k1Key, newPIN: "1234")
        }
        #expect(!other.sent.contains { $0.prefix(2).hexString == "0040" })
        await #expect(throws: ChipError.pinAlreadySet) {
            try await Infineon2Go.setPIN(PINCard(key: k1Key, pinActive: true, pin: "0000"), pin: "1234")
        }
    }

    @Test("PIN défini mais signature ratée (carte retirée) : l'erreur porte le PUK, il n'est jamais perdu")
    func pukNeverLost() async throws {
        let card = PINCard(key: k1Key, pinActive: false, failSignAfter: 1)
        do {
            _ = try await ChipSigning.setPINAndSign(card, digests: [digestA, digestB], expectedKey: k1Key, newPIN: "1234")
            Issue.record("expected a failure")
        } catch let error as PINSetButSigningFailed {
            #expect(error.puk.hexString == "0123456789abcdef")
            #expect(error.underlying == .transport("Tag connection lost"))
        }
    }

    // MARK: Création et reprise

    @Test("Création : preuve, déploiement, lien, confirmation, dans cet ordre")
    func creationOrder() async throws {
        let chain = FakeChain()
        var steps: [CreationStep] = []
        let result = try await AccountCreator(chain: chain).create(try plan(), signatures: signatures()) { steps.append($0) }
        #expect(steps == [.checkingCard, .creatingAccount, .linkingCard, .confirming])
        #expect(chain.calls == ["possession", "deploy", "link"])
        #expect(result.deploymentHash != nil)
        #expect(result.linkHash != nil)
    }

    @Test("Reprise : compte déjà déployé et carte déjà liée → rien n'est renvoyé, seulement relu")
    func creationResumes() async throws {
        let chain = FakeChain()
        chain.deployed = true
        let first = try await AccountCreator(chain: chain).create(try plan(), signatures: signatures()) { _ in }
        #expect(first.deploymentHash == nil)
        #expect(chain.calls == ["possession", "link"])
        let again = try await AccountCreator(chain: chain).create(try plan(), signatures: signatures()) { _ in }
        #expect(again.linkHash == nil)
        #expect(chain.calls == ["possession", "link", "possession"])
    }

    @Test("Coupure pendant le lien : l'erreur remonte ; un nouvel essai ne redéploie pas")
    func creationInterrupted() async throws {
        let chain = FakeChain()
        chain.linkError = StellarError.rpc("The request timed out.")
        await #expect(throws: StellarError.rpc("The request timed out.")) {
            try await AccountCreator(chain: chain).create(try plan(), signatures: signatures()) { _ in }
        }
        chain.linkError = nil
        _ = try await AccountCreator(chain: chain).create(try plan(), signatures: signatures()) { _ in }
        #expect(chain.calls.filter { $0 == "deploy" }.count == 1)
    }

    @Test("Signature set_owner trop vieille (moins de 20 ledgers) : rien n'est envoyé, un nouveau tap est demandé")
    func creationSignatureExpired() async throws {
        let chain = FakeChain()
        chain.ledger = 990
        await #expect(throws: AccountCreationError.signatureExpired) {
            try await AccountCreator(chain: chain).create(try plan(), signatures: signatures()) { _ in }
        }
        #expect(!chain.calls.contains("link"))
    }

    @Test("Envoyé mais pas visible à la relecture : « pas encore confirmé », jamais un succès")
    func creationNotConfirmed() async throws {
        let chain = FakeChain()
        chain.linkLandsOnChain = false
        await #expect(throws: AccountCreationError.self) {
            try await AccountCreator(chain: chain).create(try plan(), signatures: signatures()) { _ in }
        }
    }

    @Test("Classement des erreurs : réseau, serveur de frais, non confirmé, signature expirée ou refusée")
    func problemKinds() {
        #expect(CreationProblem.from(StellarError.rpc("x")).kind == .network)
        #expect(CreationProblem.from(FeeSignerError.busy).kind == .feeHelperBusy)
        #expect(CreationProblem.from(FeeSignerError.refused("fee")).kind == .feeHelperRefused)
        #expect(CreationProblem.from(StellarError.notConfirmed(hash: "h")).kind == .notConfirmed)
        #expect(CreationProblem.from(AccountCreationError.signatureExpired).needsNewTap)
        #expect(CreationProblem.from(StellarError.signatureRejected("x")).needsNewTap)
        #expect(!CreationProblem.from(StellarError.rpc("x")).needsNewTap)
    }

    // MARK: Parcours réel (ViewModel)

    @Test("Vrai tap d'une Infineon sans PIN : SET PIN avec le PIN choisi, PUK gardé pour l'écran, PIN effacé")
    func realTapSetsPIN() async throws {
        let signer = RecordingSigner()
        let model = try realModel(signer: signer)
        await model.pinEnter("1234", "1234")
        model.openTapSheet(.real)
        #expect(await model.scan() == .signed)
        #expect(signer.newPINs == ["1234"])
        #expect(model.unlockCode?.hexString == "deadbeef01020304")
        #expect(model.pinWasSet)
        #expect(model.pinMode == .existing)
        model.acknowledgeUnlockCode()
        #expect(model.unlockCode == nil)
    }

    @Test("Création réussie : le compte n'est enregistré qu'après confirmation, avec prénom, nom et couleur")
    func savedOnlyAfterConfirmation() async throws {
        let store = InMemoryLocalWalletStore()
        let session = AppSession(store: store, config: .testnet)
        let chain = FakeChain()
        let model = try realModel(signer: RecordingSigner(), session: session, chain: chain)
        model.firstName = "Barth"
        model.cardName = "Jungle"
        model.cardColor = .leaf
        await model.pinEnter("1234", "1234")
        model.openTapSheet(.real)
        #expect(await model.scan() == .signed)
        await model.create()
        let account = try #require(model.createdResult?.account)
        #expect(store.wallet.account?.address == account)
        #expect(store.wallet.firstName == "Barth")
        #expect(store.wallet.account?.cards.first?.name == "Jungle")
        #expect(store.wallet.account?.cards.first?.color == "leaf")
        #expect(store.wallet.hint(for: k1Key) == account)
        #expect(session.showsOnboarding)
        session.finishOnboarding()
        #expect(!session.showsOnboarding)
    }

    @Test("Échec de la création : rien n'est enregistré ; « Try again » reprend avec les mêmes signatures, sans nouveau tap")
    func failureThenRetry() async throws {
        let store = InMemoryLocalWalletStore()
        let session = AppSession(store: store, config: .testnet)
        let chain = FakeChain()
        chain.linkError = FeeSignerError.busy
        let signer = RecordingSigner()
        let model = try realModel(signer: signer, session: session, chain: chain)
        await model.pinEnter("1234", "1234")
        model.openTapSheet(.real)
        #expect(await model.scan() == .signed)
        await model.create()
        guard case .failed(let problem) = model.phase else { Issue.record("expected a failure"); return }
        #expect(problem.kind == .feeHelperBusy)
        #expect(store.saveCount == 0)
        #expect(model.lastReachedStep == .linkingCard)
        chain.linkError = nil
        await model.create()
        #expect(model.createdResult != nil)
        #expect(signer.newPINs.count == 1)
        #expect(chain.calls.filter { $0 == "deploy" }.count == 1)
    }

    @Test("Signature expirée : nouveau tap avec le PIN ressaisi, vérifié (VERIFY), jamais redéfini")
    func expiredSignatureNewTap() async throws {
        let chain = FakeChain()
        // Le plan factice signe jusqu'au ledger 1120 : à 1110, il reste moins de 20 ledgers.
        chain.ledger = 1_110
        let signer = RecordingSigner()
        let model = try realModel(signer: signer, chain: chain)
        await model.pinEnter("1234", "1234")
        model.openTapSheet(.real)
        #expect(await model.scan() == .signed)
        await model.create()
        guard case .failed(let problem) = model.phase else { Issue.record("expected a failure"); return }
        #expect(problem.needsNewTap)
        model.prepareNewTap()
        #expect(model.pinMode == .existing)
        #expect(model.pinStep == .first)
        model.pinCompleted("1234")
        chain.ledger = 900
        model.openTapSheet(.real)
        #expect(await model.scan() == .signed)
        #expect(signer.newPINs == ["1234"])
        #expect(signer.calls.last?.pin == "1234")
    }

    @Test("PIN défini mais signature ratée : PUK montré, puis nouveau tap avec le même PIN (gardé en mémoire), sans SET PIN")
    func pinSetButSigningFailed() async throws {
        let signer = RecordingSigner()
        signer.setPINError = PINSetButSigningFailed(puk: Data([0xAA, 0xBB, 0xCC, 0xDD, 0x11, 0x22, 0x33, 0x44]), underlying: .transport("lost"))
        let model = try realModel(signer: signer)
        await model.pinEnter("1234", "1234")
        model.openTapSheet(.real)
        #expect(await model.scan() == .pinSetOnly)
        #expect(model.unlockCode?.hexString == "aabbccdd11223344")
        #expect(model.pinMode == .existing)
        #expect(model.tapProblem?.kind == .cardMoved)
        model.acknowledgeUnlockCode()
        #expect(model.canFinish)
        model.openTapSheet(.real)
        #expect(await model.scan() == .signed)
        #expect(signer.newPINs.count == 1)
        #expect(signer.calls.last?.pin == "1234")
    }

    @Test("DUOX : ni PIN ni SET PIN, un tap et la création")
    func duoxRealFlow() async throws {
        let signer = RecordingSigner()
        let model = try realModel(signer: signer, choice: CardChoice(
            kind: .fresh, card: ChipKeyInfo(kind: .duox, publicKey: MockChipReader.p256Key, pinActive: false),
            tokenID: 8, pocket: pocket, pocketIsEmpty: true
        ))
        model.openTapSheet(.real)
        #expect(await model.scan() == .signed)
        #expect(signer.newPINs.isEmpty)
        #expect(signer.calls.first?.pin == nil)
        #expect(model.unlockCode == nil)
    }

    @Test("La répétition ne crée rien : ni SET PIN, ni création, ni enregistrement")
    func rehearsalNeverCreates() async throws {
        let store = InMemoryLocalWalletStore()
        let chain = FakeChain()
        let signer = RecordingSigner()
        let model = try realModel(signer: signer, session: AppSession(store: store, config: .testnet), chain: chain)
        await model.pinEnter("1234", "1234")
        model.openTapSheet(.rehearsal)
        #expect(await model.scan() == .signed)
        await model.create()
        #expect(signer.newPINs.isEmpty)
        #expect(chain.calls.isEmpty)
        #expect(store.saveCount == 0)
    }

    // MARK: Aides

    private func realModel(
        signer: ChipSigner,
        session: AppSession? = nil,
        chain: AccountCreationChain = FakeChain(),
        choice: CardChoice? = nil
    ) throws -> AccountSetupModel {
        try AccountSetupModel(
            choice: choice ?? CardChoice(kind: .fresh, card: ChipKeyInfo(kind: .infineon2Go, publicKey: k1Key, pinActive: false),
                                         tokenID: 7, pocket: pocket, pocketIsEmpty: true),
            service: MockAccountSetupService(delay: .zero), creator: AccountCreator(chain: chain),
            signer: signer, session: session, rehearsal: MockAccountSetupService(delay: .zero)
        )
    }

    /// Plan d'une carte Infineon, signature `set_owner` valable jusqu'au ledger 1000.
    private func plan() throws -> AccountSetupPlan {
        let account = try ChimpAccountClient.predictedAddress(feePayer: ChimpNetworkConfig.testnet.feePayer, publicKey: k1Key, network: .testnet)
        let setOwner = try PocketClient.declareSetOwner(
            pocket: pocket, newOwner: account, passphrase: ChimpNetworkConfig.testnet.passphrase, currentLedger: 880, nonce: 1
        )
        return AccountSetupPlan(
            card: ChipKeyInfo(kind: .infineon2Go, publicKey: k1Key, pinActive: false), pocket: pocket,
            nftContract: ChimpNetworkConfig.testnet.contracts.nfcNft, accountSalt: ChimpAccountClient.salt(for: k1Key),
            account: account, challenge: Data(repeating: 0x5A, count: 32), setOwner: setOwner
        )
    }

    private func signatures() -> [ChipSignedDigest] {
        [.secp256k1(signature: Data(repeating: 0x11, count: 64)), .secp256k1(signature: Data(repeating: 0x22, count: 64))]
    }
}

/// Fausse chaîne : garde l'état (déployé, lié) et les appels ; erreurs à la demande.
private final class FakeChain: AccountCreationChain, @unchecked Sendable {
    var deployed = false
    var linkedAccount: String?
    var ledger: UInt32 = 900
    var linkError: Error?
    /// `false` : le lien est « envoyé » mais la relecture ne le montre pas.
    var linkLandsOnChain = true
    private(set) var calls: [String] = []

    func verifyPossession(_ plan: AccountSetupPlan, signed: ChipSignedDigest) async throws { calls.append("possession") }
    func isDeployed(_ account: String) async throws -> Bool { deployed }
    func deployAccount(_ plan: AccountSetupPlan) async throws -> String {
        calls.append("deploy")
        deployed = true
        return "deploy-hash"
    }
    func pocketOwner(_ pocket: String) async throws -> String { linkedAccount ?? pocket }
    func latestLedger() async throws -> UInt32 { ledger }
    func linkCard(_ plan: AccountSetupPlan, signed: ChipSignedDigest) async throws -> String {
        calls.append("link")
        if let linkError { throw linkError }
        if linkLandsOnChain { linkedAccount = plan.account }
        return "link-hash"
    }
    func hasCard(account: String, publicKey: ChipPublicKey) async throws -> Bool { linkedAccount == account }
}

/// Infineon simulée qui connaît son PIN : SET PIN (PUK fixe), VERIFY PIN, SIGN (exige le PIN une fois défini).
private final class PINCard: APDUTransport, @unchecked Sendable {
    private(set) var sent: [Data] = []
    let key: ChipPublicKey
    private var pin: String?
    private var verified = false
    private var signs = 0
    /// Nombre de signatures réussies avant de « perdre » la carte (`nil` : jamais).
    let failSignAfter: Int?

    init(key: ChipPublicKey, pinActive: Bool, pin: String? = nil, failSignAfter: Int? = nil) {
        self.key = key
        self.pin = pinActive ? (pin ?? "0000") : nil
        self.failSignAfter = failSignAfter
    }

    func send(_ apdu: Data) async throws -> APDUResponse {
        sent.append(apdu)
        let ok = { (data: Data) in APDUResponse(data: data, sw1: 0x90, sw2: 0x00) }
        switch apdu.prefix(2).hexString {
        case "00a4":
            verified = false
            return ok(Data([pin == nil ? 0x00 : 0x01]))
        case "0016":
            return ok(Data(count: 8) + key.bytes)
        case "0040":
            guard pin == nil else { return APDUResponse(data: Data(), sw1: 0x69, sw2: 0x85) }
            pin = String(decoding: apdu.dropFirst(5).dropLast(), as: UTF8.self)
            return ok(Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]))
        case "0044":
            let given = String(decoding: apdu.dropFirst(5), as: UTF8.self)
            guard given == pin else { return APDUResponse(data: Data(), sw1: 0x63, sw2: 0xC2) }
            verified = true
            return ok(Data())
        case "0018":
            if let failSignAfter, signs >= failSignAfter { throw ChipError.transport("Tag connection lost") }
            guard pin == nil || verified else { return APDUResponse(data: Data(), sw1: 0x69, sw2: 0x85) }
            signs += 1
            let der = Data(hex: "3044022011111111111111111111111111111111111111111111111111111111111111110220" + String(repeating: "22", count: 32))!
            return ok(Data(count: 8) + der)
        default:
            return APDUResponse(data: Data(), sw1: 0x6D, sw2: 0x00)
        }
    }
}
