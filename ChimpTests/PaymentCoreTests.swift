import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Jalon 7, étape 1 : briques de `Core/` pour un paiement signé par la carte.
/// Valeurs de référence calculées par les fonctions du terminal recopiées telles quelles (`chip-auth.ts` : `scMap`,
/// `scChipAuthK1`, `scChipAuthR1`, `restamp`, `authPayloadHash`, `build` de `preSignedAuthEntries`,
/// `accountChipSignature` ; `stellar.ts` : `transferArgs` ; `lib/amount.ts` : `toUnits`), exécutées avec
/// `@stellar/stellar-sdk` 17.0.1 (version et empreinte du `bun.lock` du terminal).
struct PaymentCoreTests {
    private let passphrase = ChimpNetworkConfig.testnet.passphrase
    private let k1Key = MockChipReader.secp256k1Key
    private let r1Key = MockChipReader.p256Key
    private let signature = Data(repeating: 0x11, count: 32) + Data(repeating: 0x22, count: 32)
    private let digest = Data((0..<32).map { UInt8($0) })

    private let xlmSAC = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
    private let pocket = "CALWOI2Z6NZ5ULEYRXZZTN7M35CMWMS6YJXTQTVPIOQXKEKWKTVELEMX"
    private let account = "CDU45A6K2WTMLRDUEQ7SXGOUICJVRWSLZCYPLWB7W6FVQLD7LPNRVVFR"
    private let admin = "GBLWPGXVH47YGMODIUHZJ7FETRISFU3TB7JGADTRIMU36OLWJ7PYEZ6M"
    private let muxed = MockSendService.exchangeMuxedAddress

    // MARK: Montants → unités on-chain (toUnits)

    @Test("toUnits : vecteurs du terminal (1.23 à 2 décimales, 0.001 à 6, 5 à 2) → 7 décimales on-chain")
    func unitsTerminalVectors() throws {
        #expect(try SACClient.units(of: Decimal(string: "1.23")!, keypadDecimals: 2) == 12_300_000)
        #expect(try SACClient.units(of: Decimal(string: "0.001")!, keypadDecimals: 6) == 10_000)
        #expect(try SACClient.units(of: 5, keypadDecimals: 2) == 50_000_000)
    }

    @Test("XLM : 1 XLM = 10 000 000 stroops, 0,5 XLM = 5 000 000, 0,0000001 XLM = 1")
    func unitsXLM() throws {
        #expect(try SACClient.units(of: 1, keypadDecimals: 7) == 10_000_000)
        #expect(try SACClient.units(of: Decimal(string: "0.5")!, keypadDecimals: 7) == 5_000_000)
        #expect(try SACClient.units(of: Decimal(string: "0.0000001")!, keypadDecimals: 7) == 1)
        #expect(try SACClient.units(of: Decimal(string: "1844674407370.9551615")!, keypadDecimals: 7) == UInt64.max)
    }

    @Test("« 0,5 » tapé sur un téléphone en français = 5 000 000 stroops, comme « 0.5 » en anglais")
    func unitsFromKeypad() throws {
        var entry = AmountEntry()
        for key: ChimpKeypadKey in [.digit(0), .decimal, .digit(5)] {
            let accepted = entry.apply(key, maxFractionDigits: SendAsset.xlm.maxFractionDigits)
            #expect(accepted)
        }
        #expect(try SACClient.units(of: entry.value, keypadDecimals: SendAsset.xlm.maxFractionDigits) == 5_000_000)
        #expect(try SACClient.units(of: Decimal(string: "25.5")!, keypadDecimals: SendAsset.usdc.maxFractionDigits) == 255_000_000)
    }

    @Test("Montant nul, négatif, trop de décimales ou trop grand : refusé (jamais tronqué ni arrondi)")
    func unitsRefused() {
        #expect(throws: SACClient.AmountError.notPositive) { try SACClient.units(of: 0, keypadDecimals: 7) }
        #expect(throws: SACClient.AmountError.notPositive) { try SACClient.units(of: -1, keypadDecimals: 7) }
        #expect(throws: SACClient.AmountError.tooManyDecimals(allowed: 2)) {
            try SACClient.units(of: Decimal(string: "1.234")!, keypadDecimals: 2)
        }
        #expect(throws: SACClient.AmountError.tooManyDecimals(allowed: 7)) {
            try SACClient.units(of: Decimal(string: "0.00000001")!, keypadDecimals: 7)
        }
        #expect(throws: SACClient.AmountError.tooLarge) {
            try SACClient.units(of: Decimal(string: "1844674407370.9551616")!, keypadDecimals: 7)
        }
    }

    // MARK: Ordre 1 : transfert déclaré par la Pocket

    @Test("Pocket → admin, 0,5 XLM : entrée transfer déclarée et digest identiques au terminal, expiration = ledger + 120")
    func declaredPocketTransfer() throws {
        let declared = try SACClient.declareTransfer(
            token: xlmSAC, pocket: pocket, to: admin, units: 5_000_000,
            passphrase: passphrase, currentLedger: 1000, nonce: 1_234_567_890_123_456_789
        )
        #expect(declared.expirationLedger == 1120)
        #expect(try base64(declared.entry)
            == "AAAAAQAAAAEXZyNZ83PaLJiN85m37N9EyzJewm84Tq9DoXURVlTqRREiEPR96YEVAAAEYAAAAAEAAAAAAAAAAdeSi3LCcDzP6vfrn/TvTVBKVai5efybRQ6iyEK00c5hAAAACHRyYW5zZmVyAAAAAwAAABIAAAABF2cjWfNz2iyYjfOZt+zfRMsyXsJvOE6vQ6F1EVZU6kUAAAASAAAAAAAAAABXZ5r1Pz+DMcNFD5T8pJxRItNzD9JgDnFDKb85dk/fggAAAAoAAAAAAAAAAAAAAAAATEtAAAAAAA==")
        #expect(declared.digest.hexString == "e003c5a667e1cbfec4ad95ed399c9033848a97f687ad9eb16a4bd8605e13894d")
    }

    @Test("Destinataire M (memo ID plié) : argument Address multiplexé et digest identiques au terminal")
    func declaredMuxedTransfer() throws {
        #expect(try base64(SCValXDR.address(try SACClient.address(muxed))) == "AAAAEgAAAAIAAAAASZYC0nuyp3OwI6QUR5j5jTLYYx2fvGK3B06678sotaYQ49fO")
        let declared = try SACClient.declareTransfer(
            token: xlmSAC, pocket: pocket, to: muxed, units: 10_000_000,
            passphrase: passphrase, currentLedger: 1000, nonce: -42
        )
        #expect(declared.digest.hexString == "41038fda293251f6240f1b066368ad43d4e130039125a290ad049162ccb6672c")
    }

    @Test("SAC XLM de testnet : même adresse que Asset.native().contractId(passphrase)")
    func xlmContract() throws {
        #expect(try SACClient.contractID(for: Asset(type: AssetType.ASSET_TYPE_NATIVE)!, network: .testnet) == xlmSAC)
    }

    // MARK: Ordre 2 : entrée reçue de la simulation

    @Test("Entrée V2 reçue : expiration posée dans la variante reçue, digest V2 identique au terminal (règle 4)")
    func pendingV2() throws {
        let received = try entry(Self.recordedV2)
        let pending = try SorobanAuth.pendingEntries([received], signer: account, passphrase: passphrase, expirationLedger: 1120)
        #expect(pending.count == 1)
        #expect(pending[0].index == 0)
        #expect(SorobanAuth.isAddressV2(pending[0].entry))
        #expect(try base64(pending[0].entry) == Self.stampedV2)
        #expect(pending[0].digest.hexString == "a818ff2c5db18713b9ed5516a3fbdbca650a9eda1fb77be99e1b9d92d0527264")
    }

    @Test("La même entrée en V1 : digest V1 (différent du V2)")
    func pendingV1() throws {
        let v2 = try entry(Self.recordedV2)
        let v1 = SorobanAuthorizationEntryXDR(credentials: .address(try SorobanAuth.addressCredentials(v2)), rootInvocation: v2.rootInvocation)
        let pending = try SorobanAuth.pendingEntries([v1], signer: account, passphrase: passphrase, expirationLedger: 1120)
        #expect(pending[0].digest.hexString == "d0a5433797981abc4f28740ba0e6628d2ad57ec0359f414a342e1639831e266b")
    }

    @Test("Entrée pour une autre adresse : refus avant toute signature ; « compte source » laissé au payeur de frais")
    func pendingRefusals() throws {
        let received = try entry(Self.recordedV2)
        #expect(throws: SorobanAuth.AuthError.unexpectedSigner(account)) {
            try SorobanAuth.pendingEntries([received], signer: pocket, passphrase: passphrase, expirationLedger: 1120)
        }
        let source = SorobanAuthorizationEntryXDR(credentials: .sourceAccount, rootInvocation: received.rootInvocation)
        let pending = try SorobanAuth.pendingEntries([source, received], signer: account, passphrase: passphrase, expirationLedger: 1120)
        #expect(pending.map(\.index) == [1])
        #expect(throws: SorobanAuth.AuthError.nothingToSign) {
            try SorobanAuth.pendingEntries([source], signer: account, passphrase: passphrase, expirationLedger: 1120)
        }
        #expect(throws: SorobanAuth.AuthError.nothingToSign) {
            try SorobanAuth.pendingEntries([], signer: account, passphrase: passphrase, expirationLedger: 1120)
        }
    }

    // MARK: AccountAuth

    @Test("AccountAuth { auth, key } secp256k1 et P-256 : mêmes octets que accountChipSignature")
    func accountAuthBytes() throws {
        let k1 = ChipAuthEncoding.accountAuth(publicKey: k1Key, chipAuth: try ChipAuthEncoding.chipAuthSecp256k1(signature: signature, recoveryID: 1))
        #expect(try base64(k1) == Self.accountAuthK1)
        let r1 = ChipAuthEncoding.accountAuth(
            publicKey: r1Key,
            chipAuth: try ChipAuthEncoding.chipAuthSecp256r1(signature: signature, rndB: Data(repeating: 0xAB, count: 16))
        )
        #expect(try base64(r1)
            == "AAAAEQAAAAEAAAACAAAADwAAAARhdXRoAAAAEAAAAAEAAAACAAAADwAAAAlTZWNwMjU2cjEAAAAAAAARAAAAAQAAAAIAAAAPAAAABXJuZF9iAAAAAAAADQAAABCrq6urq6urq6urq6urq6urAAAADwAAAAlzaWduYXR1cmUAAAAAAAANAAAAQBERERERERERERERERERERERERERERERERERERERERERIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIAAAAPAAAAA2tleQAAAAANAAAAQQRrF9Hy4SxCR/i85uVjpEDydwN9gS3rM6D0oTlF2JjClk/jQuL+Gn+bjufrSnwPnhYrzjNXazFezsu2QGg3v1H1AAAA")
    }

    @Test("Entrée du Main account signée : AccountAuth dans la variante reçue (V2), octets identiques au terminal")
    func signedAccountEntry() throws {
        let prepared = preparedFromAccount()
        let chipAuth = try ChipAuthEncoding.chipAuthSecp256k1(signature: signature, recoveryID: 1)
        let signed = try SorobanAuth.restamped(prepared.entry, signature: prepared.envelope(chipAuth, card: k1Key))
        #expect(try base64(signed) == Self.signedAccountEntry)
    }

    @Test("Wallet d'une carte : ChipAuth tel quel, refus #201 ; Main account : AccountAuth, refus #301")
    func envelopeAndRejectionCodes() throws {
        let chipAuth = try ChipAuthEncoding.chipAuthSecp256k1(signature: signature, recoveryID: 0)
        let pocketPayment = try preparedFromPocket()
        #expect(try base64(pocketPayment.envelope(chipAuth, card: k1Key)) == base64(chipAuth))
        #expect(pocketPayment.rejectionCode == 201)
        #expect(preparedFromAccount().rejectionCode == 301)
        #expect(RecoveryIDSearch.isRejectedSignature(
            StellarError.simulationFailed("HostError: Error(Contract, #301)"), contractCode: RecoveryIDSearch.RejectionCode.account
        ))
        #expect(!RecoveryIDSearch.isRejectedSignature(
            StellarError.simulationFailed("HostError: Error(Contract, #300)"), contractCode: RecoveryIDSearch.RejectionCode.account
        ))
    }

    // MARK: Solde (fail-closed)

    @Test("Solde illisible ou insuffisant : refus avant toute signature ; solde exact : accepté")
    func balanceGate() throws {
        #expect(throws: PaymentClient.PaymentError.balanceUnknown) { try PaymentClient.checkBalance(nil, units: 1) }
        #expect(throws: PaymentClient.PaymentError.insufficientBalance(held: 9_999_999)) {
            try PaymentClient.checkBalance(9_999_999, units: 10_000_000)
        }
        try PaymentClient.checkBalance(10_000_000, units: 10_000_000)
    }

    @Test("Marge avant le tap : moins de 20 ledgers devant l'autorisation → à refaire")
    func refreshMargin() {
        #expect(!SorobanAuth.needsRefresh(expirationLedger: 1120, currentLedger: 1000))
        #expect(!SorobanAuth.needsRefresh(expirationLedger: 1120, currentLedger: 1100))
        #expect(SorobanAuth.needsRefresh(expirationLedger: 1120, currentLedger: 1101))
        #expect(SorobanAuth.needsRefresh(expirationLedger: 1120, currentLedger: 1200))
    }

    // MARK: Carte : une parmi plusieurs, clé vérifiée avant le PIN

    @Test("Main account : une carte du compte signe (SELECT → VERIFY PIN → SIGN), et on sait laquelle")
    func anyOfAccountCards() async throws {
        let card = PaymentInfineon(key: k1Key, pinActive: true)
        let signed = try await ChipSigning.sign(card, digests: [digest], acceptedKeys: [r1Key, k1Key], pin: "1234")
        #expect(signed.card.publicKey == k1Key)
        #expect(signed.card.kind == .infineon2Go)
        #expect(card.sent.suffix(3).map(\.hexString) == [
            Infineon2Go.selectAPDU.hexString, "004400000431323334", "0018010020" + digest.hexString + "00",
        ])
    }

    @Test("Carte qui n'est pas dans la liste : refus avec sa clé, et AUCUN PIN (00 44) ni SIGN (00 18) envoyé")
    func cardNotAcceptedGetsNoPIN() async {
        let card = PaymentInfineon(key: k1Key, pinActive: true)
        await #expect(throws: ChipError.cardNotAccepted(tapped: k1Key)) {
            try await ChipSigning.sign(card, digests: [digest], acceptedKeys: [r1Key], pin: "1234")
        }
        #expect(!card.sent.contains { $0.count > 1 && $0[1] == 0x44 })
        #expect(!card.sent.contains { $0.count > 1 && $0[1] == 0x18 })
    }

    @Test("Ancienne entrée (une seule carte attendue) : toujours « wrongCard », et toujours aucun PIN envoyé")
    func singleKeyStillWrongCard() async {
        let card = PaymentInfineon(key: k1Key, pinActive: true)
        await #expect(throws: ChipError.wrongCard) {
            try await ChipSigning.sign(card, digests: [digest], expectedKey: r1Key, pin: "1234")
        }
        #expect(!card.sent.contains { $0.count > 1 && $0[1] == 0x44 })
    }

    @Test("Carte sans PIN actif : le PIN saisi n'est pas envoyé (pas de VERIFY PIN), la carte signe")
    func noVerifyWithoutActivePIN() async throws {
        let card = PaymentInfineon(key: k1Key, pinActive: false)
        let signed = try await ChipSigning.sign(card, digests: [digest], acceptedKeys: [k1Key], pin: "1234")
        #expect(signed.signatures.count == 1)
        #expect(!card.sent.contains { $0.count > 1 && $0[1] == 0x44 })
        #expect(card.sent.last?.hexString == "0018010020" + digest.hexString + "00")
    }

    // MARK: « Check again »

    @Test("Transaction confirmée → envoyé")
    func checkSent() async throws {
        let ledger = FakeLedger(lookup: .init(status: .success, latestLedger: 1010, latestLedgerCloseTime: 5000))
        #expect(try await PaymentClient.check(trace(hash: "aa", maxTime: 4990), ledger: ledger) == .sent(hash: "aa"))
    }

    @Test("Introuvable, mais le dernier ledger a fermé avant la limite de 60 s → elle peut encore passer")
    func checkPending() async throws {
        let ledger = FakeLedger(lookup: .init(status: .notFound, latestLedger: 1010, latestLedgerCloseTime: 4990))
        #expect(try await PaymentClient.check(trace(hash: "aa", maxTime: 4990), ledger: ledger) == .pending)
        #expect(ledger.scanned == false)
    }

    @Test("Introuvable après sa limite, autorisation encore valable → attendre, avec l'heure estimée de l'expiration")
    func checkWaiting() async throws {
        let ledger = FakeLedger(lookup: .init(status: .notFound, latestLedger: 1100, latestLedgerCloseTime: 5000))
        let result = try await PaymentClient.check(trace(hash: "aa", maxTime: 4990), ledger: ledger)
        // Expiration 1120 : l'autorisation est morte quand le ledger 1121 ferme, 21 ledgers après 1100, estimés à 6 s.
        #expect(result == .waiting(untilLedger: 1120, estimatedEnd: Date(timeIntervalSince1970: 5000 + 21 * 6)))
        #expect(ledger.scanned == false)
    }

    @Test("Échouée sur la chaîne : l'autorisation reste valable jusqu'à son expiration → attendre aussi")
    func checkFailedStillWaits() async throws {
        let ledger = FakeLedger(lookup: .init(status: .failed("txFailed"), latestLedger: 1050, latestLedgerCloseTime: 5000))
        guard case .waiting = try await PaymentClient.check(trace(hash: "aa", maxTime: 9999), ledger: ledger) else {
            Issue.record("expected waiting"); return
        }
    }

    @Test("Refusée avant l'envoi (pas de hash) : on lit le dernier ledger ; avant l'expiration → attendre")
    func checkWithoutHash() async throws {
        let ledger = FakeLedger(latest: (1120, 6000))
        guard case .waiting(1120, _) = try await PaymentClient.check(trace(hash: nil, maxTime: nil), ledger: ledger) else {
            Issue.record("expected waiting until 1120"); return
        }
    }

    @Test("Après l'expiration, notre autorisation (nonce) n'apparaît dans aucune transaction → rien n'est parti, certain")
    func checkNothingSent() async throws {
        let ledger = FakeLedger(latest: (1121, 6000))
        ledger.scan = .init(transactionHashes: ["bb"], oldestLedger: 10, latestLedger: 1125)
        ledger.envelopes = ["bb": try envelope(nonce: 7)]
        #expect(try await PaymentClient.check(trace(hash: nil, maxTime: nil), ledger: ledger) == .nothingSent)
        #expect(ledger.scannedRange == 1000...1120)
    }

    @Test("Après l'expiration, notre autorisation a servi dans une autre transaction → envoyé, par celle-là")
    func checkReplayed() async throws {
        let ledger = FakeLedger(latest: (1121, 6000))
        ledger.scan = .init(transactionHashes: ["bb", "cc"], oldestLedger: 10, latestLedger: 1125)
        ledger.envelopes = ["bb": try envelope(nonce: 7), "cc": try envelope(nonce: -42)]
        #expect(try await PaymentClient.check(trace(hash: nil, maxTime: nil), ledger: ledger) == .sent(hash: "cc"))
    }

    @Test("Historique du RPC trop court, ou transaction illisible → impossible de trancher, jamais « rien n'est parti »")
    func checkUndetermined() async throws {
        let ledger = FakeLedger(latest: (1121, 6000))
        ledger.scan = .init(transactionHashes: [], oldestLedger: 1001, latestLedger: 1125)
        guard case .undetermined = try await PaymentClient.check(trace(hash: nil, maxTime: nil), ledger: ledger) else {
            Issue.record("expected undetermined"); return
        }
        ledger.scan = .init(transactionHashes: ["dd"], oldestLedger: 10, latestLedger: 1125)
        guard case .undetermined = try await PaymentClient.check(trace(hash: nil, maxTime: nil), ledger: ledger) else {
            Issue.record("expected undetermined"); return
        }
    }

    @Test("Nonce retrouvé seulement pour la bonne adresse ; sujets transfer identiques aux filtres du terminal")
    func envelopeAndTopics() throws {
        let signed = try envelope(nonce: -42)
        #expect(try PaymentClient.envelope(signed, contains: -42, from: account))
        #expect(try !PaymentClient.envelope(signed, contains: -41, from: account))
        #expect(try !PaymentClient.envelope(signed, contains: -42, from: pocket))
        #expect(try PaymentClient.transferTopics(from: pocket) == ["AAAADwAAAAh0cmFuc2Zlcg==", "AAAAEgAAAAEXZyNZ83PaLJiN85m37N9EyzJewm84Tq9DoXURVlTqRQ==", "*", "*"])
    }

    @Test("Curseur de getEvents → ledger atteint (curseurs réels de testnet, 2026-09-29)")
    func cursorLedger() {
        #expect(ChimpDAO.SorobanClient.cursorLedger("0021193825359773696-0000000000") == 4_934_572)
        #expect(ChimpDAO.SorobanClient.cursorLedger("0021194503964590079-4294967295") == 4_934_729)
        #expect(ChimpDAO.SorobanClient.cursorLedger("pas-un-curseur") == nil)
        #expect(ChimpDAO.SorobanClient.cursorLedger("") == nil)
    }

    @Test("Hash porté par l'erreur : seulement quand la transaction a peut-être été envoyée")
    func sentHash() {
        #expect(PaymentClient.sentHash(in: StellarError.notConfirmed(hash: "a")) == "a")
        #expect(PaymentClient.sentHash(in: StellarError.sendUnanswered(hash: "b", detail: "timeout")) == "b")
        #expect(PaymentClient.sentHash(in: StellarError.transactionFailed(hash: "c", detail: "x")) == "c")
        #expect(PaymentClient.sentHash(in: StellarError.submitFailed("txBadSeq")) == nil)
        #expect(PaymentClient.sentHash(in: FeeSignerError.busy) == nil)
    }

    // MARK: Outils

    static let recordedV2 = "AAAAAgAAAAHpzoPK1abFxHQkPyuZ1ECTWNpLyLD12D+3i1gsf1vbGv/////////WAAAAAAAAAAEAAAAAAAAAAdeSi3LCcDzP6vfrn/TvTVBKVai5efybRQ6iyEK00c5hAAAACHRyYW5zZmVyAAAAAwAAABIAAAAB6c6DytWmxcR0JD8rmdRAk1jaS8iw9dg/t4tYLH9b2xoAAAASAAAAAAAAAABXZ5r1Pz+DMcNFD5T8pJxRItNzD9JgDnFDKb85dk/fggAAAAoAAAAAAAAAAAAAAAAAmJaAAAAAAA=="
    static let stampedV2 = "AAAAAgAAAAHpzoPK1abFxHQkPyuZ1ECTWNpLyLD12D+3i1gsf1vbGv/////////WAAAEYAAAAAEAAAAAAAAAAdeSi3LCcDzP6vfrn/TvTVBKVai5efybRQ6iyEK00c5hAAAACHRyYW5zZmVyAAAAAwAAABIAAAAB6c6DytWmxcR0JD8rmdRAk1jaS8iw9dg/t4tYLH9b2xoAAAASAAAAAAAAAABXZ5r1Pz+DMcNFD5T8pJxRItNzD9JgDnFDKb85dk/fggAAAAoAAAAAAAAAAAAAAAAAmJaAAAAAAA=="
    static let accountAuthK1 = "AAAAEQAAAAEAAAACAAAADwAAAARhdXRoAAAAEAAAAAEAAAACAAAADwAAAAlTZWNwMjU2azEAAAAAAAARAAAAAQAAAAIAAAAPAAAAC3JlY292ZXJ5X2lkAAAAAAMAAAABAAAADwAAAAlzaWduYXR1cmUAAAAAAAANAAAAQBERERERERERERERERERERERERERERERERERERERERERIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIAAAAPAAAAA2tleQAAAAANAAAAQQR5vmZ++dy7rFWgYpXOhwsHApv82y3OKNlZ8oFbFvgXmEg62ncmo8RlXaT7/A4RCKj9F7RIpoVUGZxH0I/7ENS4AAAA"
    static let signedAccountEntry = "AAAAAgAAAAHpzoPK1abFxHQkPyuZ1ECTWNpLyLD12D+3i1gsf1vbGv/////////WAAAEYAAAABEAAAABAAAAAgAAAA8AAAAEYXV0aAAAABAAAAABAAAAAgAAAA8AAAAJU2VjcDI1NmsxAAAAAAAAEQAAAAEAAAACAAAADwAAAAtyZWNvdmVyeV9pZAAAAAADAAAAAQAAAA8AAAAJc2lnbmF0dXJlAAAAAAAADQAAAEARERERERERERERERERERERERERERERERERERERERERESIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiAAAADwAAAANrZXkAAAAADQAAAEEEeb5mfvncu6xVoGKVzocLBwKb/NstzijZWfKBWxb4F5hIOtp3JqPEZV2k+/wOEQio/Re0SKaFVBmcR9CP+xDUuAAAAAAAAAAAAAAB15KLcsJwPM/q9+uf9O9NUEpVqLl5/JtFDqLIQrTRzmEAAAAIdHJhbnNmZXIAAAADAAAAEgAAAAHpzoPK1abFxHQkPyuZ1ECTWNpLyLD12D+3i1gsf1vbGgAAABIAAAAAAAAAAFdnmvU/P4Mxw0UPlPyknFEi03MP0mAOcUMpvzl2T9+CAAAACgAAAAAAAAAAAAAAAACYloAAAAAA"

    /// Paiement depuis le Main account, tel que `prepareFromAccount` le rendrait pour l'entrée V2 ci-dessus.
    private func preparedFromAccount() -> PreparedPayment {
        let pending = try! SorobanAuth.pendingEntries([try! entry(Self.recordedV2)], signer: account, passphrase: passphrase, expirationLedger: 1120)[0]
        return PreparedPayment(
            authorizer: .account(account), token: xlmSAC, destination: admin, units: 10_000_000,
            entry: pending.entry, digest: pending.digest, expirationLedger: 1120, preparedAtLedger: 1000, acceptedKeys: [k1Key, r1Key]
        )
    }

    private func preparedFromPocket() throws -> PreparedPayment {
        let declared = try SACClient.declareTransfer(
            token: xlmSAC, pocket: pocket, to: admin, units: 5_000_000, passphrase: passphrase, currentLedger: 1000, nonce: 1
        )
        return PreparedPayment(
            authorizer: .pocket(pocket), token: xlmSAC, destination: admin, units: 5_000_000,
            entry: declared.entry, digest: declared.digest, expirationLedger: 1120, preparedAtLedger: 1000, acceptedKeys: [k1Key]
        )
    }

    /// Trace d'un paiement depuis le Main account : nonce -42, préparé au ledger 1000, autorisation valable jusqu'à 1120.
    private func trace(hash: String?, maxTime: UInt64?) -> PaymentTrace {
        var trace = preparedFromAccount().trace
        trace.transactionHash = hash
        trace.transactionMaxTime = maxTime
        return trace
    }

    /// Enveloppe d'une transaction qui porte l'entrée du Main account signée, avec un nonce donné.
    private func envelope(nonce: Int64) throws -> String {
        let signed = try entry(Self.signedAccountEntry)
        var credentials = try SorobanAuth.addressCredentials(signed)
        credentials.nonce = nonce
        let withNonce = SorobanAuthorizationEntryXDR(credentials: .addressV2(credentials), rootInvocation: signed.rootInvocation)
        let transaction = try ChimpDAO.SorobanClient(config: .testnet).contractCall(
            source: try Account(accountId: ChimpNetworkConfig.testnet.feePayer, sequenceNumber: 1),
            contract: xlmSAC, function: "transfer",
            arguments: try SACClient.transferArguments(from: account, to: admin, units: 10_000_000), auth: [withNonce]
        )
        return try transaction.encodedEnvelope()
    }

    private func entry(_ base64: String) throws -> SorobanAuthorizationEntryXDR {
        try XDRDecoder.decode(SorobanAuthorizationEntryXDR.self, data: Data(base64Encoded: base64)!)
    }

    private func base64<T: XDREncodable>(_ value: T) throws -> String {
        Data(try XDREncoder.encode(value)).base64EncodedString()
    }
}

/// Faux RPC pour « Check again » : réponses prévues, et ce qui a été demandé.
private final class FakeLedger: PaymentLedger, @unchecked Sendable {
    var lookup: ChimpDAO.SorobanClient.TransactionLookup?
    var latest: (sequence: UInt32, closeTime: UInt64)
    var scan = ChimpDAO.SorobanClient.EventScan(transactionHashes: [], oldestLedger: 1, latestLedger: 99_999)
    var envelopes: [String: String] = [:]
    private(set) var scanned = false
    private(set) var scannedRange: ClosedRange<UInt32>?

    init(lookup: ChimpDAO.SorobanClient.TransactionLookup? = nil, latest: (UInt32, UInt64) = (0, 0)) {
        self.lookup = lookup
        self.latest = latest
    }

    func lookUpTransaction(_ hash: String) async throws -> ChimpDAO.SorobanClient.TransactionLookup {
        guard let lookup else { throw StellarError.rpc("no lookup scripted") }
        return lookup
    }

    func latestLedgerInfo() async throws -> (sequence: UInt32, closeTime: UInt64) { latest }

    func eventTransactions(contract: String, topics: [String], startLedger: UInt32, endLedger: UInt32) async throws -> ChimpDAO.SorobanClient.EventScan {
        scanned = true
        scannedRange = startLedger...endLedger
        return scan
    }

    func transactionEnvelope(_ hash: String) async throws -> String? { envelopes[hash] }
}

/// Infineon simulée : lit sa clé, vérifie un PIN, signe (DER fixe) ; garde toutes les commandes reçues.
private final class PaymentInfineon: APDUTransport, @unchecked Sendable {
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
