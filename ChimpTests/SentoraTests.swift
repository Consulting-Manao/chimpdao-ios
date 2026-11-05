import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Vault Sentora : appels, arbre d'autorisation, bornes, lecture du dépôt. Vecteurs : la copie de test du 2026-11-05
/// (`tools/grow-testnet`, même wasm que le mainnet), après un vrai dépôt de 1 USDC puis un retrait de 0,4 USDC par le compte
/// `GDEC3N4X…` (`smoke.mjs`) : il reste 0,6 USDC (6 000 000 unités).
struct SentoraTests {
    static let vault = "CDGXALH6TAXVN3G26TQYMH7ORXESODQQHXL2BNGMZEC4BP5NMHMIAL2V"
    static let usdc = "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA"
    static let holder = "GDEC3N4XBMNBWBTAK3CAHNSOFWVP3PGRNI6LFRHXHQRL7QQSC5IJQVV4"
    static let main = "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"
    /// `getLedgerEntries` sur le testnet, le 2026-11-05.
    static let depositKey = "AAAABgAAAAHNcCz+mC9W7Nr04YYf7o3JJw4QPdegtMzJBcC/rWHYgAAAABAAAAABAAAAAgAAAA8AAAAHRGVwb3NpdAAAAAASAAAAAAAAAADILbeXCxobBmBWxAO2Ti2q/bzRajyyxPc8Ir/CEhdQmAAAAAE="
    static let depositEntry = "AAAABgAAAAAAAAABzXAs/pgvVuza9OGGH+6NyScOED3XoLTMyQXAv61h2IAAAAAQAAAAAQAAAAIAAAAPAAAAB0RlcG9zaXQAAAAAEgAAAAAAAAAAyC23lwsaGwZgVsQDtk4tqv280Wo8ssT3PCK/whIXUJgAAAABAAAAEQAAAAEAAAACAAAADwAAAAZhbW91bnQAAAAAAAkAAAAAAAAAAAAAAAAAW42AAAAADwAAAAVvd25lcgAAAAAAABIAAAAAAAAAAMgtt5cLGhsGYFbEA7ZOLar9vNFqPLLE9zwiv8ISF1CY"
    static let instanceEntry = "AAAABgAAAAAAAAABzXAs/pgvVuza9OGGH+6NyScOED3XoLTMyQXAv61h2IAAAAAUAAAAAQAAABMAAAAAymuFoT5TNTkSru4tR0KDD8WAdmYN3mT9rUpq+8ypZ08AAAABAAAABgAAABAAAAABAAAAAQAAAA8AAAAFQWRtaW4AAAAAAAASAAAAAAAAAADILbeXCxobBmBWxAO2Ti2q/bzRajyyxPc8Ir/CEhdQmAAAABAAAAABAAAAAQAAAA8AAAAMRGVwb3NpdEFzc2V0AAAAEgAAAAFQRc1ewHKado/VrQJQWFLfTwKNzoMOWsUiCbpISDsvAQAAABAAAAABAAAAAQAAAA8AAAAGRXNjcm93AAAAAAASAAAAAfj9+BrVRGtS1eZ9am5AKJM3fOSFi9x6Px2XMqoemj8DAAAAEAAAAAEAAAABAAAADwAAAA1OZXh0RGVwb3NpdElkAAAAAAAABQAAAAAAAAACAAAAEAAAAAEAAAABAAAADwAAAAZQYXVzZWQAAAAAAAAAAAAAAAAAEAAAAAEAAAABAAAADwAAAA5Ub3RhbFByaW5jaXBhbAAAAAAACQAAAAAAAAAAAAAAAABbjYA="

    private func value(_ base64: String) throws -> SCValXDR {
        guard case .contractData(let data) = try LedgerEntryDataXDR(fromBase64: base64) else { throw StellarError.invalidResponse("not contract data") }
        return data.val
    }

    @Test("La clé du dépôt d'un tiroir est celle que le vault écrit : `Deposit(adresse)`, persistante")
    func depositKey() throws {
        #expect(try SentoraCalls.depositKey(vault: Self.vault, holder: Self.holder) == Self.depositKey)
    }

    @Test("Le dépôt relu sur la chaîne : 0,6 USDC à ce tiroir ; l'entrée d'un autre propriétaire est refusée")
    func principal() throws {
        let record = try value(Self.depositEntry)
        #expect(SentoraCalls.principal(record, holder: Self.holder) == 6_000_000)
        #expect(SentoraCalls.principal(record, holder: Self.main) == nil)
        #expect(SentoraCalls.principal(.u32(1), holder: Self.holder) == nil)
    }

    @Test("L'état du vault relu dans son instance : pas en pause, 0,6 USDC au total")
    func state() throws {
        let state = try SentoraCalls.state(instance: try value(Self.instanceEntry))
        #expect(state == SentoraCalls.VaultState(paused: false, totalPrincipal: 6_000_000))
        #expect(throws: StellarError.self) { try SentoraCalls.state(instance: .u32(0)) }
    }

    @Test("Dépôt : `deposit(tiroir, u128, None)`, relu à l'identique ; l'arbre prend le montant au tiroir vers le vault")
    func deposit() throws {
        let call = try SentoraCalls.deposit(vault: Self.vault, from: Self.main, units: 10_000_000)
        #expect(call.function == "deposit" && call.arguments.count == 3)
        #expect(ContractArgument.uint128(call.arguments[1]) == 10_000_000)
        guard case .void = call.arguments[2] else { Issue.record("referral must be None"); return }
        #expect(SentoraCalls.decode(call, vault: Self.vault) == .init(function: "deposit", caller: Self.main, units: 10_000_000))
        let shape = SentoraAuthShape(vault: Self.vault, asset: Self.usdc)
        #expect(shape.signer(of: call) == Self.main)
        #expect(try shape.pulls(of: call, from: Self.main) == [try TokenShape.transfer(token: Self.usdc, from: Self.main, to: Self.vault, units: 10_000_000)])
        #expect(try shape.pulls(of: call, from: Self.holder).isEmpty, "Personne d'autre ne signe")
        let terms = try SentoraCalls.terms(of: call, vault: Self.vault, asset: Self.usdc)
        #expect(terms.action == .deposit && terms.assetIn == Self.usdc && terms.amountIn == 10_000_000 && terms.minimumOut == nil)
    }

    @Test("Retrait : `withdraw(tiroir, u128)`, le montant exact revient (c'est aussi le minimum signé), rien n'est pris")
    func withdraw() throws {
        let call = try SentoraCalls.withdraw(vault: Self.vault, from: Self.main, units: 4_000_000)
        #expect(call.function == "withdraw" && call.arguments.count == 2)
        #expect(try SentoraAuthShape(vault: Self.vault, asset: Self.usdc).pulls(of: call, from: Self.main).isEmpty)
        let terms = try SentoraCalls.terms(of: call, vault: Self.vault, asset: Self.usdc)
        #expect(terms.action == .withdraw && terms.assetOut == Self.usdc && terms.amountIn == 4_000_000 && terms.minimumOut == 4_000_000)
        try BoundsCheck.verify(shown: terms, signed: terms, quotedOut: 4_000_000, now: 0)
    }

    @Test("Refusé plutôt que deviné : un autre vault, un parrainage, un montant nul ne sont pas des appels Sentora reconnus")
    func malformed() throws {
        let call = try SentoraCalls.deposit(vault: Self.vault, from: Self.main, units: 1)
        #expect(SentoraCalls.decode(call, vault: Self.usdc) == nil)
        let referred = ContractCall(contract: Self.vault, function: "deposit", arguments: [call.arguments[0], call.arguments[1], .string("x")])
        #expect(SentoraCalls.decode(referred, vault: Self.vault) == nil)
        #expect(throws: YieldError.self) { try SentoraCalls.deposit(vault: Self.vault, from: Self.main, units: 0) }
        #expect(throws: ContractArgument.ArgumentError.self) { try SentoraCalls.terms(of: referred, vault: Self.vault, asset: Self.usdc) }
    }

    @Test("Les refus du vault ont un nom : 100 en pause, 101 dépôt insuffisant, 10 solde du SAC")
    func errors() {
        #expect(SentoraCalls.yieldError(for: StellarError.simulationFailed("HostError: Error(Contract, #101)")) == .notEnoughShares)
        #expect(SentoraCalls.yieldError(for: StellarError.simulationFailed("HostError: Error(Contract, #100)")) == .vaultUnavailable)
        #expect(SentoraCalls.yieldError(for: StellarError.simulationFailed("HostError: Error(Contract, #10)")) == .insufficientBalance)
        #expect(SentoraCalls.yieldError(for: StellarError.simulationFailed("HostError: Error(Contract, #7)")) == nil)
    }

    @Test("Le pot Sentora : le dépôt tel quel (rien ne « pousse »), « Add » et « Take out » mènent à son parcours")
    func pot() async throws {
        let context = try await MockLendingService(delay: .zero, mark: .sentora).fetchContext()
        #expect(context.vault.mark == .sentora && context.vault.name == "Sentora USDC")
        let pot = try #require(GrowPots.build(vault: nil, lending: nil, savings: [], sentora: context).first)
        #expect(pot.mark == .sentora && pot.value == 20 && pot.growth == 0)
        #expect(MainTabView.addRoute(.sentora, drawerID: "main") == .sentoraDeposit(drawerID: "main"))
        #expect(MainTabView.takeOutRoute(.sentora, drawerID: "main") == .sentoraWithdraw(drawerID: "main"))
        #expect(GrowView.plantRoute(.sentora, drawer: nil, fallbackAddress: nil) == .sentoraDeposit(drawerID: nil))
        #expect(ChimpNetworkConfig.testnet.vaultLabels[Self.vault]?.name == "Sentora USDC")
    }
}
