import Foundation
import Testing
import stellarsdk
@testable import ChimpDAO

/// Ajouter une carte (ARCHITECTURE §3.12) : `add_card` (ordre 2) comparé au terminal, puis les parcours G1 → G3
/// (Wallet) et A8 → A9 (rejoindre) sur une fausse chaîne.
struct AddCardTests {
    private let account = "CDU45A6K2WTMLRDUEQ7SXGOUICJVRWSLZCYPLWB7W6FVQLD7LPNRVVFR"
    private let passphrase = ChimpNetworkConfig.testnet.passphrase
    private let k1 = MockChipReader.secp256k1Key
    private let r1 = MockChipReader.p256Key

    // MARK: add_card : valeurs du terminal

    /// Valeurs calculées avec les fonctions de `chip-auth.ts` (`scCardSigner`, `authPayloadHash`) recopiées telles quelles
    /// et exécutées avec `@stellar/stellar-sdk` 17.0.1 (version du `bun.lock` du terminal), le 2026-09-30.
    @Test("Argument de add_card : CardSigner { curve, key } identique à scCardSigner, secp256k1 et P-256")
    func addCardArguments() throws {
        let k1Argument = try #require(CardMembershipClient.addCardArguments(publicKey: k1, curve: .secp256k1).first?.xdrEncoded)
        #expect(k1Argument == "AAAAEQAAAAEAAAACAAAADwAAAAVjdXJ2ZQAAAAAAABAAAAABAAAAAQAAAA8AAAAJU2VjcDI1NmsxAAAAAAAADwAAAANrZXkAAAAADQAAAEEEeb5mfvncu6xVoGKVzocLBwKb/NstzijZWfKBWxb4F5hIOtp3JqPEZV2k+/wOEQio/Re0SKaFVBmcR9CP+xDUuAAAAA==")
        let r1Argument = try #require(CardMembershipClient.addCardArguments(publicKey: r1, curve: .p256).first?.xdrEncoded)
        #expect(r1Argument == "AAAAEQAAAAEAAAACAAAADwAAAAVjdXJ2ZQAAAAAAABAAAAABAAAAAQAAAA8AAAAJU2VjcDI1NnIxAAAAAAAADwAAAANrZXkAAAAADQAAAEEEaxfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54WK84zV2sxXs7LtkBoN79R9QAAAA==")
    }

    @Test("Entrée add_card V1 du compte : digest identique à authPayloadHash (nonce positif et négatif)")
    func addCardDigestV1() throws {
        let cases: [(ChipPublicKey, ChipCurve, Int64, String)] = [
            (k1, .secp256k1, 7, "e268d88b577c277aa14d0c649b7c61d2577b9a54caa860d0eea817bcb5267d25"),
            (k1, .secp256k1, -42, "dc8b00fabeefba8f01b23533b3df607b47be8a2ab3fe9f463a849bc288137a23"),
            (r1, .p256, 7, "d68afc865597c139ed8cb9d2e9a1cc7e5b64239ea9e76afeed36b8ed28334d99"),
            (r1, .p256, -42, "da1b0c4d781cb8bf17e1c84e52a31acb3f0a9a3205d430ee371f29425ce6c315"),
        ]
        for (key, curve, nonce, digest) in cases {
            let declared = try DeclaredAuthorization(
                authorizer: account,
                invocation: try SorobanAuth.contractInvocation(
                    contract: account, function: "add_card", arguments: CardMembershipClient.addCardArguments(publicKey: key, curve: curve)
                ),
                passphrase: passphrase, expirationLedger: 1120, nonce: nonce
            )
            #expect(declared.digest.hexString == digest)
        }
    }

    @Test("Entrée add_card V2 reçue de la simulation : digest V2 identique au terminal, et c'est bien l'appel demandé (règles 4 et 8)")
    func addCardDigestV2() throws {
        let received = try XDRDecoder.decode(SorobanAuthorizationEntryXDR.self, data: Data(base64Encoded: Self.addCardV2K1)!)
        let pending = try SorobanAuth.pendingEntries([received], signer: account, passphrase: passphrase, expirationLedger: 1120)
        #expect(pending.count == 1)
        #expect(pending[0].digest.hexString == "7992869c12dabe159c650cce9351ac59ab14f513674e56309dc95a8635d5f248")
        let expected = try SorobanAuth.contractInvocation(
            contract: account, function: "add_card", arguments: CardMembershipClient.addCardArguments(publicKey: k1, curve: .secp256k1)
        )
        #expect(try XDREncoder.encode(pending[0].entry.rootInvocation) == XDREncoder.encode(expected))
        // Une autre carte dans l'appel : ce n'est plus l'appel demandé, rien ne serait signé.
        let other = try SorobanAuth.contractInvocation(
            contract: account, function: "add_card", arguments: CardMembershipClient.addCardArguments(publicKey: r1, curve: .p256)
        )
        #expect(try XDREncoder.encode(pending[0].entry.rootInvocation) != XDREncoder.encode(other))
    }

    // MARK: G1 → G3 (Wallet)

    @Test("Wallet : lire la nouvelle carte, nom, nouveau PIN, un tap (SET PIN + set_owner), code, une carte du compte (add_card), G3")
    func walletHappyPath() async throws {
        let (session, store) = walletSession()
        let service = MockAddCardService(delay: .zero)
        let signer = RecordingSigner()
        let model = AddCardModel(entry: .wallet(account: account), session: session,
                                 reader: MockChipReader(scenario: .infineon, delay: .zero), signer: signer, service: service)
        #expect(model.screen == .tapNew)
        #expect(model.cardColor == .jungle, "Couleur par défaut : une que le compte n'utilise pas encore (la carte n°7 est Banana)")

        await model.scanNewCard()
        #expect(model.screen == .nameCard)
        #expect(model.pinMode == .choose)
        #expect(model.cardNumber == "0913")
        model.cardName = "Leaf"
        model.cardColor = .leaf
        model.continueFromCard()
        #expect(model.screen == .pin)
        model.pinCompleted("1234")
        model.pinCompleted("1234")
        model.continueFromPIN()
        #expect(model.screen == .confirm)

        model.openTapSheet()
        #expect(model.isShowingTapSheet)
        await model.scanNewCardToSign()
        #expect(signer.newPINs == ["1234"])
        #expect(signer.calls.last?.expectedKey == k1)
        #expect(model.screen == .unlockCode)
        #expect(model.unlockCode != nil)
        model.acknowledgeUnlockCode()
        #expect(model.screen == .member)
        #expect(model.unlockCode == nil)

        #expect(model.memberUsesPIN)
        model.startMemberStep()
        #expect(model.isShowingMemberPINSheet)
        model.memberPINEntered("4321")
        #expect(model.isShowingMemberTapSheet)
        await model.scanMember()
        #expect(signer.calls.last?.pin == "4321")
        #expect(signer.calls.last?.expectedKey == r1, "Seules les cartes du compte peuvent dire oui")
        #expect(model.screen == .done)
        #expect(service.linkCount == 1 && service.addCount == 1)
        #expect(model.cardCount == 2)

        let saved = try #require(store.wallet.account?.cards.first { $0.publicKey == k1.hex })
        #expect(saved == SavedCard(publicKey: k1.hex, chip: "infineon2Go", tokenID: 913, pocket: MockAddCardService.pocket(for: k1), name: "Leaf", color: "leaf"))
        #expect(store.wallet.hint(for: k1) == account, "Une carte ajoutée n'a que son indice pour retrouver son compte")
        #expect(store.wallet.account?.cards.count == 2)

        // Historique (session « Activity ») : la carte entrée, avec la carte du compte qui a dit oui.
        let rows = session.activity.activity(of: account).records
        #expect(rows.count == 1)
        #expect(rows.first?.event == .cardAdded)
        #expect(rows.first?.cardKey == k1.hex)
        #expect(rows.first?.approvedBy == r1.hex)
        #expect(rows.first?.isLocal == true)
        #expect(rows.first?.id == "stellar:\(rows.first?.hash ?? "")")
    }

    // MARK: Clarté (retour du call avec Pamphile, 2026-10-01)

    @Test("« Step x of y » : Wallet en 5 étapes (4 pour une DUOX), rejoindre en 6 ; le code de déblocage reste à l'étape du tap")
    func progressSteps() async {
        let model = AddCardModel(entry: .wallet(account: account), session: walletSession().0,
                                 reader: MockChipReader(scenario: .infineon, delay: .zero), signer: RecordingSigner(),
                                 service: MockAddCardService(delay: .zero))
        #expect(model.progress(at: .tapNew)! == (1, 5), "Avant la lecture : on compte l'étape du PIN")
        await model.scanNewCard()
        #expect(model.progress(at: .nameCard)! == (2, 5))
        #expect(model.progress(at: .pin)! == (3, 5))
        #expect(model.progress(at: .confirm)! == (4, 5))
        #expect(model.progress(at: .unlockCode)! == (4, 5))
        #expect(model.progress(at: .member)! == (5, 5))
        #expect(model.progress(at: .adding) == nil)

        let duox = AddCardModel(entry: .wallet(account: account), session: walletSession().0,
                                reader: MockChipReader(scenario: .duox, delay: .zero), signer: RecordingSigner(),
                                service: MockAddCardService(delay: .zero))
        await duox.scanNewCard()
        #expect(duox.progress(at: .confirm)! == (3, 4), "Pas de PIN sur une DUOX")
        #expect(duox.progress(at: .pin) == nil)

        let join = AddCardModel(entry: .join, session: walletSession().0, reader: MockChipReader(scenario: .infineon, delay: .zero),
                                signer: RecordingSigner(), service: MockAddCardService(delay: .zero),
                                newCard: ChipKeyInfo(kind: .infineon2Go, publicKey: k1, pinActive: false), tokenID: 913)
        #expect(join.progress(at: .firstName)! == (1, 6))
        #expect(join.progress(at: .findAccount)! == (4, 6))
        #expect(join.progress(at: .member)! == (6, 6))
    }

    @Test("Plusieurs cartes dans le compte : on choisit d'abord celle qui dit oui ; PIN et tap sont pour elle seule")
    func chooseTheMemberCard() async throws {
        let jungleKey = "04" + String(repeating: "ab", count: 64)
        let store = InMemoryLocalWalletStore(LocalWallet(
            firstName: "Barth", tourSeen: true,
            account: SavedAccount(address: account, cards: [
                SavedCard(publicKey: r1.hex, chip: "infineon2Go", tokenID: 7, pocket: "CPOCKET7", name: "Banana", color: "banana"),
                SavedCard(publicKey: jungleKey, chip: "duox", tokenID: 8, pocket: "CPOCKET8", name: "Jungle", color: "jungle"),
            ])
        ))
        let service = MockAddCardService(delay: .zero)
        let signer = MemberTapSigner(newCard: k1, member: r1)
        let model = AddCardModel(entry: .wallet(account: account), session: AppSession(store: store, config: .testnet),
                                 reader: MockChipReader(scenario: .infineonWithPIN, delay: .zero), signer: signer, service: service)
        await model.scanNewCard()
        model.cardName = "Leaf"
        model.continueFromCard()
        model.pinCompleted("1234")
        model.continueFromPIN()
        model.openTapSheet()
        await model.scanNewCardToSign()
        #expect(model.screen == .member)

        #expect(model.memberCandidates.map(\.name) == ["Banana", "Jungle"], "Jamais la nouvelle carte")
        #expect(model.needsMemberChoice)
        model.startMemberStep()
        #expect(!model.isShowingMemberPINSheet && !model.isShowingMemberTapSheet, "Rien avant le choix")

        // Jungle (DUOX) choisie : pas de PIN ; mais c'est Banana qui est tapée → refus, rien d'envoyé.
        model.chooseMember(jungleKey)
        #expect(model.expectedMemberName == "Jungle")
        #expect(model.expectedMemberColor == .jungle)
        #expect(!model.memberUsesPIN)
        await model.scanMember()
        #expect(model.problem?.kind == .notTheChosenCard("Jungle"))
        #expect(service.addCount == 0)

        // Banana choisie : son PIN, puis le tap de Banana.
        model.chooseMember(r1.hex)
        #expect(model.problem == nil)
        #expect(model.memberUsesPIN)
        model.startMemberStep()
        #expect(model.isShowingMemberPINSheet)
        model.memberPINEntered("4321")
        await model.scanMember()
        #expect(signer.memberAccepted == [r1], "Seule la carte choisie est acceptée")
        #expect(signer.memberPIN == "4321")
        #expect(model.screen == .done)
    }

    @Test("Nouvelle carte refusée : déjà dans le compte, dans un autre compte, jamais enregistrée ; on reste sur G1")
    func refusedNewCards() async {
        let cases: [(MockAddCardService.Scenario, AddCardProblem.Kind)] = [
            (.alreadyInAccount, .alreadyInAccount), (.otherAccount, .otherAccount), (.notEnrolled, .notAChimpCard),
        ]
        for (scenario, kind) in cases {
            let model = AddCardModel(entry: .wallet(account: account), session: walletSession().0,
                                     reader: MockChipReader(scenario: .infineon, delay: .zero), signer: RecordingSigner(),
                                     service: MockAddCardService(scenario: scenario, delay: .zero))
            await model.scanNewCard()
            #expect(model.problem?.kind == kind)
            #expect(model.screen == .tapNew)
        }
    }

    @Test("Carte sans clé ou puce inconnue : pas une vraie carte ; annulation : pas de message")
    func notAChimpCard() async {
        for (reader, kind) in [(MockChipReader.Scenario.noKey, AddCardProblem.Kind?.some(.notAChimpCard)), (.cancelled, nil)] {
            let model = AddCardModel(entry: .wallet(account: account), session: walletSession().0,
                                     reader: MockChipReader(scenario: reader, delay: .zero), signer: RecordingSigner(),
                                     service: MockAddCardService(delay: .zero))
            await model.scanNewCard()
            #expect(model.problem?.kind == kind)
        }
    }

    @Test("DUOX : pas de PIN, le tap signe sans PIN, pas de code de déblocage")
    func duoxNewCard() async {
        let service = MockAddCardService(delay: .zero)
        service.members = [k1]
        let signer = RecordingSigner()
        let model = AddCardModel(entry: .wallet(account: account), session: walletSession().0,
                                 reader: MockChipReader(scenario: .duox, delay: .zero), signer: signer, service: service)
        await model.scanNewCard()
        #expect(model.pinMode == .none)
        model.cardName = "Pinky"
        model.continueFromCard()
        #expect(model.screen == .confirm)
        model.openTapSheet()
        await model.scanNewCardToSign()
        #expect(signer.newPINs.isEmpty)
        #expect(signer.calls.last?.pin == nil)
        #expect(model.screen == .member)
    }

    @Test("La nouvelle carte tapée à la place d'une carte du compte : refus (« a card can't invite itself »), rien d'envoyé")
    func newCardCannotVouch() async {
        let service = MockAddCardService(delay: .zero)
        let signer = TappingSigner(tapped: k1)
        let model = await atMemberStep(service: service, signer: signer)
        await model.scanMember()
        #expect(model.problem?.kind == .isTheNewCard)
        #expect(model.screen == .member)
        #expect(service.addCount == 0)
    }

    @Test("Réseau pendant add_card : « Try again » reprend sans renvoyer set_owner")
    func resumeAfterNetworkError() async {
        let service = MockAddCardService(scenario: .networkWhileAdding, delay: .zero)
        let model = await atMemberStep(service: service, signer: RecordingSigner())
        model.memberPIN = "4321"
        await model.scanMember()
        guard case .failed(.admitting, let problem) = model.addingPhase else { Issue.record("expected a failure while admitting"); return }
        #expect(problem.kind == .network)
        #expect(!problem.needsNewTap)
        await model.runAdding()
        #expect(model.screen == .done)
        #expect(service.linkCount == 1, "set_owner n'est envoyé qu'une fois")
        #expect(service.addCount == 2)
    }

    @Test("Cérémonie reprise : la Pocket nomme déjà le compte, pas de PIN ni de tap de la nouvelle carte, seulement add_card")
    func resumedCeremony() async {
        let service = MockAddCardService(delay: .zero)
        let signer = RecordingSigner()
        // Premier essai interrompu après le lien.
        _ = try? await service.submitLink(
            try PocketClient.declareSetOwner(pocket: MockAddCardService.pocket(for: k1), newOwner: account, passphrase: passphrase, currentLedger: 1000, nonce: 1),
            pocket: MockAddCardService.pocket(for: k1), account: account, curve: .secp256k1, signed: .secp256k1(signature: Data(count: 64))
        )
        let model = AddCardModel(entry: .wallet(account: account), session: walletSession().0,
                                 reader: MockChipReader(scenario: .infineon, delay: .zero), signer: signer, service: service)
        await model.scanNewCard()
        #expect(model.addable?.needsLink == false)
        model.cardName = "Leaf"
        model.continueFromCard()
        #expect(model.screen == .confirm)
        #expect(!model.newCardMustSign)
        model.openTapSheet()
        #expect(model.screen == .member)
        model.memberPIN = "4321"
        await model.scanMember()
        #expect(model.screen == .done)
        #expect(service.linkCount == 1, "Seulement l'envoi du premier essai")
        #expect(signer.newPINs.isEmpty)
    }

    // MARK: A8 → A9 (rejoindre depuis l'onboarding)

    @Test("Rejoindre : prénom, nom, PIN, une carte du compte (lecture), la nouvelle carte signe, la même carte du compte dit oui, A9")
    func joinHappyPath() async throws {
        let store = InMemoryLocalWalletStore(LocalWallet(tourSeen: true))
        let session = AppSession(store: store, config: .testnet)
        let service = MockAddCardService(delay: .zero)
        let signer = RecordingSigner()
        let newCard = ChipKeyInfo(kind: .infineon2Go, publicKey: k1, pinActive: false)
        let model = AddCardModel(entry: .join, session: session, reader: MockChipReader(scenario: .duox, delay: .zero),
                                 signer: signer, service: service, newCard: newCard, tokenID: 913)
        #expect(model.screen == .firstName)
        model.firstName = "Léo"
        model.continueFromName()
        model.cardName = "Leaf"
        model.continueFromCard()
        model.pinCompleted("1234")
        model.pinCompleted("1234")
        model.continueFromPIN()
        #expect(model.screen == .findAccount)

        await model.scanForAccount()
        #expect(model.account == MockOnboardingService.memberAccount)
        #expect(model.member?.publicKey == r1)
        #expect(model.screen == .confirm)

        model.openTapSheet()
        await model.scanNewCardToSign()
        model.acknowledgeUnlockCode()
        #expect(model.screen == .member)
        #expect(!model.memberUsesPIN, "La carte lue en A8 est une DUOX")
        model.startMemberStep()
        #expect(model.isShowingMemberTapSheet)
        await model.scanMember()
        #expect(signer.calls.last?.expectedKey == r1)
        #expect(model.screen == .done)
        #expect(store.wallet.account?.address == MockOnboardingService.memberAccount)
        #expect(store.wallet.firstName == "Léo")
        #expect(session.showsOnboarding, "A9 reste affiché jusqu'à « Let's swing »")
        model.finish()
        #expect(!session.showsOnboarding)
    }

    @Test("Rejoindre : la nouvelle carte tapée en A8, ou une carte d'aucun compte : refus, on reste en A8")
    func joinWrongCards() async {
        let newCard = ChipKeyInfo(kind: .infineon2Go, publicKey: k1, pinActive: false)
        let same = AddCardModel(entry: .join, session: AppSession(store: InMemoryLocalWalletStore(), config: .testnet),
                                reader: MockChipReader(scenario: .infineon, delay: .zero), signer: RecordingSigner(),
                                service: MockAddCardService(delay: .zero), newCard: newCard)
        await same.scanForAccount()
        #expect(same.problem?.kind == .isTheNewCard)

        let service = MockAddCardService(delay: .zero)
        service.memberAccount = nil
        let stranger = AddCardModel(entry: .join, session: AppSession(store: InMemoryLocalWalletStore(), config: .testnet),
                                    reader: MockChipReader(scenario: .duox, delay: .zero), signer: RecordingSigner(),
                                    service: service, newCard: newCard)
        await stranger.scanForAccount()
        #expect(stranger.problem?.kind == .notAMember)
        #expect(stranger.account == nil)
    }

    @Test("A3 : « Join » ouvre le parcours pour une carte neuve seulement, et seulement si le service existe")
    func joinFromA3() {
        let choice = CardChoice(kind: .fresh, card: ChipKeyInfo(kind: .infineon2Go, publicKey: k1, pinActive: false), tokenID: 913, pocket: nil, pocketIsEmpty: true)
        let session = AppSession(store: InMemoryLocalWalletStore(), config: .testnet)
        let withJoin = OnboardingModel(session: session, reader: MockChipReader(delay: .zero), service: MockOnboardingService(delay: .zero),
                                       signer: RecordingSigner(), joinService: MockAddCardService(delay: .zero), makeSetup: { _ in throw CancellationError() })
        withJoin.startJoin(with: choice)
        #expect(withJoin.path.last == .join)
        #expect(withJoin.join != nil)
        withJoin.leaveJoin()
        #expect(withJoin.join == nil)

        let orphan = CardChoice(kind: .orphan(lastKnown: nil), card: choice.card, tokenID: 913, pocket: nil, pocketIsEmpty: nil)
        withJoin.startJoin(with: orphan)
        #expect(withJoin.join == nil, "Une carte orpheline ne rejoint pas (décision du 2026-09-29)")

        let withoutJoin = OnboardingModel(session: session, reader: MockChipReader(delay: .zero), service: MockOnboardingService(delay: .zero),
                                          signer: RecordingSigner(), makeSetup: { _ in throw CancellationError() })
        #expect(!withoutJoin.canJoin)
    }

    // MARK: Aides

    private func walletSession() -> (AppSession, InMemoryLocalWalletStore) {
        let store = InMemoryLocalWalletStore(LocalWallet(
            firstName: "Barth", tourSeen: true,
            account: SavedAccount(address: account, cards: [
                SavedCard(publicKey: r1.hex, chip: "infineon2Go", tokenID: 7, pocket: "CPOCKET7", name: "Banana", color: "banana"),
            ])
        ))
        return (AppSession(store: store, config: .testnet), store)
    }

    /// Parcours Wallet arrêté sur G2, nouvelle carte Infineon avec PIN déjà défini.
    private func atMemberStep(service: MockAddCardService, signer: ChipSigner) async -> AddCardModel {
        let model = AddCardModel(entry: .wallet(account: account), session: walletSession().0,
                                 reader: MockChipReader(scenario: .infineonWithPIN, delay: .zero), signer: signer, service: service)
        await model.scanNewCard()
        model.cardName = "Leaf"
        model.continueFromCard()
        model.pinCompleted("1234")
        model.continueFromPIN()
        model.openTapSheet()
        await model.scanNewCardToSign()
        return model
    }

    /// Entrée `add_card` V2 (nonce 7, expiration 1120) pour la clé secp256k1 de test, construite par le SDK JS 17.0.1.
    static let addCardV2K1 = "AAAAAgAAAAHpzoPK1abFxHQkPyuZ1ECTWNpLyLD12D+3i1gsf1vbGgAAAAAAAAAHAAAEYAAAAAEAAAAAAAAAAenOg8rVpsXEdCQ/K5nUQJNY2kvIsPXYP7eLWCx/W9saAAAACGFkZF9jYXJkAAAAAQAAABEAAAABAAAAAgAAAA8AAAAFY3VydmUAAAAAAAAQAAAAAQAAAAEAAAAPAAAACVNlY3AyNTZrMQAAAAAAAA8AAAADa2V5AAAAAA0AAABBBHm+Zn753LusVaBilc6HCwcCm/zbLc4o2VnygVsW+BeYSDradyajxGVdpPv8DhEIqP0XtEimhVQZnEfQj/sQ1LgAAAAAAAAA"
}

/// Signataire dont la carte « posée » est toujours `tapped` : signe si elle est acceptée, sinon la refuse comme
/// `ChipSigning` (sans rien lui envoyer d'autre).
private final class TappingSigner: ChipSigner, @unchecked Sendable {
    let tapped: ChipPublicKey
    init(tapped: ChipPublicKey) { self.tapped = tapped }

    func sign(digests: [Data], expectedKey: ChipPublicKey, pin: String?) async throws -> [ChipSignedDigest] {
        guard expectedKey == tapped else { throw ChipError.wrongCard }
        return digests.map { _ in .secp256k1(signature: Data(repeating: 0x11, count: 64)) }
    }

    func sign(digests: [Data], acceptedKeys: [ChipPublicKey], pin: String?) async throws -> CardSignatures {
        guard acceptedKeys.contains(tapped) else { throw ChipError.cardNotAccepted(tapped: tapped) }
        return CardSignatures(card: ChipKeyInfo(kind: .infineon2Go, publicKey: tapped, pinActive: true),
                              signatures: try await sign(digests: digests, expectedKey: tapped, pin: pin))
    }

    func readOrSign(digests: [Data], acceptedKeys: [ChipPublicKey]) async throws -> ReadOrSign {
        .signed(try await sign(digests: digests, acceptedKeys: acceptedKeys, pin: nil))
    }

    func setPINAndSign(digests: [Data], expectedKey: ChipPublicKey, newPIN: String) async throws -> PINSetupSignatures {
        PINSetupSignatures(puk: nil, signatures: try await sign(digests: digests, expectedKey: expectedKey, pin: newPIN))
    }

    func verifyPIN(expectedKey: ChipPublicKey, pin: String) async throws {}
}

/// Signe avec la nouvelle carte quand on l'attend, puis tape toujours `member` à l'étape d'une carte du compte.
private final class MemberTapSigner: ChipSigner, @unchecked Sendable {
    let newCard: ChipPublicKey
    let member: ChipPublicKey
    private(set) var memberAccepted: [ChipPublicKey] = []
    private(set) var memberPIN: String?

    init(newCard: ChipPublicKey, member: ChipPublicKey) {
        self.newCard = newCard
        self.member = member
    }

    func sign(digests: [Data], expectedKey: ChipPublicKey, pin: String?) async throws -> [ChipSignedDigest] {
        digests.map { _ in .secp256k1(signature: Data(repeating: 0x11, count: 64)) }
    }

    func sign(digests: [Data], acceptedKeys: [ChipPublicKey], pin: String?) async throws -> CardSignatures {
        guard acceptedKeys.contains(member) else { throw ChipError.cardNotAccepted(tapped: member) }
        memberAccepted = acceptedKeys
        memberPIN = pin
        return CardSignatures(card: ChipKeyInfo(kind: .infineon2Go, publicKey: member, pinActive: true),
                              signatures: try await sign(digests: digests, expectedKey: member, pin: pin))
    }

    func readOrSign(digests: [Data], acceptedKeys: [ChipPublicKey]) async throws -> ReadOrSign {
        .signed(try await sign(digests: digests, acceptedKeys: acceptedKeys, pin: nil))
    }

    func setPINAndSign(digests: [Data], expectedKey: ChipPublicKey, newPIN: String) async throws -> PINSetupSignatures {
        PINSetupSignatures(puk: nil, signatures: try await sign(digests: digests, expectedKey: expectedKey, pin: newPIN))
    }

    func verifyPIN(expectedKey: ChipPublicKey, pin: String) async throws {}
}
