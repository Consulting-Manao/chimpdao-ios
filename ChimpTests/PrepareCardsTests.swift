import Foundation
import Testing
@testable import ChimpDAO

#if CHIMP_ADMIN
/// « Prepare cards » (Chimp Admin, Meridian) : l'assistant pas à pas. Clé générée si besoin, numéro et note, argent de
/// départ, enregistrement sur testnet ; journal exportable ; reprise sans double enregistrement ; jamais de PIN.
struct PrepareCardsTests {
    /// Une clé de carte différente par numéro (même format que la vraie : 65 octets, `04…`).
    private func key(_ n: UInt8) -> ChipPublicKey {
        var bytes = MockChipReader.secp256k1Key.bytes
        bytes[bytes.count - 1] = n
        return try! ChipPublicKey(bytes)
    }

    /// La carte posée : vierge (sa clé est générée), déjà munie d'une clé, avec PIN, ou une DUOX.
    private final class FakeCard: ChipReader, ChipKeyGenerator, @unchecked Sendable {
        enum Kind { case blank, keyed, keyedWithPIN, duox }
        var kind: Kind
        var key: ChipPublicKey
        private(set) var generated = 0
        init(_ kind: Kind, key: ChipPublicKey) { self.kind = kind; self.key = key }

        func generateKeyOnEmptySlot() async throws -> ChipKeyInfo {
            switch kind {
            case .blank:
                generated += 1
                kind = .keyed
                return ChipKeyInfo(kind: .infineon2Go, publicKey: key, pinActive: false)
            case .keyed, .keyedWithPIN: throw ChipError.keyAlreadyPresent
            case .duox: throw ChipError.keyGenerationUnsupported("NXP MIFARE DUOX")
            }
        }

        func readKey() async throws -> ChipKeyInfo {
            switch kind {
            case .blank: throw ChipError.noKey(statusWord: 0x6A88)
            case .keyed: return ChipKeyInfo(kind: .infineon2Go, publicKey: key, pinActive: false)
            case .keyedWithPIN: return ChipKeyInfo(kind: .infineon2Go, publicKey: key, pinActive: true)
            case .duox: return ChipKeyInfo(kind: .duox, publicKey: MockChipReader.p256Key, pinActive: false)
            }
        }
    }

    /// Testnet factice : se souvient des cartes enregistrées, compte les `mint`.
    private final class FakeChain: CardEnrolmentService, @unchecked Sendable {
        var enrolled: Set<ChipPublicKey> = []
        private(set) var mints = 0
        var failNextEnrol = false
        func inspect(_ card: ChipKeyInfo) async throws -> EnrolmentInspection {
            let mock = MockCardEnrolmentService(alreadyEnrolled: enrolled.contains(card.publicKey), delay: .zero)
            return try await mock.inspect(card)
        }
        func enrol(_ plan: EnrolmentPlan, signed: ChipSignedDigest) async throws -> EnrolmentResult {
            mints += 1
            enrolled.insert(plan.card.publicKey)
            if failNextEnrol {
                failNextEnrol = false
                throw StellarError.rpc("timeout after sending (mock)")
            }
            return try await MockCardEnrolmentService(delay: .zero).enrol(plan, signed: signed)
        }
    }

    private func model(card: FakeCard, chain: FakeChain, signer: RecordingSigner = RecordingSigner(),
                       store: MemoryPreparedCardsStore = MemoryPreparedCardsStore(),
                       funder: MockTestnetFunding = MockTestnetFunding()) -> PrepareCardsModel {
        funder.delay = .zero
        return PrepareCardsModel(reader: card, generator: card, signer: signer, makeService: { chain }, store: store, funder: funder,
                                 readXLM: { _ in 50 }, now: { Date(timeIntervalSince1970: 1_792_500_000) })
    }

    /// Étapes 1 à 3 : tap, numéro (proposé) et note, montant ; s'arrête avant le tap de l'étape 4.
    private func goToFinishing(_ model: PrepareCardsModel, number: Int? = nil, note: String = "", xlm: Int? = 50) async {
        await model.startCard()
        guard case .identify(let draft) = model.step else { Issue.record("expected identify, got \(model.step)"); return }
        model.confirmIdentity(number: number ?? draft.entry.number, note: note)
        model.chooseStartingMoney(xlm)
    }

    private func finishedEntry(_ model: PrepareCardsModel) -> PreparedCard? {
        if case .ready(let entry) = model.step { return entry }
        Issue.record("expected ready, got \(model.step)")
        return nil
    }

    @Test("Carte vierge : clé créée au tap 1, numéro proposé #001, note, 50 XLM ; la carte signe sans PIN ; journal complet")
    func blankCard() async throws {
        let card = FakeCard(.blank, key: key(1))
        let chain = FakeChain()
        let signer = RecordingSigner()
        let store = MemoryPreparedCardsStore()
        let funder = MockTestnetFunding()
        let model = model(card: card, chain: chain, signer: signer, store: store, funder: funder)
        await model.startCard()
        guard case .identify(let draft) = model.step else { Issue.record("expected identify, got \(model.step)"); return }
        #expect(draft.entry.number == 1 && card.generated == 1)
        model.confirmIdentity(number: 1, note: "  Demo card  ")
        guard case .startingMoney = model.step else { Issue.record("expected startingMoney"); return }
        model.chooseStartingMoney(50)
        guard case .finishing(_, .waitingForTap) = model.step else { Issue.record("expected finishing"); return }
        #expect(model.cards.isEmpty, "Rien n'est écrit avant le tap 2")
        await model.signAndRegister()
        let done = try #require(finishedEntry(model))
        #expect(done.numberText == "#001" && done.note == "Demo card")
        #expect(done.status == .prepared && done.transactionHash != nil && done.wallet.hasPrefix("C"))
        #expect(done.isFunded && done.fundingText == "50 XLM" && funder.funded == [done.wallet])
        #expect(signer.calls.count == 1 && signer.calls[0].pin == nil, "Jamais de PIN")
        #expect(signer.newPINs.isEmpty, "Jamais de SET PIN")
        #expect(chain.mints == 1)
        #expect(store.cards == model.cards && model.cards.count == 1)
        #expect(model.nextNumber == 2 && model.readyCount == 1)
    }

    @Test("Argent de départ : « None » n'envoie rien ; un autre montant est envoyé tel quel et proposé à la carte suivante")
    func startingMoney() async throws {
        let chain = FakeChain()
        let store = MemoryPreparedCardsStore()
        let funder = MockTestnetFunding()
        let first = model(card: FakeCard(.blank, key: key(20)), chain: chain, store: store, funder: funder)
        await goToFinishing(first, xlm: nil)
        await first.signAndRegister()
        let none = try #require(finishedEntry(first))
        #expect(none.funding == .declined && none.fundingText == "none" && !none.needsFunding)
        #expect(funder.funded.isEmpty)
        #expect(first.lastStartingXLM == nil)

        let second = model(card: FakeCard(.blank, key: key(21)), chain: chain, store: store, funder: funder)
        await goToFinishing(second, xlm: 120)
        await second.signAndRegister()
        let custom = try #require(finishedEntry(second))
        #expect(custom.fundingText == "120 XLM" && custom.startingXLM == 120)
        #expect(second.lastStartingXLM == 120, "Proposé à la carte suivante")
    }

    @Test("Montant hors de 1 à 1000 XLM : refusé, on reste à l'étape 3")
    func amountLimits() async {
        let model = model(card: FakeCard(.blank, key: key(22)), chain: FakeChain())
        await model.startCard()
        guard case .identify(let draft) = model.step else { Issue.record("expected identify"); return }
        model.confirmIdentity(number: draft.entry.number, note: "")
        #expect(model.amountProblem(0) != nil && model.amountProblem(1001) != nil && model.amountProblem(nil) != nil)
        #expect(model.amountProblem(1) == nil && model.amountProblem(1000) == nil)
        model.chooseStartingMoney(1001)
        guard case .startingMoney = model.step else { Issue.record("expected startingMoney, got \(model.step)"); return }
    }

    @Test("Argent raté : la carte reste enregistrée ; « Send the test money again » ne renvoie que l'argent, sans tap")
    func moneyRetry() async throws {
        let card = FakeCard(.blank, key: key(11))
        let chain = FakeChain()
        let signer = RecordingSigner()
        let funder = MockTestnetFunding()
        let model = model(card: card, chain: chain, signer: signer, funder: funder)
        await goToFinishing(model)
        guard case .finishing(let draft, _) = model.step else { Issue.record("expected finishing"); return }
        funder.failing = [draft.entry.wallet]
        await model.signAndRegister()
        guard case .finishing(let failed, .moneyFailed) = model.step else { Issue.record("expected moneyFailed, got \(model.step)"); return }
        #expect(failed.entry.status == .prepared && !failed.entry.isFunded)
        #expect(model.cards.first?.status == .prepared, "Notée enregistrée au journal")
        funder.failing = []
        await model.retryMoney()
        let done = try #require(finishedEntry(model))
        #expect(done.isFunded && chain.mints == 1 && signer.calls.count == 1)
    }

    @Test("Enregistrement raté (réponse perdue) : « Tap the card again » relit la chaîne, pas de second mint, puis l'argent")
    func registerRetry() async throws {
        let chain = FakeChain()
        chain.failNextEnrol = true
        let signer = RecordingSigner()
        let funder = MockTestnetFunding()
        let model = model(card: FakeCard(.blank, key: key(12)), chain: chain, signer: signer, funder: funder)
        await goToFinishing(model)
        await model.signAndRegister()
        guard case .finishing(_, .registerFailed) = model.step else { Issue.record("expected registerFailed, got \(model.step)"); return }
        #expect(chain.mints == 1, "Le mint est parti, mais l'app n'a pas eu la réponse")
        await model.retryRegistration()
        let done = try #require(finishedEntry(model))
        #expect(done.status == .alreadyReady && done.isFunded)
        #expect(chain.mints == 1 && signer.calls.count == 1, "Ni second mint ni second tap")
    }

    @Test("Signature refusée par la carte (rien d'envoyé) : « Tap the card again » relit la chaîne, puis la carte resigne")
    func signRetry() async throws {
        let chain = FakeChain()
        let signer = RecordingSigner()
        signer.failNext = ChipError.transport("tag lost")
        let model = model(card: FakeCard(.blank, key: key(13)), chain: chain, signer: signer)
        await goToFinishing(model)
        await model.signAndRegister()
        guard case .finishing(_, .registerFailed) = model.step else { Issue.record("expected registerFailed, got \(model.step)"); return }
        #expect(chain.mints == 0 && model.cards.isEmpty, "Rien n'est parti, rien n'est noté")
        await model.retryRegistration()
        let done = try #require(finishedEntry(model))
        #expect(done.status == .prepared && chain.mints == 1)
    }

    @Test("Session NFC fermée au tap 2 : retour à « Tap the card », rien n'est écrit")
    func cancelAtSign() async {
        let signer = RecordingSigner()
        signer.failNext = ChipError.cancelled
        let model = model(card: FakeCard(.blank, key: key(14)), chain: FakeChain(), signer: signer)
        await goToFinishing(model)
        await model.signAndRegister()
        guard case .finishing(_, .waitingForTap) = model.step else { Issue.record("expected waitingForTap, got \(model.step)"); return }
        #expect(model.cards.isEmpty)
    }

    @Test("Carte déjà dans le journal : sa fiche, rien de signé ; l'argent manquant part depuis la fiche")
    func rescanFromJournal() async throws {
        let card = FakeCard(.blank, key: key(3))
        let chain = FakeChain()
        let signer = RecordingSigner()
        let funder = MockTestnetFunding()
        let model = model(card: card, chain: chain, signer: signer, funder: funder)
        await goToFinishing(model)
        guard case .finishing(let draft, _) = model.step else { Issue.record("expected finishing"); return }
        funder.failing = [draft.entry.wallet]
        await model.signAndRegister()
        funder.failing = []
        await model.startCard()
        guard case .alreadyReady(let sheet) = model.step else { Issue.record("expected alreadyReady, got \(model.step)"); return }
        #expect(sheet.numberText == "#001" && sheet.needsFunding)
        await model.sendMoneyFromSheet()
        guard case .alreadyReady(let funded) = model.step else { Issue.record("expected alreadyReady"); return }
        #expect(funded.isFunded && funder.funded.count == 1)
        await model.sendMoneyFromSheet()
        #expect(funder.funded.count == 1, "Jamais deux fois")
        #expect(chain.mints == 1 && signer.calls.count == 1)
        await model.loadBalance(of: funded.wallet)
        #expect(model.balances[funded.wallet] == .xlm(50))
    }

    @Test("Carte enregistrée ailleurs : étape 2 pour son numéro, puis sa fiche ; rien n'est signé")
    func alreadyOnChain() async {
        let chain = FakeChain()
        chain.enrolled = [key(2)]
        let signer = RecordingSigner()
        let model = model(card: FakeCard(.keyed, key: key(2)), chain: chain, signer: signer)
        await model.startCard()
        guard case .identify(let draft) = model.step else { Issue.record("expected identify, got \(model.step)"); return }
        #expect(draft.plan == nil)
        model.confirmIdentity(number: 7, note: "From the terminal")
        guard case .alreadyReady(let entry) = model.step else { Issue.record("expected alreadyReady"); return }
        #expect(entry.status == .alreadyReady && entry.number == 7 && entry.note == "From the terminal")
        #expect(signer.calls.isEmpty && chain.mints == 0 && model.cards.count == 1)
    }

    @Test("Reprise après une coupure pendant l'envoi : relue sur la chaîne, même numéro et même note, jamais deux mints")
    func resumeAfterInterruption() async throws {
        let card = FakeCard(.blank, key: key(4))
        let chain = FakeChain()
        chain.failNextEnrol = true
        let store = MemoryPreparedCardsStore()
        let first = model(card: card, chain: chain, store: store)
        await goToFinishing(first, note: "Booth")
        await first.signAndRegister()
        let entry = try #require(store.cards.first)
        #expect(entry.number == 1 && !entry.isDone)

        // L'app est rouverte : le journal est relu, la carte retapée.
        let reopened = model(card: card, chain: chain, store: store)
        #expect(reopened.nextNumber == 2)
        await reopened.startCard()
        guard case .alreadyReady(let done) = reopened.step else { Issue.record("expected alreadyReady, got \(reopened.step)"); return }
        #expect(done.number == 1 && done.note == "Booth" && done.status == .alreadyReady && done.needsFunding)
        #expect(chain.mints == 1, "Aucun second enregistrement")
    }

    @Test("Carte qui a déjà un PIN : « can't be prepared », rien n'est signé ni noté")
    func cardWithPIN() async {
        let signer = RecordingSigner()
        let chain = FakeChain()
        let model = model(card: FakeCard(.keyedWithPIN, key: key(5)), chain: chain, signer: signer)
        await model.startCard()
        guard case .cannotPrepare(let reason) = model.step else { Issue.record("expected cannotPrepare, got \(model.step)"); return }
        #expect(reason.contains("PIN"))
        #expect(signer.calls.isEmpty && chain.mints == 0 && model.cards.isEmpty)
    }

    @Test("DUOX : « can't be prepared » (Infineon seulement), rien n'est noté")
    func duox() async {
        let model = model(card: FakeCard(.duox, key: key(6)), chain: FakeChain())
        await model.startCard()
        guard case .cannotPrepare(let reason) = model.step else { Issue.record("expected cannotPrepare"); return }
        #expect(reason.contains("Infineon"))
        #expect(model.cards.isEmpty)
    }

    @Test("Numéro déjà pris par une autre carte : refusé à l'étape 2 avec le numéro, rien n'est écrit")
    func numberTaken() async {
        let chain = FakeChain()
        let store = MemoryPreparedCardsStore()
        let first = model(card: FakeCard(.blank, key: key(7)), chain: chain, store: store)
        await goToFinishing(first)
        await first.signAndRegister()
        let second = model(card: FakeCard(.blank, key: key(8)), chain: chain, store: store)
        await second.startCard()
        guard case .identify(let draft) = second.step else { Issue.record("expected identify"); return }
        #expect(draft.entry.number == 2, "Le suivant est proposé")
        #expect(second.numberProblem(1, for: draft)?.contains("#001") == true)
        #expect(second.numberProblem(0, for: draft) != nil && second.numberProblem(nil, for: draft) != nil)
        second.confirmIdentity(number: 1, note: "")
        guard case .identify = second.step else { Issue.record("expected identify, got \(second.step)"); return }
        #expect(chain.mints == 1 && store.cards.count == 1)
    }

    @Test("CSV : colonne note, une ligne par carte dans l'ordre des numéros, champs avec virgule entre guillemets")
    func csv() async {
        let model = model(card: FakeCard(.blank, key: key(9)), chain: FakeChain())
        await goToFinishing(model, note: "Demo, booth")
        await model.signAndRegister()
        let lines = model.csv.split(separator: "\n").map(String.init)
        #expect(lines.first == "number,note,public_key,wallet_address,transaction_hash,status,test_money,test_money_hash,date")
        #expect(lines.count == 2)
        #expect(lines[1].hasPrefix("#001,\"Demo, booth\",04"))
        #expect(lines[1].contains(",prepared,50 XLM,"))
        #expect(PrepareCardsModel.csvField("failed: a, b") == "\"failed: a, b\"")
    }

    @Test("Ancien journal (sans note ni montant) : relu, 50 XLM par défaut")
    func oldJournal() throws {
        let json = #"[{"number":3,"publicKey":"04ab","wallet":"CABC","status":{"prepared":{}},"date":0,"funding":{"funded":{"hash":"aa"}}}]"#
        let cards = try JSONDecoder().decode([PreparedCard].self, from: Data(json.utf8))
        #expect(cards.first?.note == nil && cards.first?.fundingText == "50 XLM")
    }
}
#endif
