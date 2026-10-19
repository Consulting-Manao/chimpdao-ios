import SwiftUI

/// Prêt XOXNO (phase 7) : les textes et avertissements partagés. La page d'un pot est G2 (`PotView`), les écrans de dépôt
/// et de retrait sont ceux du vault. Jamais un taux.

/// Les risques du prêt, dits simplement : où va l'argent, puis les trois textes obligatoires, puis les pastilles.
struct LendingRiskNotice: View {
    let asset: String
    var ink: Color?

    static let risks: [LocalizedStringKey] = [
        "No published audit for Stellar yet",
        "Withdrawals can be paused or limited",
        "If a borrower doesn't repay, depositors share the loss",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.s) {
            Text("XOXNO lends your \(asset) to borrowers. You never borrow.")
                .chimpFont(.captionStrong)
                .foregroundStyle(ink ?? Color(.chimpTextPrimary))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(Self.risks.enumerated()), id: \.offset) { _, risk in
                LendingRiskLine(text: risk, ink: ink)
            }
            ChimpVaultNotice(chipsOnly: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LendingRiskLine: View {
    let text: LocalizedStringKey
    var ink: Color?

    var body: some View {
        HStack(alignment: .top, spacing: ChimpSpacing.s) {
            Text(verbatim: "!")
                .chimpFont(.rowTitle)
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(.chimpNegative)))
                .accessibilityHidden(true)
            Text(text)
                .chimpFont(.captionStrong)
                .foregroundStyle(ink ?? Color(.chimpTextPrimary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Texte d'une position qu'on ne peut pas déplacer.
enum LendingText {
    static let needsRenewal: LocalizedStringKey = "This position needs to be renewed before you can see or move it. Your money is still there."
    static let hasDebt: LocalizedStringKey = "This position has a loan on it. ChimpDAO never borrows, so it can't be moved from here."
}
