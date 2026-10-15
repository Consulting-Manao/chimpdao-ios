import SwiftUI

/// L'avertissement unique du rendement (maquettes B2, B3, F1 à F8, I1g ; principe 6 de la tranche 2) : où va l'argent,
/// protocoles nommés, puis « Not guaranteed », « Not advice », « You keep control of your money ». Sur **chaque** écran
/// du vault, jamais un taux.
struct ChimpVaultNotice: View {
    /// « This vault lends your XLM on Blend through DeFindex ».
    let sentence: LocalizedStringKey
    /// Les pastilles seules (sous un texte qui dit déjà où va l'argent).
    var chipsOnly = false
    /// Sur un fond de couleur (F5, F7s) : texte de cette encre, pastilles blanches translucides.
    var ink: Color?

    init(asset: String, protocols: [String], ink: Color? = nil) {
        let runner = protocols.first ?? "DeFindex"
        let lender = protocols.last ?? "Blend"
        sentence = "This vault lends your \(asset) on \(lender) through \(runner)"
        self.ink = ink
    }

    init(chipsOnly: Bool) {
        sentence = ""
        self.chipsOnly = chipsOnly
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
            if !chipsOnly {
                Text(sentence)
                    .chimpFont(.captionStrong)
                    .foregroundStyle(ink ?? Color(.chimpTextPrimary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ChimpFlowLayout(spacing: 5) {
                chip("Not guaranteed")
                chip("Not advice")
                chip("You keep control of your money")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func chip(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .chimpFont(.captionS)
            .fontWeight(.black)
            .foregroundStyle(ink == nil ? Color(.chimpTextPrimary) : Color(.chimpTicketInk))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(ink == nil ? Color(.chimpSurface) : .white.opacity(0.45)))
            .overlay { Capsule().strokeBorder(ink ?? Color(.chimpOutline), lineWidth: ChimpBorder.thin) }
    }
}

/// Une rangée qui passe à la ligne quand la place manque (pastilles).
struct ChimpFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

#Preview {
    VStack(spacing: 20) {
        ChimpVaultNotice(asset: "XLM", protocols: ["DeFindex", "Blend"])
        ChimpVaultNotice(chipsOnly: true)
    }
    .padding()
    .background(Color(.chimpBackground))
}
