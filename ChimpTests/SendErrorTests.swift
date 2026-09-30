import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Jalon 7, étapes 3 et 4 : envoi depuis le wallet d'une carte, C7 (mauvaise carte) dans chaque variante, ordre
/// « tap puis PIN » sur le vrai chemin (premier tap qui signe si la carte n'a pas de PIN, second tap limité à la carte
/// lue), raisons d'un échec après la signature.
struct SendErrorTests {
    private let digest = Data((0..<32).map { UInt8($0) })
    private let k1Key = MockChipReader.secp256k1Key
    private let r1Key = MockChipReader.p256Key

    private func reviewReady(
        drawerID: String,
        order: SigningOrder = .pinThenTap,
        cards: MockSendService.CardSetup = .allWithPin
    ) async -> (SendFlowModel, MockSendService) {
        let service = MockSendService(cardSetup: cards, delay: .zero, nfcDelay: .zero)
        let model = SendFlowModel(service: service, signingOrder: order)
        await model.loadIfNeeded()
        model.choose(SendContact(id: "maya", name: "Maya", color: .pink, address: MockSendService.mayaAddress))
        model.select(drawerID: drawerID)
        model.setAmount(10)
        model.continueToReview()
        return (model, service)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func isSent(_ model: SendFlowModel) -> Bool {
        if case .finished(.sent) = model.signingStage { return true }
        return false
    }

    private func wrongCard(_ model: SendFlowModel) -> (WrongCard, SigningStep)? {
        if case .wrongCard(let card, let retry) = model.signingStage { return (card, retry) }
        return nil
    }

    // MARK: Core : premier tap (readOrSign)

    @Test("readOrSign, carte avec PIN : lue seulement (SELECT, GET KEY INFO), ni VERIFY PIN ni SIGN")
    func readOrSignWithPIN() async throws {
        let card = FakeInfineon(key: k1Key, pinActive: true)
        let result = try await ChipSigning.readOrSign(card, digests: [digest], acceptedKeys: [k1Key])
        guard case .needsPIN(let info) = result else { Issue.record("expected needsPIN"); return }
        #expect(info.publicKey == k1Key)
        #expect(!card.sent.contains { $0.count > 1 && ($0[1] == 0x44 || $0[1] == 0x18) })
    }

    @Test("readOrSign, carte sans PIN : signe dans le même tap, sans VERIFY PIN")
    func readOrSignWithoutPIN() async throws {
        let card = FakeInfineon(key: k1Key, pinActive: false)
        let result = try await ChipSigning.readOrSign(card, digests: [digest], acceptedKeys: [r1Key, k1Key])
        guard case .signed(let signed) = result else { Issue.record("expected signed"); return }
        #expect(signed.card.publicKey == k1Key)
        #expect(signed.signatures.count == 1)
        #expect(!card.sent.contains { $0.count > 1 && $0[1] == 0x44 })
        #expect(card.sent.last?.hexString == "0018010020" + digest.hexString + "00")
    }

    @Test("readOrSign, carte refusée : refus avec sa clé, aucune commande après la lecture")
    func readOrSignRefused() async {
        let card = FakeInfineon(key: k1Key, pinActive: false)
        await #expect(throws: ChipError.cardNotAccepted(tapped: k1Key)) {
            try await ChipSigning.readOrSign(card, digests: [digest], acceptedKeys: [r1Key])
        }
        #expect(!card.sent.contains { $0.count > 1 && ($0[1] == 0x44 || $0[1] == 0x18) })
    }

    // MARK: C7 · Wrong card

    @Test("Wallet de Jungle, Banana tapée : « Wrong banana! », retaper Jungle avec le même PIN, rien d'envoyé")
    func otherCardOfTheAccount() async {
        let (model, service) = await reviewReady(drawerID: "0421")
        service.nextSignError = ChipError.cardNotAccepted(tapped: k1Key)
        model.confirmReview()
        await waitUntil { model.signingStage == .enteringPin }
        model.pinEntered("1234")
        model.scanCard()
        await waitUntil { wrongCard(model) != nil }
        guard let (card, retry) = wrongCard(model) else { Issue.record("expected C7"); return }
        #expect(card == WrongCard(reason: .otherWallet, tapped: KnownCard(name: "Banana", color: .banana), needed: KnownCard(name: "Jungle", color: .jungle)))
        #expect(retry == .tapToSign)
        #expect(!model.isSigningLocked, "Rien n'est signé : on peut annuler")
        #expect(service.submitCount == 0)

        model.retryAfterWrongCard()
        #expect(model.signingStage == .waitingForTap(.tapToSign))
        #expect(model.pin == "1234", "Le PIN reste pour retaper la bonne carte")
        model.scanCard()
        await waitUntil { isSent(model) }
        #expect(service.lastPin == "1234")
        #expect(model.pin.isEmpty)
    }

    @Test("Wallet d'une carte, carte inconnue : « That card isn't one of yours », carte attendue affichée")
    func unknownCardForAWallet() async {
        let (model, service) = await reviewReady(drawerID: "0421")
        service.nextSignError = ChipError.cardNotAccepted(tapped: r1Key)
        model.confirmReview()
        await waitUntil { model.signingStage == .enteringPin }
        model.pinEntered("1234")
        model.scanCard()
        await waitUntil { wrongCard(model) != nil }
        #expect(wrongCard(model)?.0 == WrongCard(reason: .notYours, tapped: nil, needed: KnownCard(name: "Jungle", color: .jungle)))
    }

    @Test("Main account, carte hors du compte : « Any card of your account can sign », pas de carte attendue")
    func unknownCardForMain() async {
        let (model, service) = await reviewReady(drawerID: "main")
        service.nextSignError = ChipError.cardNotAccepted(tapped: r1Key)
        model.confirmReview()
        await waitUntil { model.signingStage == .enteringPin }
        model.pinEntered("1234")
        model.scanCard()
        await waitUntil { wrongCard(model) != nil }
        #expect(wrongCard(model)?.0 == WrongCard(reason: .notYours, tapped: nil, needed: nil))
    }

    @Test("C7 puis « Cancel » : retour à la vérification, PIN effacé, rien de préparé")
    func cancelFromWrongCard() async {
        let (model, service) = await reviewReady(drawerID: "0421")
        service.nextSignError = ChipError.cardNotAccepted(tapped: k1Key)
        model.confirmReview()
        await waitUntil { model.signingStage == .enteringPin }
        model.pinEntered("1234")
        model.scanCard()
        await waitUntil { wrongCard(model) != nil }
        model.cancelSigning()
        #expect(model.signingStage == .idle)
        #expect(model.pin.isEmpty)
    }

    // MARK: Tap puis PIN (vrai chemin)

    @Test("Tap puis PIN : le premier tap refusé mène à C7 avant tout PIN")
    func tapThenPinFirstTapRefused() async {
        let (model, service) = await reviewReady(drawerID: "0421", order: .tapThenPin)
        service.nextReadError = ChipError.cardNotAccepted(tapped: k1Key)
        model.confirmReview()
        await waitUntil { model.signingStage == .waitingForTap(.tapToRead) }
        model.scanCard()
        await waitUntil { wrongCard(model) != nil }
        #expect(wrongCard(model)?.1 == .tapToRead)
        #expect(service.signCount == 0)
        model.retryAfterWrongCard()
        #expect(model.signingStage == .waitingForTap(.tapToRead))
    }

    @Test("Tap puis PIN : le second tap n'accepte que la carte lue au premier (son PIN)")
    func tapThenPinSecondTapLimitedToFirstCard() async {
        let (model, service) = await reviewReady(drawerID: "main", order: .tapThenPin)
        service.readCardKey = k1Key
        model.confirmReview()
        await waitUntil { model.signingStage == .waitingForTap(.tapToRead) }
        model.scanCard()
        await waitUntil { model.signingStage == .enteringPin }
        model.pinEntered("4321")
        model.scanCard()
        await waitUntil { isSent(model) }
        #expect(service.lastOnlyCard == k1Key)
        #expect(service.lastPin == "4321")
    }

    @Test("Tap puis PIN : au second tap, une autre carte → « your PIN is for Jungle »")
    func tapThenPinSecondTapOtherCard() async {
        let (model, service) = await reviewReady(drawerID: "main", order: .tapThenPin)
        service.readCardKey = r1Key
        model.confirmReview()
        await waitUntil { model.signingStage == .waitingForTap(.tapToRead) }
        model.scanCard()
        await waitUntil { model.signingStage == .enteringPin }
        model.pinEntered("4321")
        service.nextSignError = ChipError.cardNotAccepted(tapped: k1Key)
        model.scanCard()
        await waitUntil { wrongCard(model) != nil }
        #expect(wrongCard(model)?.0 == WrongCard(reason: .notTheSameCard, tapped: KnownCard(name: "Banana", color: .banana), needed: KnownCard(name: "Jungle", color: .jungle)))
        #expect(wrongCard(model)?.1 == .tapToSign)
    }

    @Test("Tap puis PIN, carte lue sans PIN (compte mixte) : elle signe dans le même tap, pas de second tap")
    func tapThenPinCardWithoutPINSignsAtOnce() async {
        let (model, service) = await reviewReady(drawerID: "main", order: .tapThenPin, cards: .mixed)
        service.readCardUsesPin = false
        model.confirmReview()
        await waitUntil { model.signingStage == .waitingForTap(.tapToRead) }
        model.scanCard()
        await waitUntil { isSent(model) }
        #expect(isSent(model))
        #expect(service.readCount == 1)
        #expect(service.signCount == 1, "La signature a eu lieu pendant la lecture")
        #expect(service.submitCount == 1)
        #expect(service.lastPin == nil)
    }

    // MARK: Vrai service : second tap limité à la carte lue

    @Test("ChainSendService.sign : `onlyCard` réduit les cartes acceptées à la carte lue, jamais hors du compte")
    func chainSignOnlyCard() async throws {
        let signer = KeysSpy()
        let session = AppSession(store: InMemoryLocalWalletStore(), network: .testnet)
        let service = ChainSendService(session: session, wallet: EmptyWallet(), signer: signer)
        let prepared = try preparedFromMain(acceptedKeys: [k1Key, r1Key])
        _ = try await service.sign(prepared, pin: "1234", onlyCard: nil)
        #expect(signer.lastKeys == [k1Key, r1Key])
        _ = try await service.sign(prepared, pin: "1234", onlyCard: r1Key)
        #expect(signer.lastKeys == [r1Key])
        let outsider = try ChipPublicKey(Data([0x04] + [UInt8](repeating: 0x33, count: 64)))
        _ = try await service.sign(prepared, pin: "1234", onlyCard: outsider)
        #expect(signer.lastKeys.isEmpty, "Une carte hors du compte ne peut jamais signer")
    }

    // MARK: Raisons d'un échec après la signature

    @Test("Raison affichée après la signature : réseau, serveur de frais, signature refusée, refus de Stellar")
    func failureReasons() {
        let trace = PaymentTrace(token: "t", from: "C", destination: "G", units: 1, nonce: 1, preparedAtLedger: 1, expirationLedger: 2)
        func reason(_ error: Error) -> SendFailureReason? { SendFailureReason(PaymentFailure(trace: trace, underlying: error)) }
        #expect(reason(StellarError.rpc("timeout")) == .network)
        #expect(reason(StellarError.sendUnanswered(hash: "a", detail: "x")) == .network)
        #expect(reason(URLError(.notConnectedToInternet)) == .network)
        #expect(reason(FeeSignerError.busy) == .feeHelperBusy)
        #expect(reason(FeeSignerError.unavailable(nil)) == .feeHelperBusy)
        #expect(reason(FeeSignerError.refused("fee too high")) == .feeHelperRefused)
        #expect(reason(StellarError.signatureRejected("x")) == .signatureRejected)
        #expect(reason(StellarError.simulationFailed("Error(Contract, #10)")) == .refused)
        #expect(reason(StellarError.submitFailed("txBadSeq")) == .refused)
        #expect(reason(StellarError.notConfirmed(hash: "a")) == nil, "Envoyé mais pas confirmé : pas un échec")
    }

    // MARK: Outils

    private func preparedFromMain(acceptedKeys: [ChipPublicKey]) throws -> PreparedSend {
        let account = "CDU45A6K2WTMLRDUEQ7SXGOUICJVRWSLZCYPLWB7W6FVQLD7LPNRVVFR"
        let token = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
        let declared = try SACClient.declareTransfer(
            token: token, pocket: account, to: MockSendService.mayaAddress, units: 10_000_000,
            passphrase: ChimpNetworkConfig.testnet.passphrase, currentLedger: 1000, nonce: 1
        )
        let payment = PreparedPayment(
            authorizer: .account(account), token: token, destination: MockSendService.mayaAddress, units: 10_000_000,
            entry: declared.entry, digest: declared.digest, expirationLedger: 1120, preparedAtLedger: 1000, acceptedKeys: acceptedKeys
        )
        let drawer = SendDrawer(id: "main", kind: .main, address: account, balances: [.xlm: 10], usesPin: true)
        let draft = SendDraft(
            recipient: StellarRecipient(address: MockSendService.mayaAddress, kind: .account, memoID: nil),
            recipientName: nil, drawer: drawer, asset: .xlm, amount: 1, network: .testnet
        )
        return PreparedSend(draft: draft, payment: payment)
    }
}

/// Signataire espion : garde les cartes acceptées de la dernière signature.
private final class KeysSpy: ChipSigner, @unchecked Sendable {
    private(set) var lastKeys: [ChipPublicKey] = []

    func sign(digests: [Data], expectedKey: ChipPublicKey, pin: String?) async throws -> [ChipSignedDigest] {
        digests.map { _ in .secp256k1(signature: Data(repeating: 0x11, count: 64)) }
    }

    func sign(digests: [Data], acceptedKeys: [ChipPublicKey], pin: String?) async throws -> CardSignatures {
        lastKeys = acceptedKeys
        let key = acceptedKeys.first ?? MockChipReader.secp256k1Key
        return CardSignatures(card: ChipKeyInfo(kind: .infineon2Go, publicKey: key, pinActive: true), signatures: try await sign(digests: digests, expectedKey: key, pin: pin))
    }

    func readOrSign(digests: [Data], acceptedKeys: [ChipPublicKey]) async throws -> ReadOrSign {
        .signed(try await sign(digests: digests, acceptedKeys: acceptedKeys, pin: nil))
    }

    func setPINAndSign(digests: [Data], expectedKey: ChipPublicKey, newPIN: String) async throws -> PINSetupSignatures {
        PINSetupSignatures(puk: nil, signatures: try await sign(digests: digests, expectedKey: expectedKey, pin: newPIN))
    }

    func verifyPIN(expectedKey: ChipPublicKey, pin: String) async throws {}
}

private struct EmptyWallet: WalletDataSource {
    var firstName: String? { nil }
    func fetchWallet() async throws -> WalletSnapshot {
        WalletSnapshot(currencyCode: "USD", main: DrawerBalance(assets: []), cards: [], weeklyChange: nil, usdPrices: [:], fetchedAt: .now)
    }
}

/// Infineon simulée : lit sa clé, vérifie un PIN, signe (DER fixe) ; garde toutes les commandes reçues.
private final class FakeInfineon: APDUTransport, @unchecked Sendable {
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
