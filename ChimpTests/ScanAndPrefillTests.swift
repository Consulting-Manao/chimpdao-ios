import Foundation
import Testing
@testable import ChimpDAO

/// Retours du call avec Pamphile (2026-10-01), thème 2 : code QR en C1 (adresse ou lien SEP-7), envois préremplis
/// (« Pay again », « Send back »), texte de partage de Recevoir.
struct ScanAndPrefillTests {
    private let rules = ScanRules(config: .testnet)
    private let maya = MockSendService.mayaAddress
    private let testnet = "network_passphrase=Test%20SDF%20Network%20%3B%20September%202015"

    // MARK: Code QR

    @Test("Adresse seule : G, M (memo ID dedans) ou C ; espaces autour ignorés")
    func plainAddresses() throws {
        #expect(try ScannedCodeParser.parse(" \(maya)\n", rules: rules).get() == SendPrefill(address: maya, origin: .scan))
        let muxed = try ScannedCodeParser.parse(MockSendService.exchangeMuxedAddress, rules: rules).get()
        #expect(muxed.address == MockSendService.exchangeMuxedAddress)
        let contract = try ScannedCodeParser.parse(MockReceiveDataSource.mainAddress, rules: rules).get()
        #expect(contract.address == MockReceiveDataSource.mainAddress)
    }

    @Test("Adresse refusée : mêmes raisons qu'une adresse collée ; autre chose qu'une adresse : refus")
    func refusedCodes() {
        let secret = "S" + String(repeating: "A", count: 55)
        #expect(ScannedCodeParser.parse(secret, rules: rules) == .failure(.address(.secretKey)))
        var typo = Array(maya)
        typo[10] = typo[10] == "A" ? "B" : "A"
        #expect(ScannedCodeParser.parse(String(typo), rules: rules) == .failure(.address(.typo)))
        #expect(ScannedCodeParser.parse("https://chimpdao.xyz", rules: rules) == .failure(.notAPaymentCode))
        #expect(ScannedCodeParser.parse("", rules: rules) == .failure(.notAPaymentCode))
    }

    @Test("SEP-7 pay : destination, montant, XLM par défaut, passphrase testnet décodée")
    func payLinkXLM() throws {
        let link = "web+stellar:pay?destination=\(maya)&amount=12.5&\(testnet)"
        #expect(try ScannedCodeParser.parse(link, rules: rules).get()
            == SendPrefill(address: maya, asset: .xlm, amount: Decimal(string: "12.5")!, origin: .scan))
        // Schéma en majuscules, sans montant.
        let noAmount = try ScannedCodeParser.parse("WEB+STELLAR:pay?destination=\(maya)&\(testnet)", rules: rules).get()
        #expect(noAmount.amount == nil)
        #expect(noAmount.asset == .xlm)
    }

    @Test("SEP-7 pay : USDC de l'émetteur de Config, memo ID ; autre émetteur ou autre actif : refus")
    func payLinkUSDC() throws {
        let issuer = ChimpNetworkConfig.testnet.usdcIssuer
        let link = "web+stellar:pay?destination=\(maya)&amount=5&asset_code=USDC&asset_issuer=\(issuer)&memo=1234567890&memo_type=MEMO_ID&\(testnet)"
        #expect(try ScannedCodeParser.parse(link, rules: rules).get()
            == SendPrefill(address: maya, memoID: 1_234_567_890, asset: .usdc, amount: 5, origin: .scan))
        let otherIssuer = "web+stellar:pay?destination=\(maya)&asset_code=USDC&asset_issuer=\(maya)&\(testnet)"
        #expect(ScannedCodeParser.parse(otherIssuer, rules: rules) == .failure(.unsupportedAsset("USDC")))
        let eurc = "web+stellar:pay?destination=\(maya)&asset_code=EURC&asset_issuer=\(issuer)&\(testnet)"
        #expect(ScannedCodeParser.parse(eurc, rules: rules) == .failure(.unsupportedAsset("EURC")))
    }

    @Test("SEP-7 : sans passphrase = réseau public (refusé sur testnet) ; tx, callback, memo texte : refus")
    func refusedLinks() {
        #expect(ScannedCodeParser.parse("web+stellar:pay?destination=\(maya)&amount=1", rules: rules) == .failure(.otherNetwork))
        let pubnet = "network_passphrase=Public%20Global%20Stellar%20Network%20%3B%20September%202015"
        #expect(ScannedCodeParser.parse("web+stellar:pay?destination=\(maya)&\(pubnet)", rules: rules) == .failure(.otherNetwork))
        #expect(ScannedCodeParser.parse("web+stellar:tx?xdr=AAAA&\(testnet)", rules: rules) == .failure(.signRequest))
        #expect(ScannedCodeParser.parse("web+stellar:pay?destination=\(maya)&callback=url%3Ahttps%3A%2F%2Fexample.com&\(testnet)", rules: rules) == .failure(.callback))
        #expect(ScannedCodeParser.parse("web+stellar:pay?destination=\(maya)&memo=hello&memo_type=MEMO_TEXT&\(testnet)", rules: rules) == .failure(.wordMemo))
        #expect(ScannedCodeParser.parse("web+stellar:pay?destination=\(maya)&memo=42&\(testnet)", rules: rules) == .failure(.wordMemo),
                "Sans memo_type, le memo est un texte : jamais deviné en memo ID")
        #expect(ScannedCodeParser.parse("web+stellar:pay?amount=1&\(testnet)", rules: rules) == .failure(.notAPaymentCode))
        #expect(ScannedCodeParser.parse("web+stellar:pay?destination=nope&\(testnet)", rules: rules) == .failure(.address(.notStellar)))
    }

    // MARK: Envoyer prérempli

    @Test("Prérempli : adresse en C1, actif et montant pour C2 ; un montant que le pavé ne sait pas taper est ignoré")
    func applyPrefill() {
        let model = SendFlowModel(service: MockSendService(delay: .zero))
        model.apply(SendPrefill(address: maya, asset: .xlm, amount: Decimal(string: "1757.5")!, origin: .payAgain))
        #expect(model.addressText == maya)
        #expect(model.asset == .xlm)
        #expect(model.amount.value == Decimal(string: "1757.5")!)
        #expect(!model.isSendingBack)

        let tooPrecise = SendFlowModel(service: MockSendService(delay: .zero))
        tooPrecise.apply(SendPrefill(address: maya, asset: .usdc, amount: Decimal(string: "0.1234567")!, origin: .payAgain))
        #expect(tooPrecise.asset == .usdc)
        #expect(tooPrecise.amount.isEmpty, "Jamais arrondi : à taper en C2")
    }

    @Test("Send back : Chimpy prévient tant que l'adresse n'a pas changé")
    func sendBackWarning() {
        let model = SendFlowModel(service: MockSendService(delay: .zero))
        model.apply(SendPrefill(address: maya, asset: .usdc, amount: 25, origin: .sendBack))
        #expect(model.isSendingBack)
        model.addressText = MockSendService.tomAddress
        #expect(!model.isSendingBack)
    }

    @Test("Scan : code accepté → C1 rempli (memo ID compris) ; code refusé → message, adresse gardée, effacé si elle change")
    func scanInModel() {
        let model = SendFlowModel(service: MockSendService(delay: .zero))
        model.addressText = MockSendService.tomAddress
        model.isScannerPresented = true
        model.scanned("web+stellar:tx?xdr=AAAA&\(testnet)")
        #expect(!model.isScannerPresented)
        #expect(model.scanIssue == .signRequest)
        #expect(model.addressText == MockSendService.tomAddress)
        model.scanned("web+stellar:pay?destination=\(maya)&amount=3&memo=77&memo_type=MEMO_ID&\(testnet)")
        #expect(model.scanIssue == nil)
        #expect(model.addressText == maya)
        #expect(model.memoText == "77")
        #expect(model.asset == .xlm)
        #expect(model.amount.value == 3)
        model.scanned("nonsense")
        #expect(model.scanIssue == .notAPaymentCode)
        model.addressText = ""
        #expect(model.scanIssue == nil)
    }

    @Test("C9 « Pay again » : même adresse, même actif, même montant ; jamais pour un Move")
    func sendAgainAfterSent() async {
        let service = MockSendService(delay: .zero, nfcDelay: .zero)
        let model = SendFlowModel(service: service)
        model.pasteAddress(maya)
        await model.load()
        model.setAmount(25)
        model.continueToReview()
        model.confirmReview()
        for _ in 0..<300 where model.signingStage != .enteringPin {
            try? await Task.sleep(for: .milliseconds(10))
        }
        model.pinEntered("1234")
        model.scanCard()
        for _ in 0..<300 where model.sendAgainPrefill == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.sendAgainPrefill == SendPrefill(address: maya, asset: .usdc, amount: 25, origin: .payAgain))

        let move = SendFlowModel(service: MockSendService(delay: .zero), kind: .move)
        #expect(move.sendAgainPrefill == nil)
    }

    // MARK: Partage de Recevoir

    @Test("Partage : adresse complète, actifs acceptés, avertissement testnet ; wallet d'une carte nommé")
    func shareText() {
        let address = MockReceiveDataSource.mainAddress
        #expect(ReceiveViewModel.shareText(address: address, drawerTitle: nil, network: .testnet) == """
        Send me money on Stellar Testnet:
        \(address)

        Accepted: XLM and USDC.
        ⚠️ Stellar Testnet only. Money sent from another network will be lost.
        """)
        #expect(ReceiveViewModel.shareText(address: address, drawerTitle: "Jungle's wallet", network: .testnet)
            .hasPrefix("Send me money on Jungle's wallet (Stellar Testnet):\n\(address)\n"))
        #expect(ReceiveViewModel.shareText(address: address, drawerTitle: nil, network: .mainnet) == """
        Send me money on Stellar:
        \(address)

        Accepted: XLM and USDC.
        """)
    }
}
