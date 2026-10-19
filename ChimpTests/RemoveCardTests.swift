import Foundation
import Testing
import stellarsdk
@testable import ChimpDAO

/// Retirer une carte (G6), carte perdue (G7), dernière carte (G5) : `account.remove_card(clé)` en ordre 2, comparé au
/// terminal, puis les parcours sur une fausse chaîne (rien ne part).
struct RemoveCardTests {
    private let account = "CDU45A6K2WTMLRDUEQ7SXGOUICJVRWSLZCYPLWB7W6FVQLD7LPNRVVFR"
    private let passphrase = ChimpNetworkConfig.testnet.passphrase
    private let k1 = MockChipReader.secp256k1Key
    private let r1 = MockChipReader.p256Key

    // MARK: remove_card : valeurs du terminal

    /// Valeurs calculées avec `scBytes` (`env.ts`) et `authPayloadHash` (`chip-auth.ts`) recopiées telles quelles et
    /// exécutées avec `@stellar/stellar-sdk` 17.0.1 (version du `bun.lock` du terminal), le 2026-09-30.
    @Test("Argument de remove_card : les 65 octets de la clé (scBytes), secp256k1 et P-256")
    func removeCardArguments() throws {
        let k1Argument = try #require(CardMembershipClient.removeCardArguments(publicKey: k1).first?.xdrEncoded)
        #expect(k1Argument == "AAAADQAAAEEEeb5mfvncu6xVoGKVzocLBwKb/NstzijZWfKBWxb4F5hIOtp3JqPEZV2k+/wOEQio/Re0SKaFVBmcR9CP+xDUuAAAAA==")
        let r1Argument = try #require(CardMembershipClient.removeCardArguments(publicKey: r1).first?.xdrEncoded)
        #expect(r1Argument == "AAAADQAAAEEEaxfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54WK84zV2sxXs7LtkBoN79R9QAAAA==")
    }

    @Test("Entrée remove_card V1 du compte : digest identique à authPayloadHash (nonce positif et négatif)")
    func removeCardDigestV1() throws {
        let cases: [(ChipPublicKey, Int64, String)] = [
            (k1, 7, "77573b515ed49bb135e73605bdfc517988a49d05a2105b9c8ae4ecc3b2cb8fd8"),
            (k1, -42, "e08ba0c10e16bd0a754860d00b900de05e114db8933644fed0ae5823428275a8"),
            (r1, 7, "f2395c317efe975dbd70a199f7cdfd3e689705d736c2fc822ef3677094654add"),
            (r1, -42, "8527f03dcf07c4da31fbf294165f7765e3687fc4896148c8286dc5f992c5ccc0"),
        ]
        for (key, nonce, digest) in cases {
            let declared = try DeclaredAuthorization(
                authorizer: account,
                invocation: try SorobanAuth.contractInvocation(
                    contract: account, function: "remove_card", arguments: CardMembershipClient.removeCardArguments(publicKey: key)
                ),
                passphrase: passphrase, expirationLedger: 1120, nonce: nonce
            )
            #expect(declared.digest.hexString == digest)
        }
    }

    @Test("Entrée remove_card V2 reçue de la simulation : digest V2 du terminal, et c'est bien l'appel demandé (règles 4 et 8)")
    func removeCardDigestV2() throws {
        let received = try XDRDecoder.decode(SorobanAuthorizationEntryXDR.self, data: Data(base64Encoded: Self.removeCardV2K1)!)
        let pending = try SorobanAuth.pendingEntries([received], signer: account, passphrase: passphrase, expirationLedger: 1120)
        #expect(pending.count == 1)
        #expect(pending[0].digest.hexString == "30c7ae51886905e106108cc2d2603498f33d46d472cb0bfd605ce555f04f3fa6")
        let expected = try SorobanAuth.contractInvocation(
            contract: account, function: "remove_card", arguments: CardMembershipClient.removeCardArguments(publicKey: k1)
        )
        #expect(try XDREncoder.encode(pending[0].entry.rootInvocation) == XDREncoder.encode(expected))
        // Une autre carte dans l'appel : ce n'est plus l'appel demandé, rien ne serait signé.
        let other = try SorobanAuth.contractInvocation(
            contract: account, function: "remove_card", arguments: CardMembershipClient.removeCardArguments(publicKey: r1)
        )
        #expect(try XDREncoder.encode(pending[0].entry.rootInvocation) != XDREncoder.encode(other))
    }

    @Test("Refus « dernière carte » reconnu comme le terminal (#303, LastCard), pas les autres refus")
    func lastCardRefusal() {
        #expect(CardMembershipClient.isLastCardRefusal(.simulationFailed("HostError: Error(Contract, #303)")))
        #expect(CardMembershipClient.isLastCardRefusal(.transactionFailed(hash: "h", detail: "LastCard")))
        #expect(!CardMembershipClient.isLastCardRefusal(.simulationFailed("HostError: Error(Contract, #301)")))
        #expect(!CardMembershipClient.isLastCardRefusal(.notConfirmed(hash: "h")))
    }

    @Test("Qui signe : G6 la carte elle-même, G7 toutes les autres ; carte absente ou dernière carte refusées")
    func removalSigners() throws {
        #expect(try CardMembershipClient.removalSigners(members: [k1, r1], card: k1, signer: .theCardItself) == [k1])
        #expect(try CardMembershipClient.removalSigners(members: [k1, r1], card: k1, signer: .anotherCard) == [r1])
        #expect(throws: CardMembershipClient.MembershipError.lastCard) {
            try CardMembershipClient.removalSigners(members: [k1], card: k1, signer: .anotherCard)
        }
        #expect(throws: CardMembershipClient.MembershipError.notInAccount) {
            try CardMembershipClient.removalSigners(members: [r1], card: k1, signer: .theCardItself)
        }
    }

    // MARK: Parcours

    private func session(pending: Bool = false) -> (AppSession, InMemoryLocalWalletStore) {
        var wallet = LocalWallet(
            firstName: "Barth", tourSeen: true,
            account: SavedAccount(address: account, cards: [
                SavedCard(publicKey: k1.hex, chip: "infineon2Go", tokenID: 7, pocket: "CPOCKET7", name: "Banana", color: "banana"),
                SavedCard(publicKey: r1.hex, chip: "duox", tokenID: 913, pocket: "CPOCKET913", name: "Leaf", color: "leaf"),
            ]),
            cardHints: [CardHint(key: k1.hex, account: account, at: .now), CardHint(key: r1.hex, account: account, at: .now)]
        )
        if pending {
            let trace = PaymentTrace(token: "T", from: account, destination: "G", units: 1, nonce: 1, preparedAtLedger: 1, expirationLedger: 121)
            wallet.pendingSend = PendingSend(trace: trace, recipient: "G", recipientName: nil, drawerTitle: "Main account", asset: "XLM", amount: 1, signedAt: .now)
        }
        let store = InMemoryLocalWalletStore(wallet)
        return (AppSession(store: store, config: .testnet), store)
    }

    private func target(_ key: ChipPublicKey, chip: ChipKind, name: String) -> RemovalTarget {
        RemovalTarget(key: key, chip: chip, name: name, color: .banana, number: "0007",
                      walletAmount: "$62.50", walletIsEmpty: false, mainAmount: "$1,320.00")
    }

    private func model(
        _ mode: RemoveCardModel.Mode, removing key: ChipPublicKey? = nil, members: [ChipPublicKey]? = nil,
        scenario: MockRemoveCardService.Scenario = .success, signer: ChipSigner = MockChipSigner(delay: .zero),
        pending: Bool = false
    ) -> (RemoveCardModel, MockRemoveCardService, InMemoryLocalWalletStore) {
        let (session, store) = session(pending: pending)
        let removed = key ?? k1
        let service = MockRemoveCardService(members: members ?? [k1, r1], scenario: scenario, delay: .zero)
        let model = RemoveCardModel(
            mode: mode, account: account,
            target: target(removed, chip: removed == r1 ? .duox : .infineon2Go, name: removed == r1 ? "Leaf" : "Banana"),
            session: session, signer: signer, service: service
        )
        return (model, service, store)
    }

    @Test("G6 : PIN de la carte retirée, puis son tap, remove_card, relecture ; le téléphone l'oublie (carte et indice)")
    func removeHappyPath() async {
        let signer = TapSigner(tapped: k1)
        let (model, service, store) = model(.remove, signer: signer)
        #expect(model.usesPIN, "Infineon")
        await model.start()
        #expect(model.isShowingPINSheet)
        model.pinEntered("1234")
        #expect(model.isShowingTapSheet)
        await model.scan()
        #expect(signer.accepted == [[k1]], "Seule la carte retirée peut signer (terminal)")
        #expect(signer.pins == ["1234"])
        #expect(model.screen == .done)
        #expect(service.submitCount == 1)
        #expect(store.wallet.account?.cards.map(\.publicKey) == [r1.hex])
        #expect(store.wallet.cardHints.map(\.key) == [r1.hex])
    }

    @Test("G7 : n'importe quelle autre carte signe ; la carte perdue n'est pas acceptée")
    func lostHappyPath() async {
        let signer = TapSigner(tapped: r1)
        let (model, service, store) = model(.lost, removing: k1, signer: signer)
        await model.start()
        // Seule autre carte : une DUOX, sans PIN.
        #expect(!model.usesPIN)
        #expect(model.isShowingTapSheet)
        await model.scan()
        #expect(signer.accepted == [[r1]])
        #expect(model.signerName == "Leaf")
        #expect(model.screen == .done)
        #expect(service.submitCount == 1)
        #expect(store.wallet.account?.cards.map(\.publicKey) == [r1.hex])
    }

    @Test("G5 : dernière carte → refusé avant tout tap, rien n'est lu ni signé")
    func lastCard() async {
        let signer = TapSigner(tapped: k1)
        let (model, service, _) = model(.remove, members: [k1], signer: signer)
        await model.start()
        #expect(model.isShowingLastCard)
        #expect(!model.isShowingPINSheet && !model.isShowingTapSheet)
        #expect(signer.accepted.isEmpty)
        #expect(service.submitCount == 0)
    }

    @Test("G5 : le compte a changé (#303 à l'envoi) → retour à la revue avec G5, rien d'enregistré")
    func lastCardAtSubmit() async {
        let (model, _, store) = model(.remove, scenario: .lastCardAtSubmit, signer: TapSigner(tapped: k1))
        await model.start()
        model.pinEntered("1234")
        await model.scan()
        #expect(model.screen == .review)
        #expect(model.isShowingLastCard)
        #expect(store.wallet.account?.cards.count == 2)
    }

    @Test("Paiement en attente : refusé, rien ne part")
    func refusedWhilePending() async {
        let (model, service, _) = model(.remove, pending: true)
        await model.start()
        #expect(model.problem?.kind == .pendingPayment)
        #expect(!model.isShowingPINSheet && !model.isShowingTapSheet)
        #expect(service.submitCount == 0)
    }

    @Test("G6 : une autre carte tapée → refusée sans PIN ni signature ; G7 : la carte perdue tapée → refusée")
    func wrongCards() async {
        let (remove, removeService, _) = model(.remove, signer: TapSigner(tapped: r1))
        await remove.start()
        remove.pinEntered("1234")
        await remove.scan()
        #expect(remove.problem?.kind == .notTheCard)
        #expect(remove.screen == .review)
        #expect(removeService.submitCount == 0)

        let (lost, lostService, _) = model(.lost, removing: k1, signer: TapSigner(tapped: k1))
        await lost.start()
        await lost.scan()
        #expect(lost.problem?.kind == .isTheLostCard)
        #expect(lostService.submitCount == 0)

        let stranger = try! ChipPublicKey(Data(repeating: 0x04, count: 1) + Data(repeating: 0x09, count: 64))
        let (other, _, _) = model(.lost, removing: k1, signer: TapSigner(tapped: stranger))
        await other.start()
        await other.scan()
        #expect(other.problem?.kind == .notAMember)
    }

    @Test("PIN faux : retour au pavé avec les essais restants, rien n'est envoyé")
    func wrongPIN() async {
        let (model, service, _) = model(.remove, signer: MockChipSigner(outcome: .failure(.wrongPIN(retriesLeft: 2)), delay: .zero))
        await model.start()
        model.pinEntered("0000")
        await model.scan()
        #expect(model.isShowingPINSheet)
        #expect(model.pinState == .wrong(triesLeft: 2))
        #expect(service.submitCount == 0)
    }

    @Test("DUOX retirée : pas de PIN, tap direct")
    func duoxWithoutPIN() async {
        let (model, _, _) = model(.remove, removing: r1, signer: TapSigner(tapped: r1))
        #expect(!model.usesPIN)
        await model.start()
        #expect(model.isShowingTapSheet)
        await model.scan()
        #expect(model.screen == .done)
    }

    @Test("Réseau à l'envoi : « Try again » renvoie la même signature ; une fois retirée, plus rien ne part")
    func networkThenRetry() async {
        let (model, service, store) = model(.remove, scenario: .networkWhileRemoving, signer: TapSigner(tapped: k1))
        await model.start()
        model.pinEntered("1234")
        await model.scan()
        guard case .failed(.removing, let problem) = model.phase else {
            Issue.record("Échec attendu à l'envoi")
            return
        }
        #expect(problem.kind == .network)
        await model.run()
        #expect(model.screen == .done)
        #expect(service.submitCount == 2)
        await model.run()
        #expect(service.submitCount == 2, "Déjà retirée : rien n'est renvoyé")
        #expect(store.wallet.account?.cards.count == 1)
    }

    @Test("Envoyé mais encore listée : « Check again », rien n'est enregistré sur le téléphone")
    func notConfirmed() async {
        let (model, _, store) = model(.remove, scenario: .notConfirmedYet, signer: TapSigner(tapped: k1))
        await model.start()
        model.pinEntered("1234")
        await model.scan()
        guard case .failed(.confirming, let problem) = model.phase else {
            Issue.record("Échec attendu à la confirmation")
            return
        }
        #expect(problem.kind == .notConfirmed)
        #expect(store.wallet.account?.cards.count == 2)
    }

    @Test("Réseau avant le tap : message, rien n'est lu ni signé")
    func networkBeforeTap() async {
        let signer = TapSigner(tapped: k1)
        let (model, _, _) = model(.remove, scenario: .networkBeforeTap, signer: signer)
        await model.start()
        model.pinEntered("1234")
        await model.scan()
        #expect(model.problem?.kind == .network)
        #expect(signer.accepted.isEmpty)
    }

    /// Entrée `remove_card` V2 (nonce 7, expiration 1120) pour la clé secp256k1 de test, construite par le SDK JS 17.0.1.
    static let removeCardV2K1 = "AAAAAgAAAAHpzoPK1abFxHQkPyuZ1ECTWNpLyLD12D+3i1gsf1vbGgAAAAAAAAAHAAAEYAAAAAEAAAAAAAAAAenOg8rVpsXEdCQ/K5nUQJNY2kvIsPXYP7eLWCx/W9saAAAAC3JlbW92ZV9jYXJkAAAAAAEAAAANAAAAQQR5vmZ++dy7rFWgYpXOhwsHApv82y3OKNlZ8oFbFvgXmEg62ncmo8RlXaT7/A4RCKj9F7RIpoVUGZxH0I/7ENS4AAAAAAAAAA=="
}

/// Signataire dont la carte « posée » est toujours `tapped` : signe si elle est acceptée, sinon la refuse comme
/// `ChipSigning` (sans rien lui envoyer d'autre). Garde les listes acceptées et les PIN reçus.
private final class TapSigner: ChipSigner, @unchecked Sendable {
    let tapped: ChipPublicKey
    private(set) var accepted: [[ChipPublicKey]] = []
    private(set) var pins: [String?] = []
    init(tapped: ChipPublicKey) { self.tapped = tapped }

    func sign(digests: [Data], expectedKey: ChipPublicKey, pin: String?) async throws -> [ChipSignedDigest] {
        guard expectedKey == tapped else { throw ChipError.wrongCard }
        return digests.map { _ in .secp256k1(signature: Data(repeating: 0x11, count: 64)) }
    }

    func sign(digests: [Data], acceptedKeys: [ChipPublicKey], pin: String?) async throws -> CardSignatures {
        accepted.append(acceptedKeys)
        guard acceptedKeys.contains(tapped) else { throw ChipError.cardNotAccepted(tapped: tapped) }
        pins.append(pin)
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
