import CryptoKit
import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

// Mode admin (CHIMP_ADMIN) : absent de la Release, donc du schéma « Chimp Release Tests ».
#if CHIMP_ADMIN

/// Onboarding, étape 3 : A4 à A7 en répétition à blanc.
/// Valeur de référence de `recoverySalt` calculée par la fonction du terminal (`provisioning.ts`), exécutée avec
/// `@stellar/stellar-sdk` 17.0.1.
struct SetupRehearsalTests {
    private let k1Key = MockChipReader.secp256k1Key
    private let config = ChimpNetworkConfig.testnet
    private let oldAccount = "CDU45A6K2WTMLRDUEQ7SXGOUICJVRWSLZCYPLWB7W6FVQLD7LPNRVVFR"
    private let pocket = "CALWOI2Z6NZ5ULEYRXZZTN7M35CMWMS6YJXTQTVPIOQXKEKWKTVELEMX"

    // MARK: Sel du Main account

    @Test("recoverySalt (carte orpheline) et l'adresse qui en découle : identiques au terminal")
    func recoverySalt() throws {
        let salt = try ChimpAccountClient.recoverySalt(publicKey: k1Key, escapedFrom: oldAccount)
        #expect(salt.hexString == "bc2a3bacf6eacb2bca646af01c61dead45ed36bae5e3c8937c4a400927c0596d")
        #expect(try ChimpAccountClient.predictedAddress(feePayer: config.feePayer, salt: salt, network: .testnet)
            == "CCSARAU5RPPNBHNU33XOBHFNWTUIXXKX3QV3ELRPVFD2F3H4EKOM4WCS")
        #expect(throws: (any Error).self) { try ChimpAccountClient.recoverySalt(publicKey: k1Key, escapedFrom: config.feePayer) }
    }

    @Test("Sel de la cérémonie : carte neuve = sha256(clé) ; orpheline = recoverySalt ; ancien compte inconnu = sel aléatoire tiré une fois")
    func ceremonySalt() async throws {
        let signer = RecordingSigner()
        let service = MockAccountSetupService(delay: .zero)

        let fresh = try makeSetup(choice(.fresh), service: service, signer: signer)
        await fresh.pinEnter("1234", "1234")
        #expect(await fresh.rehearsalScan() == .signed)
        #expect(service.lastSalt == ChimpAccountClient.salt(for: k1Key))

        let orphan = try makeSetup(choice(.orphan(lastKnown: oldAccount)), service: service, signer: signer)
        await orphan.pinEnter("1234", "1234")
        #expect(await orphan.rehearsalScan() == .signed)
        #expect(service.lastSalt == (try ChimpAccountClient.recoverySalt(publicKey: k1Key, escapedFrom: oldAccount)))

        let random = Data(repeating: 0x77, count: 32)
        let unknown = try makeSetup(choice(.orphan(lastKnown: nil)), service: service, signer: signer, randomSalt: { random })
        await unknown.pinEnter("1234", "1234")
        #expect(await unknown.rehearsalScan() == .signed)
        #expect(service.lastSalt == random)
    }

    @Test("Déploiement avec un sel donné : même sel dans l'opération que dans l'adresse prévue")
    func deployWithSalt() throws {
        let salt = try ChimpAccountClient.recoverySalt(publicKey: k1Key, escapedFrom: oldAccount)
        let operation = try ChimpAccountClient.deployOperation(
            wasmHash: config.contracts.accountWasmHash, feePayer: config.feePayer, publicKey: k1Key, curve: .secp256k1, salt: salt
        )
        guard case .createContractV2(let args) = operation.hostFunction,
              case .fromAddress(let preimage) = args.contractIDPreimage else {
            Issue.record("expected createContractV2 from address"); return
        }
        #expect(preimage.salt.wrapped == salt)
    }

    // MARK: recovery_id : refus observés

    @Test("Recherche du recovery_id : chaque refus est transmis avec son texte (question 21)")
    func rejectionsReported() async throws {
        var seen: [UInt32] = []
        let found = try await RecoveryIDSearch.first(rejectionCodes: [201], onRejected: { id, _ in seen.append(id) }) { id -> UInt32 in
            if id < 2 { throw StellarError.simulationFailed("Error(Contract, #201)") }
            return id
        }
        #expect(found.recoveryID == 2)
        #expect(seen == [0, 1])
    }

    // MARK: A4, A5

    @Test("Prénom et nom de carte : vides ou trop longs refusés, espaces ignorés")
    func namesValidation() throws {
        let model = try makeSetup(choice(.fresh), service: MockAccountSetupService(delay: .zero), signer: RecordingSigner())
        model.firstName = "   "
        #expect(!model.canContinueFromName)
        model.firstName = " Léo "
        #expect(model.canContinueFromName)
        #expect(model.trimmedFirstName == "Léo")
        model.firstName = String(repeating: "a", count: 31)
        #expect(!model.canContinueFromName)
        #expect(!model.canContinueFromCard)
        model.cardName = "Jungle"
        #expect(model.canContinueFromCard)
        model.cardName = String(repeating: "b", count: 21)
        #expect(!model.canContinueFromCard)
        #expect(model.cardNumber == "0007")
    }

    // MARK: A6 : PIN

    @Test("Ce que demande A6 : Infineon sans PIN = choisir ; Infineon avec PIN = le saisir ; DUOX = rien")
    func pinModes() throws {
        let service = MockAccountSetupService(delay: .zero)
        let choose = try makeSetup(choice(.fresh), service: service, signer: RecordingSigner())
        #expect(choose.pinMode == .choose)
        #expect(!choose.canFinish)
        let existing = try makeSetup(choice(.fresh, pinActive: true), service: service, signer: RecordingSigner())
        #expect(existing.pinMode == .existing)
        let duox = try makeSetup(choice(.fresh, kind: .duox), service: service, signer: RecordingSigner())
        #expect(duox.pinMode == .none)
        #expect(duox.canFinish)
    }

    @Test("Nouveau PIN : saisie puis confirmation ; deux saisies différentes = « don't match », on recommence de zéro")
    func pinConfirmation() throws {
        let model = try makeSetup(choice(.fresh), service: MockAccountSetupService(delay: .zero), signer: RecordingSigner())
        model.pinCompleted("1234")
        #expect(model.pinStep == .confirm)
        #expect(model.pinEntry.isEmpty)
        model.pinCompleted("4321")
        #expect(model.pinState == .mismatch)
        #expect(model.pinStep == .first)
        #expect(!model.canFinish)
        model.pinCompleted("1234")
        model.pinCompleted("1234")
        #expect(model.pinStep == .done)
        #expect(model.canFinish)
        model.restartPIN()
        #expect(model.pinStep == .first)
        #expect(!model.canFinish)
    }

    @Test("PIN : seulement 4 chiffres")
    func pinFormat() throws {
        let model = try makeSetup(choice(.fresh), service: MockAccountSetupService(delay: .zero), signer: RecordingSigner())
        model.pinCompleted("12a4")
        model.pinCompleted("123")
        #expect(model.pinStep == .first)
    }

    // MARK: Tap (répétition)

    @Test("Tap : lectures réseau d'abord, puis un seul tap qui signe la preuve de possession et set_owner, dans cet ordre")
    func tapSignsBothDigests() async throws {
        let signer = RecordingSigner()
        let service = MockAccountSetupService(delay: .zero)
        let model = try makeSetup(choice(.fresh), service: service, signer: signer)
        await model.pinEnter("1234", "1234")
        #expect(await model.rehearsalScan() == .signed)
        #expect(service.prepareCount == 1)
        let plan = try #require(service.lastPlan)
        #expect(signer.calls.count == 1)
        #expect(signer.calls[0].digests == [plan.challenge, plan.setOwner.digest])
        #expect(signer.calls[0].expectedKey == k1Key)
        #expect(model.phase == .signed)
        #expect(!model.isShowingTapSheet)
    }

    @Test("Répétition : le PIN choisi n'est jamais envoyé à la carte ; un PIN déjà défini est vérifié (VERIFY PIN)")
    func pinSentOnlyWhenExisting() async throws {
        let newPIN = RecordingSigner()
        let fresh = try makeSetup(choice(.fresh), service: MockAccountSetupService(delay: .zero), signer: newPIN)
        await fresh.pinEnter("1234", "1234")
        #expect(await fresh.rehearsalScan() == .signed)
        #expect(newPIN.calls[0].pin == nil)

        let existingPIN = RecordingSigner()
        let existing = try makeSetup(choice(.fresh, pinActive: true), service: MockAccountSetupService(delay: .zero), signer: existingPIN)
        existing.pinCompleted("5678")
        #expect(await existing.rehearsalScan() == .signed)
        #expect(existingPIN.calls[0].pin == "5678")
    }

    @Test("Règle : SET PIN (00 40) n'est jamais envoyé pendant la répétition ; carte sans PIN : ni VERIFY PIN (00 44)")
    func noSetPINOnTheWire() async throws {
        let card = RehearsalInfineon(key: k1Key, pinActive: false)
        let model = try makeSetup(choice(.fresh), service: MockAccountSetupService(delay: .zero), signer: TransportSigner(card: card))
        await model.pinEnter("1234", "1234")
        #expect(await model.rehearsalScan() == .signed)
        #expect(!card.sent.contains { $0.count > 1 && $0[1] == 0x40 })
        #expect(!card.sent.contains { $0.count > 1 && $0[1] == 0x44 })
        #expect(card.sent.filter { $0.count > 1 && $0[1] == 0x18 }.count == 2)
    }

    @Test("Carte qui a déjà un PIN : VERIFY PIN puis SIGN, deux fois, jamais SET PIN")
    func existingPINOnTheWire() async throws {
        let card = RehearsalInfineon(key: k1Key, pinActive: true)
        let model = try makeSetup(choice(.fresh, pinActive: true), service: MockAccountSetupService(delay: .zero), signer: TransportSigner(card: card))
        model.pinCompleted("5678")
        #expect(await model.rehearsalScan() == .signed)
        #expect(!card.sent.contains { $0.count > 1 && $0[1] == 0x40 })
        #expect(card.sent.filter { $0.count > 1 && $0[1] == 0x44 }.count == 2)
    }

    @Test("Tap annulé : retour à A6, feuille toujours ouverte ; rien n'est gardé")
    func tapCancelled() async throws {
        let model = try makeSetup(choice(.fresh), service: MockAccountSetupService(delay: .zero), signer: RecordingSigner(error: .cancelled))
        await model.pinEnter("1234", "1234")
        #expect(await model.rehearsalScan() != .signed)
        #expect(model.phase == .editing)
        #expect(model.isShowingTapSheet)
        #expect(model.tapProblem == nil)
    }

    @Test("Règle 7 : mauvaise carte, mauvais PIN, PIN bloqué, liaison perdue : remontés à l'écran")
    func tapErrorsSurface() async throws {
        let wrongCard = try makeSetup(choice(.fresh), service: MockAccountSetupService(delay: .zero), signer: RecordingSigner(error: .wrongCard))
        await wrongCard.pinEnter("1234", "1234")
        #expect(await wrongCard.rehearsalScan() != .signed)
        #expect(wrongCard.tapProblem?.kind == .wrongCard)

        let wrongPIN = try makeSetup(choice(.fresh, pinActive: true), service: MockAccountSetupService(delay: .zero), signer: RecordingSigner(error: .wrongPIN(retriesLeft: 2)))
        wrongPIN.pinCompleted("0000")
        #expect(await wrongPIN.rehearsalScan() != .signed)
        #expect(wrongPIN.pinState == .wrong(triesLeft: 2))
        // Le PIN refusé est effacé : l'utilisateur le retape.
        #expect(wrongPIN.pinStep == .first)

        let locked = try makeSetup(choice(.fresh, pinActive: true), service: MockAccountSetupService(delay: .zero), signer: RecordingSigner(error: .pinLocked))
        locked.pinCompleted("0000")
        #expect(await locked.rehearsalScan() != .signed)
        #expect(locked.pinState == .blocked)

        let moved = try makeSetup(choice(.fresh), service: MockAccountSetupService(delay: .zero), signer: RecordingSigner(error: .transport("Tag connection lost")))
        await moved.pinEnter("1234", "1234")
        #expect(await moved.rehearsalScan() != .signed)
        #expect(moved.tapProblem?.kind == .cardMoved)
        #expect(moved.tapProblem?.technicalDetails.contains("Tag connection lost") == true)
    }

    @Test("Réseau en panne avant le tap : la carte n'est jamais sollicitée")
    func prepareFailureNoTap() async throws {
        let signer = RecordingSigner()
        let service = FailingPrepareService()
        let model = try makeSetup(choice(.fresh), service: service, signer: signer)
        await model.pinEnter("1234", "1234")
        #expect(await model.rehearsalScan() != .signed)
        #expect(signer.calls.isEmpty)
        #expect(model.tapProblem?.kind == .couldntCheck)
    }

    // MARK: Vérifications

    @Test("Vérifications : rapport en cas de succès ; échec affiché puis « Try again » avec les mêmes signatures")
    func checks() async throws {
        let service = MockAccountSetupService(scenario: .networkError, delay: .zero)
        let signer = RecordingSigner()
        let model = try makeSetup(choice(.fresh), service: service, signer: signer)
        await model.pinEnter("1234", "1234")
        #expect(await model.rehearsalScan() == .signed)
        await model.check()
        guard case .rehearsalFailed(let problem) = model.phase else { Issue.record("expected failure"); return }
        #expect(problem.kind == .couldntCheck)
        service.scenario = .success
        await model.check()
        #expect(model.report != nil)
        #expect(service.rehearseCount == 2)
        #expect(signer.calls.count == 1)
    }

    @Test("Création : confirmation, PIN, puis le tap démarre tout seul après la confirmation du PIN (une seule signature)")
    func pinStartsTheTap() async throws {
        let session = AppSession(store: InMemoryLocalWalletStore(), config: .testnet)
        let signer = RecordingSigner()
        let onboarding = OnboardingModel(
            session: session, reader: MockChipReader(scenario: .infineon, delay: .zero),
            service: MockOnboardingService(scenario: .fresh, delay: .zero), signer: RecordingSigner(),
            makeSetup: { try self.makeSetup($0, service: MockAccountSetupService(delay: .zero), signer: signer) }
        )
        onboarding.path = [.reading]
        await onboarding.scan()
        guard case .choice(let fresh) = onboarding.path.last else { Issue.record("expected A3"); return }
        onboarding.startNewAccount(with: fresh)
        let setup = try #require(onboarding.setup)
        setup.firstName = "Léo"
        onboarding.continueFromName()
        setup.cardName = "Jungle"
        onboarding.continueFromCard()
        onboarding.confirmCreate(.rehearsal)
        #expect(onboarding.path.last == .pickPIN)
        await setup.pinEnter("1234", "1234")
        for _ in 0..<200 where onboarding.path.last != .unlockCode {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(onboarding.path.last == .unlockCode)
        #expect(signer.calls.count == 1, "Un seul tap, lancé tout seul")
    }

    @Test("Toute la répétition, de A3 à A7 : rien n'est enregistré sur le téléphone, retour à A1")
    func wholeRehearsalSavesNothing() async throws {
        let store = InMemoryLocalWalletStore()
        let session = AppSession(store: store, config: .testnet)
        let onboarding = OnboardingModel(
            session: session, reader: MockChipReader(scenario: .infineon, delay: .zero),
            service: MockOnboardingService(scenario: .fresh, delay: .zero), signer: RecordingSigner(),
            makeSetup: { try self.makeSetup($0, service: MockAccountSetupService(delay: .zero), signer: RecordingSigner()) }
        )
        onboarding.path = [.reading]
        await onboarding.scan()
        guard case .choice(let fresh) = onboarding.path.last else { Issue.record("expected A3"); return }
        onboarding.startNewAccount(with: fresh)
        let setup = try #require(onboarding.setup)
        #expect(onboarding.path.last == .yourName)
        setup.firstName = "Léo"
        onboarding.continueFromName()
        setup.cardName = "Jungle"
        onboarding.continueFromCard()
        #expect(onboarding.path.last == .confirmCreate, "La confirmation vient avant le PIN")
        onboarding.confirmCreate(.rehearsal)
        #expect(onboarding.path.last == .pickPIN)
        await setup.pinEnter("1234", "1234")
        #expect(setup.isShowingTapSheet, "PIN confirmé : la feuille du tap s'ouvre tout de suite")
        await onboarding.scanForSetup()
        #expect(onboarding.path.last == .unlockCode)
        #expect(setup.unlockCode == nil)
        onboarding.acknowledgeUnlockCode()
        #expect(onboarding.path.last == .setupCheck)
        await setup.check()
        onboarding.continueAfterCheck()
        #expect(onboarding.path.last == .welcome)
        onboarding.finishRehearsal()
        #expect(onboarding.path.isEmpty)
        #expect(onboarding.setup == nil)
        #expect(store.saveCount == 0)
        #expect(!session.hasAccount)
    }

    // MARK: Aides

    /// Cérémonie avec services factices ; la répétition est disponible, la création passe par une fausse chaîne.
    private func makeSetup(
        _ choice: CardChoice,
        service: AccountSetupService,
        signer: ChipSigner,
        randomSalt: (() throws -> Data)? = nil,
        session: AppSession? = nil,
        chain: AccountCreationChain = MockAccountCreationChain(delay: .zero)
    ) throws -> AccountSetupModel {
        try AccountSetupModel(
            choice: choice, service: service, creator: AccountCreator(chain: chain), signer: signer, session: session,
            rehearsal: service as? AccountRehearsing, randomSalt: randomSalt ?? { try SorobanAuth.randomBytes(count: 32) }
        )
    }

    private func choice(_ kind: CardChoice.Kind, kind chip: ChipKind = .infineon2Go, pinActive: Bool = false) -> CardChoice {
        let key = chip == .duox ? MockChipReader.p256Key : k1Key
        return CardChoice(kind: kind, card: ChipKeyInfo(kind: chip, publicKey: key, pinActive: pinActive),
                          tokenID: 7, pocket: pocket, pocketIsEmpty: true)
    }
}

extension AccountSetupModel {
    /// Tap en mode répétition à blanc.
    func rehearsalScan() async -> TapOutcome {
        openTapSheet(.rehearsal)
        return await scan()
    }
}

extension MockAccountSetupService {
    fileprivate var lastSalt: Data? { lastPlan?.accountSalt }
}

/// Le vrai chemin de signature (`ChipSigning`) sur une carte simulée, pour contrôler les APDU envoyés.
private struct TransportSigner: ChipSigner {
    let card: RehearsalInfineon

    func sign(digests: [Data], expectedKey: ChipPublicKey, pin: String?) async throws -> [ChipSignedDigest] {
        try await ChipSigning.sign(card, digests: digests, expectedKey: expectedKey, pin: pin)
    }

    func sign(digests: [Data], acceptedKeys: [ChipPublicKey], pin: String?) async throws -> CardSignatures {
        try await ChipSigning.sign(card, digests: digests, acceptedKeys: acceptedKeys, pin: pin)
    }

    func readOrSign(digests: [Data], acceptedKeys: [ChipPublicKey]) async throws -> ReadOrSign {
        try await ChipSigning.readOrSign(card, digests: digests, acceptedKeys: acceptedKeys)
    }

    func setPINAndSign(digests: [Data], expectedKey: ChipPublicKey, newPIN: String) async throws -> PINSetupSignatures {
        try await ChipSigning.setPINAndSign(card, digests: digests, expectedKey: expectedKey, newPIN: newPIN)
    }

    func verifyPIN(expectedKey: ChipPublicKey, pin: String) async throws {
        try await ChipSigning.verifyPIN(card, expectedKey: expectedKey, pin: pin)
    }
}

/// Infineon simulée : lit sa clé, vérifie un PIN, signe (DER fixe) ; garde toutes les commandes reçues.
private final class RehearsalInfineon: APDUTransport, @unchecked Sendable {
    private(set) var sent: [Data] = []
    let key: ChipPublicKey
    let pinActive: Bool

    init(key: ChipPublicKey, pinActive: Bool) {
        self.key = key
        self.pinActive = pinActive
    }

    func send(_ apdu: Data) async throws -> APDUResponse {
        sent.append(apdu)
        let ok = { (data: Data) in APDUResponse(data: data, sw1: 0x90, sw2: 0x00) }
        if apdu == Infineon2Go.selectAPDU { return ok(Data([pinActive ? 0x01 : 0x00])) }
        if apdu.prefix(2) == Data([0x00, 0x16]) { return ok(Data(count: 8) + key.bytes) }
        if apdu.prefix(2) == Data([0x00, 0x44]) { return ok(Data()) }
        if apdu.prefix(2) == Data([0x00, 0x18]) {
            let der = Data(hex: "3044022011111111111111111111111111111111111111111111111111111111111111110220" + String(repeating: "22", count: 32))!
            return ok(Data(count: 8) + der)
        }
        return APDUResponse(data: Data(), sw1: 0x6D, sw2: 0x00)
    }
}

/// Service dont la préparation échoue (réseau).
private struct FailingPrepareService: AccountSetupService {
    func prepare(card: ChipKeyInfo, pocket: String, accountSalt: Data) async throws -> AccountSetupPlan {
        throw StellarError.rpc("The request timed out.")
    }

    func rehearse(_ plan: AccountSetupPlan, signatures: [ChipSignedDigest]) async throws -> RehearsalReport {
        Issue.record("rehearse must not be called")
        throw StellarError.rpc("unexpected")
    }
}
#endif
