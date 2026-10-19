import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

// Mode admin (CHIMP_ADMIN) : absent de la Release, donc du schéma « Chimp Release Tests ».
#if CHIMP_ADMIN

// Code du mode admin : ces tests tournent avec l'action Test du schéma (configuration Debug, drapeau `CHIMP_ADMIN`).

/// Tranche 2, phase 4, étape 4 : prolongation de la durée de vie du vault (mode admin). Clés du ledger comparées à
/// `@stellar/stellar-sdk` 14.1.1 (`LedgerKey.contractData(… instance, persistent)` et `LedgerKey.contractCode`) pour le
/// vault XLM `CCLV4H7W…` et son code (`f345228d…`, relevé sur testnet le 2026-10-15).
struct ContractLifetimeTests {
    @Test("Clés de l'instance et du code : identiques au SDK JS")
    func ledgerKeys() throws {
        let vault = "CCLV4H7WTLJQ7ATLHBBQV2WW3OINF3FOY5XZ7VPHZO7NH3D2ZS4GFSF6"
        #expect(try ContractLifetime.instanceKey(vault).xdrEncoded == "AAAABgAAAAGXXh/2mtMPgms4Qwrq1tuQ0uyux2+f1efLvtPsesy4YgAAABQAAAAB")
        let hash = try #require(Data(hex: "f345228dca59c6605789620e9ec62ff4847a0927c33dac7581a955fe746016be"))
        #expect(try ContractLifetime.codeKey(hash).xdrEncoded == "AAAAB/NFIo3KWcZgV4liDp7GL/SEegknwz2sdYGpVf50YBa+")
    }

    @Test("Cibles : le vault et sa stratégie, lus dans Config/ ; durée visée sous la limite des frais d'une transaction")
    func targets() {
        let targets = ContractLifetime.vaultTargets(.testnet)
        #expect(targets.map(\.contract) == ["CCLV4H7WTLJQ7ATLHBBQV2WW3OINF3FOY5XZ7VPHZO7NH3D2ZS4GFSF6", "CDVLOSPJPQOTB6ZCWO5VSGTOLGMKTXSFWYTUP572GTPNOWX4F76X3HPM"])
        #expect(ContractLifetime.extensionLedgers == 1_555_200)
    }

    @Test("Date indicative : ledgers restants × 5,8 s")
    func estimatedDate() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ContractLifetime.estimatedDate(of: 1_100, latest: 100, now: now) == now.addingTimeInterval(5_800))
        #expect(ContractLifetime.estimatedDate(of: 100, latest: 100, now: now) == now)
    }
}
#endif
