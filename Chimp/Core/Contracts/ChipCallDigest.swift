import CryptoKit
import Foundation
import stellarsdk

/// `call_digest` de `chimpdao_chip_auth` (`reference/chimp-contracts/contracts/chip-auth/src/verify.rs`) : ce qu'une puce
/// atteste pour **un** appel, `sha256(domaine ‖ XDR(adresse du contrat) ‖ XDR(Symbol fonction) ‖ XDR(Vec arguments) ‖
/// XDR(u32 nonce))`. Portage de `callDigest` (`reference/terminal/src/chain/chip-auth.ts`), identique octet pour octet au
/// Rust (vecteur figé du terminal dans `EnrolmentTests`). Partagé par `nfc-nft` (mint, mode admin) et `prize` (retrait
/// d'une carte partenaire, dans l'app).
enum ChipCallDigest {
    static func callDigest(domain: String, contractID: String, function: String, arguments: [SCValXDR], nonce: UInt32) throws -> Data {
        var preimage = Data(domain.utf8)
        preimage.append(contentsOf: try XDREncoder.encode(SCValXDR.address(try SCAddressXDR(contractId: contractID))))
        preimage.append(contentsOf: try XDREncoder.encode(SCValXDR.symbol(function)))
        preimage.append(contentsOf: try XDREncoder.encode(SCValXDR.vec(arguments)))
        preimage.append(contentsOf: try XDREncoder.encode(SCValXDR.u32(nonce)))
        return Data(SHA256.hash(data: preimage))
    }
}
