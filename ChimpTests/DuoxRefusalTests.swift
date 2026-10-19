import Foundation
import Testing
@testable import ChimpDAO

/// Cartes DUOX refusées tant que F1 n'est pas fait (décisions du 2026-10-19 ; refusées sur le mainnet, donc en Release) :
/// à la lecture, avant toute vérification en ligne et toute signature, avec un message clair.
struct DuoxRefusalTests {
    /// Le testnet, mais sans DUOX : ce que fait le mainnet.
    private var refusingConfig: ChimpNetworkConfig {
        var config = ChimpNetworkConfig.testnet
        config.features.duoxCards = false
        return config
    }

    private func onboarding(_ config: ChimpNetworkConfig, reader: MockChipReader.Scenario) -> OnboardingModel {
        OnboardingModel(
            session: AppSession(store: InMemoryLocalWalletStore(), config: config),
            reader: MockChipReader(scenario: reader, delay: .zero),
            service: MockOnboardingService(scenario: .fresh, delay: .zero),
            signer: MockChipSigner(delay: .zero),
            makeSetup: {
                try AccountSetupModel(
                    choice: $0, service: MockAccountSetupService(delay: .zero),
                    creator: AccountCreator(chain: MockAccountCreationChain(delay: .zero)), signer: MockChipSigner(delay: .zero), session: nil
                )
            }
        )
    }

    @Test("Le mainnet refuse les DUOX ; le testnet les accepte encore")
    func perNetwork() {
        #expect(!ChimpNetworkConfig.mainnetDraft.features.duoxCards)
        #expect(ChimpNetworkConfig.testnet.features.duoxCards)
    }

    @Test("Onboarding (A2) : une DUOX est arrêtée à la lecture, avec un message clair ; une Infineon passe")
    func onboardingRefusesDuox() async throws {
        let model = onboarding(refusingConfig, reader: .duox)
        model.path = [.reading]
        await model.scan()
        guard case .failed(let problem) = model.readingState else { Issue.record("expected a refusal"); return }
        #expect(problem.kind == .duoxNotSupported)
        #expect(model.path == [.reading], "Aucun écran suivant : ni création, ni rejoindre, ni reconnexion")
        let text = String(describing: CardReadingView.message(for: .duoxNotSupported))
        #expect(text.contains("DUOX") && text.contains("Infineon"))

        let infineon = onboarding(refusingConfig, reader: .infineon)
        infineon.path = [.reading]
        await infineon.scan()
        #expect(infineon.path.count == 2, "Une Infineon continue vers A3")

        let testnet = onboarding(.testnet, reader: .duox)
        testnet.path = [.reading]
        await testnet.scan()
        #expect(testnet.path.count == 2, "Sur le testnet, la DUOX est encore acceptée")
    }

    @Test("Ajouter une carte (G1) : une nouvelle carte DUOX est refusée, rien n'est lié ni ajouté")
    func addCardRefusesDuox() async {
        let account = "CASBWZTE3GU4VVBC2Q3V6VXCHTG7VLHG45AJXEJ64IVNQSDLEDRBD3RP"
        let service = MockAddCardService(delay: .zero)
        let model = AddCardModel(
            entry: .wallet(account: account), session: AppSession(store: InMemoryLocalWalletStore(), config: refusingConfig),
            reader: MockChipReader(scenario: .duox, delay: .zero), signer: MockChipSigner(delay: .zero), service: service
        )
        await model.scanNewCard()
        #expect(model.problem?.kind == .card(.duoxNotSupported))
        #expect(model.screen == .tapNew)
        #expect(service.linkCount == 0 && service.addCount == 0)
    }
}
