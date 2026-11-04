import SwiftUI

/// L'œil des en-têtes (Wallet, Grow) : ouvert, les montants sont visibles ; barré, ils deviennent « **** » partout
/// (`chimpHidesAmounts`). Zone tactile de 44 pt.
struct ChimpAmountsEyeButton: View {
    let isHiding: Bool
    var color: Color = Color(.chimpOnHeaderSecondary)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isHiding ? "eye.slash.fill" : "eye.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
                .expandedTouchTarget(visualSize: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isHiding ? "Show amounts" : "Hide amounts")
    }
}

#Preview {
    HStack(spacing: 30) {
        ChimpAmountsEyeButton(isHiding: false) {}
        ChimpAmountsEyeButton(isHiding: true) {}
    }
    .padding()
    .background(Color(.chimpHeader))
}
