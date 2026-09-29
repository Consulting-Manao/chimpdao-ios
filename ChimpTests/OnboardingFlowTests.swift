import Foundation
import Testing
@testable import ChimpDAO

/// Onboarding, étape 2 : stockage local, indice « carte → compte » (`cardHint.ts`), session, aiguillage d'A2.
struct OnboardingFlowTests {
    private let accountA = "CAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    private let accountB = "CBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
    private let card = SavedCard(publicKey: MockChipReader.secp256k1Key.hex, chip: "infineon2Go", tokenID: 7,
                                 pocket: "CPOCKET", name: nil, color: nil)

    // MARK: Indice carte → compte (withHint, cardHint.test.ts)

    @Test("Indice : le plus récent d'abord, une seule entrée par carte")
    func hintNewestFirst() {
        let a = CardHint(key: "a", account: accountA, at: Date(timeIntervalSince1970: 1))
        let b = CardHint(key: "b", account: accountA, at: Date(timeIntervalSince1970: 2))
        let aAgain = CardHint(key: "a", account: accountB, at: Date(timeIntervalSince1970: 3))
        #expect(CardHint.adding(b, to: [a]) == [b, a])
        #expect(CardHint.adding(aAgain, to: [b, a]) == [aAgain, b])
    }

    @Test("Indice : au-delà du plafond, les plus anciens sont oubliés")
    func hintEviction() {
        let old = (1...3).map { CardHint(key: "k\($0)", account: accountA, at: Date(timeIntervalSince1970: Double($0))) }
        let newest = CardHint(key: "new", account: accountB, at: Date(timeIntervalSince1970: 9))
        #expect(CardHint.adding(newest, to: old, maximum: 3) == [newest, old[0], old[1]])
        #expect(CardHint.maximum == 32)
    }

    // MARK: Stockage

    @Test("Fichier JSON : aller-retour, un fichier par réseau, fichier absent = portefeuille vide")
    func fileRoundTrip() throws {
        let directory = try temporaryDirectory()
        let store = try FileLocalWalletStore(network: .testnet, directory: directory)
        #expect(try store.load() == LocalWallet())
        #expect(store.fileURL.lastPathComponent == "wallet-testnet.json")
        let wallet = sampleWallet()
        try store.save(wallet)
        #expect(try store.load() == wallet)
        #expect(try FileLocalWalletStore(network: .mainnet, directory: directory).load() == LocalWallet())
        try store.erase()
        #expect(try store.load() == LocalWallet())
    }

    @Test("Écriture avec la protection de fichier d'iOS (NSFileProtectionComplete)")
    func fileProtectionOption() {
        #expect(FileLocalWalletStore.writingOptions.contains(.completeFileProtection))
        #expect(FileLocalWalletStore.writingOptions.contains(.atomic))
    }

    /// Le simulateur n'applique pas la protection des données : vérifiable seulement sur un iPhone.
    @Test("Fichier protégé sur l'iPhone (attribut NSFileProtectionComplete)", .enabled(if: !OnboardingFlowTests.isSimulator))
    func fileProtection() throws {
        let store = try FileLocalWalletStore(network: .testnet, directory: try temporaryDirectory())
        try store.save(sampleWallet())
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        #expect(attributes[.protectionKey] as? FileProtectionType == .complete)
    }

    @Test("Fichier illisible ou d'une autre version : mis de côté, jamais écrasé, et l'app repart d'un état vide")
    func unreadableFile() throws {
        let store = try FileLocalWalletStore(network: .testnet, directory: try temporaryDirectory())
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(try store.load() == LocalWallet())
        #expect(FileManager.default.fileExists(atPath: store.fileURL.appendingPathExtension("unreadable").path))

        var future = sampleWallet()
        future.version = 99
        try FileLocalWalletStore.encoder.encode(future).write(to: store.fileURL)
        #expect(try store.load() == LocalWallet())
    }

    @Test("Règle 1 : le fichier ne contient que des champs publics (et prénom, nom de carte) — tout nouveau champ doit être relu")
    func noSecretFields() throws {
        let data = try FileLocalWalletStore.encoder.encode(sampleWallet())
        let keys = allKeys(in: try JSONSerialization.jsonObject(with: data))
        #expect(keys == [
            "version", "firstName", "tourSeen", "account", "cardHints",
            "address", "cards", "publicKey", "chip", "tokenID", "pocket", "name", "color",
            "key", "at",
        ])
    }

    // MARK: Session

    @Test("signIn : compte et carte enregistrés, indice ajouté, compte ouvert")
    func sessionSignIn() throws {
        let store = InMemoryLocalWalletStore()
        let session = AppSession(store: store, network: .testnet)
        #expect(!session.hasAccount)
        try session.signIn(account: accountA, card: card, at: Date(timeIntervalSince1970: 5))
        #expect(session.hasAccount)
        #expect(store.wallet.account == SavedAccount(address: accountA, cards: [card]))
        #expect(store.wallet.cardHints == [CardHint(key: card.publicKey, account: accountA, at: Date(timeIntervalSince1970: 5))])
        #expect(store.wallet.hint(for: MockChipReader.secp256k1Key) == accountA)
    }

    @Test("signIn sur le même compte : le nom et la couleur déjà choisis sont gardés")
    func sessionSignInKeepsLocalNames() throws {
        var named = card
        named.name = "Jungle"
        named.color = "jungle"
        let store = InMemoryLocalWalletStore(LocalWallet(account: SavedAccount(address: accountA, cards: [named])))
        let session = AppSession(store: store, network: .testnet)
        try session.signIn(account: accountA, card: card)
        #expect(store.wallet.account?.cards == [named])
    }

    @Test("Écriture impossible : l'erreur remonte et rien ne change en mémoire")
    func sessionSaveFailure() {
        let session = AppSession(store: FailingStore(), network: .testnet)
        #expect(throws: CocoaError.self) { try session.signIn(account: accountA, card: card) }
        #expect(!session.hasAccount)
    }

    // MARK: Aiguillage (A1, visite, A2)

    @Test("Premier lancement : la visite ; ensuite (vue ou passée) : directement la lecture")
    func tourOnlyOnce() {
        let session = AppSession(store: InMemoryLocalWalletStore(), network: .testnet)
        let model = makeModel(session: session)
        model.start()
        #expect(model.path == [.tour])
        model.nextTourPage()
        model.nextTourPage()
        model.nextTourPage()
        #expect(model.tourPage == 3)
        model.nextTourPage()
        #expect(model.path == [.reading])
        #expect(session.wallet.tourSeen)
    }

    @Test("Carte neuve enregistrée → A3 « Fresh card » avec le numéro du NFT")
    func routesFreshCard() async {
        let model = await scanned(.fresh)
        guard case .choice(let choice) = model.path.last else { Issue.record("expected A3, got \(model.path)"); return }
        #expect(choice.kind == .fresh)
        #expect(choice.tokenID == 7)
        #expect(choice.pocketIsEmpty == true)
        #expect(model.readingState == .idle)
    }

    @Test("Carte orpheline → A3 variante « This card is yours »")
    func routesOrphan() async {
        let model = await scanned(.orphan)
        guard case .choice(let choice) = model.path.last else { Issue.record("expected A3"); return }
        #expect(choice.kind == .orphan(lastKnown: MockOnboardingService.memberAccount))
    }

    @Test("Carte non enregistrée, carte sans clé, puce inconnue → H3")
    func routesNotAChimpCard() async {
        #expect(await scanned(.notEnrolled).path.last == .notAChimpCard)
        #expect(await scanned(.fresh, reader: .noKey).path.last == .notAChimpCard)
        #expect(await scanned(.fresh, reader: .unknownChip).path.last == .notAChimpCard)
    }

    @Test("Carte déjà dans un compte → compte ouvert sur le téléphone, sans rien signer")
    func routesMember() async {
        let session = AppSession(store: InMemoryLocalWalletStore(), network: .testnet)
        let model = await scanned(.member, session: session)
        #expect(session.wallet.account?.address == MockOnboardingService.memberAccount)
        #expect(session.wallet.account?.cards.first?.tokenID == 421)
        #expect(model.path == [.reading])
    }

    @Test("Réseau : « unknown » ou panne → « Couldn't check this card », on reste sur A2 (jamais orpheline)")
    func routesNetworkProblems() async {
        for scenario in [MockOnboardingService.Scenario.unknown, .networkError] {
            let model = await scanned(scenario)
            #expect(model.path == [.reading])
            guard case .failed(let problem) = model.readingState else { Issue.record("expected a problem"); continue }
            #expect(problem.kind == .couldntCheck)
            #expect(!problem.technicalDetails.isEmpty)
        }
    }

    @Test("Règle 7 : les erreurs NFC remontent à l'écran (annulation = retour à l'attente, sans message)")
    func nfcErrorsSurface() async {
        let cancelled = await scanned(.fresh, reader: .cancelled)
        #expect(cancelled.readingState == .idle)
        let moved = await scanned(.fresh, reader: .cardRemoved)
        guard case .failed(let problem) = moved.readingState else { Issue.record("expected a problem"); return }
        #expect(problem.kind == .cardMoved)
        #expect(problem.technicalDetails.contains("Tag connection lost"))
    }

    @Test("L'indice mémorisé pour la carte est donné à la résolution")
    func passesHint() async {
        let key = MockChipReader.secp256k1Key.hex
        let store = InMemoryLocalWalletStore(LocalWallet(cardHints: [CardHint(key: key, account: accountB, at: .now)]))
        let service = RecordingService()
        let model = OnboardingModel(session: AppSession(store: store, network: .testnet),
                                    reader: MockChipReader(scenario: .infineon, delay: .zero), service: service,
                                    makeSetup: { try AccountSetupModel(choice: $0, service: MockAccountSetupService(delay: .zero), signer: MockChipSigner(delay: .zero)) })
        model.path = [.reading]
        await model.scan()
        #expect(service.hints == [accountB])
    }

    // MARK: Aides

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private func makeModel(session: AppSession, reader: MockChipReader.Scenario = .infineon,
                           service: MockOnboardingService.Scenario = .fresh) -> OnboardingModel {
        OnboardingModel(session: session, reader: MockChipReader(scenario: reader, delay: .zero),
                        service: MockOnboardingService(scenario: service, delay: .zero),
                        makeSetup: { try AccountSetupModel(choice: $0, service: MockAccountSetupService(delay: .zero), signer: MockChipSigner(delay: .zero)) })
    }

    private func scanned(_ service: MockOnboardingService.Scenario, reader: MockChipReader.Scenario = .infineon,
                         session: AppSession? = nil) async -> OnboardingModel {
        let model = makeModel(session: session ?? AppSession(store: InMemoryLocalWalletStore(), network: .testnet),
                              reader: reader, service: service)
        model.path = [.reading]
        await model.scan()
        return model
    }

    private func sampleWallet() -> LocalWallet {
        var named = card
        named.name = "Jungle"
        named.color = "jungle"
        return LocalWallet(firstName: "Léo", tourSeen: true, account: SavedAccount(address: accountA, cards: [named]),
                           cardHints: [CardHint(key: card.publicKey, account: accountA, at: Date(timeIntervalSince1970: 1_700_000_000))])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func allKeys(in object: Any) -> Set<String> {
        if let dictionary = object as? [String: Any] {
            return dictionary.reduce(into: Set(dictionary.keys)) { $0.formUnion(allKeys(in: $1.value)) }
        }
        if let array = object as? [Any] {
            return array.reduce(into: Set<String>()) { $0.formUnion(allKeys(in: $1)) }
        }
        return []
    }
}

private struct FailingStore: LocalWalletStore {
    func load() throws -> LocalWallet { LocalWallet() }
    func save(_ wallet: LocalWallet) throws { throw CocoaError(.fileWriteNoPermission) }
    func erase() throws {}
}

private final class RecordingService: OnboardingService, @unchecked Sendable {
    private(set) var hints: [String?] = []

    func inspect(_ card: ChipKeyInfo, hint: String?) async throws -> CardInspection {
        hints.append(hint)
        return CardInspection(card: card, resolution: .enrolled, tokenID: 7, pocket: nil, pocketIsEmpty: nil)
    }
}
