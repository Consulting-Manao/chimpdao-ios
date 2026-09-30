import Foundation

/// Ce que I6 « Switch account » montre d'un compte : « 3 cards · $1,485.00 ».
struct AccountSummary: Equatable {
    let cardCount: Int
    /// Total dans la devise d'affichage, ou montants par actif si un prix manque (comme le Wallet).
    let total: String
}

/// Lecture du résumé d'un compte ouvert sur ce téléphone. `ChainAccountSummaryReader` (testnet) dans l'app, un faux dans
/// les tests. Lecture seule : rien n'est signé ni envoyé.
protocol AccountSummaryReader {
    func summary(of account: SavedAccount) async throws -> AccountSummary
}

/// Mêmes lectures que le Wallet (`ChainWalletDataSource`), pour un compte qui n'est pas affiché.
struct ChainAccountSummaryReader: AccountSummaryReader {
    let wallet: ChainWalletDataSource

    func summary(of account: SavedAccount) async throws -> AccountSummary {
        let snapshot = try await wallet.fetchWallet(for: account)
        return AccountSummary(cardCount: snapshot.cards.count, total: WalletViewModel.format(snapshot).total)
    }
}

/// Nom d'un compte (I6, maquette : « Léo's account ») : le prénom du compte, sinon la fin de son adresse.
enum AccountName {
    static func text(firstName: String?, address: String) -> String {
        if let firstName, !firstName.isEmpty { return String(localized: "\(firstName)'s account") }
        return String(localized: "Account ···\(String(address.suffix(4)))")
    }
}
