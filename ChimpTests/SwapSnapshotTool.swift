import SwiftUI
import Testing
@testable import ChimpDAO

/// Outil de développement, pas un test : rend les écrans du swap (E3 et ses états, E4, E4i, E4p, E5, E6, attente) en
/// images PNG, en clair et en sombre, pour les comparer à la maquette. Ne s'exécute que sur demande :
/// `TEST_RUNNER_CHIMP_SNAPSHOTS=/chemin/du/dossier xcodebuild test … -only-testing:ChimpTests/SwapSnapshotTool`.
@MainActor
struct SwapSnapshotTool {
    static let folder = ProcessInfo.processInfo.environment["CHIMP_SNAPSHOTS"]

    private func model(_ quote: MockSwapService.QuoteScenario = .normal, result: MockSendService.ResultScenario = .sent, drawerID: String? = nil) async -> (SwapFlowModel, MockSwapService) {
        let service = MockSwapService(quoteScenario: quote, resultScenario: result, delay: .zero)
        service.send.authorizationWait = .seconds(600)
        let model = SwapFlowModel(service: service, initialDrawerID: drawerID, quoteDebounce: .zero)
        await model.loadIfNeeded()
        return (model, service)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    private func save(_ name: String, _ view: some View) {
        guard let folder = Self.folder else { return }
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: view
                .frame(width: 393, height: 852)
                .environment(\.colorScheme, scheme)
                .environment(\.locale, Locale(identifier: "en_US")))
            renderer.scale = 2
            guard let image = renderer.uiImage, let data = image.pngData() else { continue }
            try? data.write(to: URL(fileURLWithPath: folder).appending(path: "\(name)-\(scheme == .light ? "light" : "dark").png"))
        }
    }

    @Test(.enabled(if: SwapSnapshotTool.folder != nil))
    func render() async throws {
        // E3 · devis
        var (m, s) = await model()
        m.setAmount(400); await m.refreshQuote()
        save("E3", SwapAmountView(model: m, onBack: {}))
        // E3a · devis en cours
        (m, s) = await model()
        m.setAmount(400)
        save("E3a", SwapAmountView(model: m, onBack: {}))
        // E3b, E3c
        (m, s) = await model(.noRoute); m.setAmount(400); await m.refreshQuote()
        save("E3b", SwapAmountView(model: m, onBack: {}))
        (m, s) = await model(.protocolUnavailable); m.setAmount(400); await m.refreshQuote()
        save("E3c", SwapAmountView(model: m, onBack: {}))
        // E3d · pas assez, depuis Banana
        (m, s) = await model(drawerID: "0688"); m.setAmount(400); await m.refreshQuote()
        save("E3d", SwapAmountView(model: m, onBack: {}))
        // E3e · gros impact
        (m, s) = await model(.bigImpact); m.setAmount(400); await m.refreshQuote()
        save("E3e", SwapAmountView(model: m, onBack: {}))
        // E3f · un envoi en attente
        let pendingService = MockSwapService(delay: .zero)
        pendingService.pendingSend = PendingSend(
            trace: PaymentTrace(token: "xlm", from: "main", destination: "tom", units: 1, nonce: 1, preparedAtLedger: 1, expirationLedger: 121),
            recipient: "tom", recipientName: nil, drawerTitle: "Main account", asset: "xlm", amount: 1, signedAt: .now
        )
        let blocked = SwapFlowModel(service: pendingService, quoteDebounce: .zero)
        await blocked.loadIfNeeded(); blocked.setAmount(400); await blocked.refreshQuote()
        save("E3f", SwapAmountView(model: blocked, onBack: {}))

        // E4 · vérification, E4i
        (m, s) = await model(); m.setAmount(400); await m.refreshQuote(); m.continueToReview()
        save("E4", SwapReviewView(model: m))
        (m, s) = await model(.bigImpact); m.setAmount(400); await m.refreshQuote(); m.continueToReview()
        save("E4i", SwapReviewView(model: m))
        // E4p
        (m, s) = await model(.priceMovesBeforeSigning); m.setAmount(400); await m.refreshQuote(); m.continueToReview()
        m.confirmReview(); await waitUntil { m.priceMoved?.newDraft != nil }
        save("E4p", SwapReviewView(model: m))

        // E5 · swappé
        (m, s) = await model(); m.setAmount(400); await m.refreshQuote(); m.continueToReview()
        m.confirmReview(); await waitUntil { m.stage == .enteringPin }; m.pinEntered("1234"); m.scanCard()
        await waitUntil { if case .finished(.sent) = m.stage { true } else { false } }
        save("E5", SwapReviewView(model: m))
        // E6 · pas sûr
        (m, s) = await model(result: .undetermined); m.setAmount(400); await m.refreshQuote(); m.continueToReview()
        m.confirmReview(); await waitUntil { m.stage == .enteringPin }; m.pinEntered("1234"); m.scanCard()
        await waitUntil { m.stage == .finished(.undetermined) }
        save("E6", SwapReviewView(model: m))
        // Attente
        (m, s) = await model(result: .rejectedThenNothingSent); m.setAmount(400); await m.refreshQuote(); m.continueToReview()
        m.confirmReview(); await waitUntil { m.stage == .enteringPin }; m.pinEntered("1234"); m.scanCard()
        await waitUntil { if case .finished(.waiting) = m.stage { true } else { false } }
        save("Waiting", SwapReviewView(model: m))
        _ = s

        // I1s · Activity
        let activity = ActivityViewModel(source: MockActivityDataSource(scenario: .standard))
        await activity.refresh()
        save("I1s", ActivityView(model: activity))
        if let record = activity.records.first(where: { $0.event == .swap }), let receipt = activity.receipt(for: record) {
            save("I1s1", ScrollView { ActivityReceiptSheet(receipt: receipt, model: activity) }.background(Color(.chimpBackground)))
        }
    }
}
