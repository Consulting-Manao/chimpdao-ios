import Foundation
import Testing
@testable import ChimpDAO

#if CHIMP_ADMIN
/// « Prepare cards » (Chimp Admin, Meridian) : un lot de cartes Infineon, clé générée si besoin, enregistrées sur
/// testnet ; journal exportable ; reprise sans double enregistrement ; jamais de PIN.
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
                                 now: { Date(timeIntervalSince1970: 1_792_500_000) })
    }

    @Test("Carte vierge : clé générée, état lu, la carte signe sans PIN, enregistrée ; journal #001 avec wallet et hash")
    func blankCard() async throws {
        let card = FakeCard(.blank, key: key(1))
        let chain = FakeChain()
        let signer = RecordingSigner()
        let store = MemoryPreparedCardsStore()
        let model = model(card: card, chain: chain, signer: signer, store: store)
        await model.scan()
        guard case .readyToSign(let entry, _) = model.step else { Issue.record("expected readyToSign, got \(model.step)"); return }
        #expect(entry.numberText == "#001")
        #expect(card.generated == 1)
        await model.signAndRegister()
        guard case .done(let done) = model.step else { Issue.record("expected done, got \(model.step)"); return }
        #expect(done.status == .prepared && done.transactionHash != nil && done.wallet.hasPrefix("C"))
        #expect(signer.calls.count == 1 && signer.calls[0].pin == nil, "Jamais de PIN")
        #expect(signer.newPINs.isEmpty, "Jamais de SET PIN")
        #expect(chain.mints == 1)
        #expect(store.cards == model.cards && model.cards.count == 1)
        #expect(model.nextNumber == 2, "Le numéro suivant s'incrémente")
    }

    @Test("Argent de test : 50 XLM vers le wallet de la carte après l'enregistrement, noté au journal ; jamais deux fois")
    func funding() async throws {
        let card = FakeCard(.blank, key: key(10))
        let funder = MockTestnetFunding()
        let model = model(card: card, chain: FakeChain(), funder: funder)
        await model.scan()
        await model.signAndRegister()
        guard case .done(let done) = model.step else { Issue.record("expected done, got \(model.step)"); return }
        #expect(done.isFunded && done.fundingText == "50 XLM")
        #expect(funder.funded == [done.wallet], "Le wallet de la carte, une fois")
        await model.scan()
        #expect(funder.funded.count == 1, "Retapée : rien n'est renvoyé")
        #expect(model.fundedCount == 1)
    }

    @Test("Argent de test raté : la carte reste enregistrée ; retapée, seul l'argent repart (pas de second enregistrement)")
    func fundingRetry() async throws {
        let card = FakeCard(.blank, key: key(11))
        let chain = FakeChain()
        let funder = MockTestnetFunding()
        let model = model(card: card, chain: chain, funder: funder)
        await model.scan()
        guard case .readyToSign(let entry, _) = model.step else { Issue.record("expected readyToSign"); return }
        funder.failing = [entry.wallet]
        await model.signAndRegister()
        guard case .done(let failed) = model.step else { Issue.record("expected done"); return }
        #expect(failed.status == .prepared && !failed.isFunded)
        #expect(model.failedCount == 1, "À retaper")
        funder.failing = []
        await model.scan()
        guard case .done(let retried) = model.step else { Issue.record("expected done"); return }
        #expect(retried.isFunded && chain.mints == 1)
        #expect(model.failedCount == 0)
    }

    @Test("Carte déjà enregistrée sur la chaîne : « already ready », rien n'est signé ni écrit")
    func alreadyOnChain() async {
        let card = FakeCard(.keyed, key: key(2))
        let chain = FakeChain()
        chain.enrolled = [key(2)]
        let signer = RecordingSigner()
        let model = model(card: card, chain: chain, signer: signer)
        await model.scan()
        guard case .done(let done) = model.step else { Issue.record("expected done"); return }
        #expect(done.status == .alreadyReady)
        #expect(signer.calls.isEmpty && chain.mints == 0)
    }

    @Test("Carte déjà dans le journal : retapée, elle n'est ni relue sur la chaîne ni enregistrée deux fois")
    func rescanFromJournal() async {
        let card = FakeCard(.blank, key: key(3))
        let chain = FakeChain()
        let model = model(card: card, chain: chain)
        await model.scan()
        await model.signAndRegister()
        await model.scan()
        guard case .done(let done) = model.step else { Issue.record("expected done"); return }
        #expect(done.numberText == "#001" && done.status == .prepared)
        #expect(chain.mints == 1 && model.cards.count == 1 && model.nextNumber == 2)
    }

    @Test("Reprise après une coupure pendant l'envoi : relue sur la chaîne, même numéro, jamais deux enregistrements")
    func resumeAfterInterruption() async throws {
        let card = FakeCard(.blank, key: key(4))
        let chain = FakeChain()
        chain.failNextEnrol = true
        let store = MemoryPreparedCardsStore()
        let first = model(card: card, chain: chain, store: store)
        await first.scan()
        await first.signAndRegister()
        #expect(chain.mints == 1, "Le mint est parti, mais l'app n'a pas eu la réponse")
        let entry = try #require(store.cards.first)
        #expect(entry.number == 1 && !entry.isDone)

        // L'app est rouverte : le journal est relu, la carte retapée.
        let reopened = model(card: card, chain: chain, store: store)
        #expect(reopened.nextNumber == 2)
        await reopened.scan()
        guard case .done(let done) = reopened.step else { Issue.record("expected done, got \(reopened.step)"); return }
        #expect(done.number == 1 && done.status == .alreadyReady)
        #expect(chain.mints == 1, "Aucun second enregistrement")
    }

    @Test("Carte qui a déjà un PIN : mise de côté (on n'en connaît ni n'en définit), rien n'est signé")
    func cardWithPIN() async {
        let card = FakeCard(.keyedWithPIN, key: key(5))
        let signer = RecordingSigner()
        let chain = FakeChain()
        let model = model(card: card, chain: chain, signer: signer)
        await model.scan()
        guard case .done(let done) = model.step else { Issue.record("expected done"); return }
        #expect(done.status == .failed("the card already has a PIN"))
        #expect(signer.calls.isEmpty && chain.mints == 0)
    }

    @Test("DUOX : refusée (Infineon seulement), rien n'est noté")
    func duox() async {
        let model = model(card: FakeCard(.duox, key: key(6)), chain: FakeChain())
        await model.scan()
        guard case .problem(let message) = model.step else { Issue.record("expected problem"); return }
        #expect(message.contains("Infineon"))
        #expect(model.cards.isEmpty)
    }

    @Test("Numéro saisi déjà pris par une autre carte : refus, rien n'est écrit")
    func numberTaken() async {
        let chain = FakeChain()
        let store = MemoryPreparedCardsStore()
        let first = model(card: FakeCard(.blank, key: key(7)), chain: chain, store: store)
        await first.scan()
        await first.signAndRegister()
        let second = model(card: FakeCard(.blank, key: key(8)), chain: chain, store: store)
        second.nextNumber = 1
        await second.scan()
        guard case .problem(let message) = second.step else { Issue.record("expected problem"); return }
        #expect(message.contains("#001"))
        #expect(chain.mints == 1)
    }

    @Test("CSV : en-tête, une ligne par carte dans l'ordre des numéros, champs avec virgule entre guillemets")
    func csv() async {
        let chain = FakeChain()
        let model = model(card: FakeCard(.blank, key: key(9)), chain: chain)
        await model.scan()
        await model.signAndRegister()
        let lines = model.csv.split(separator: "\n").map(String.init)
        #expect(lines.first == "number,public_key,wallet_address,transaction_hash,status,test_money,test_money_hash,date")
        #expect(lines.count == 2)
        #expect(lines[1].hasPrefix("#001,04"))
        #expect(lines[1].contains(",prepared,50 XLM,"))
        #expect(PrepareCardsModel.csvField("failed: a, b") == "\"failed: a, b\"")
    }
}
#endif
