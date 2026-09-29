import SwiftUI

/// Points de pagination de la visite guidée : la page courante est une pilule allongée.
struct ChimpPageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                if index == current {
                    Capsule().fill(Color(.chimpTextPrimary)).frame(width: 26, height: 7)
                } else {
                    Capsule()
                        .fill(Color(.chimpSurfaceSecondary))
                        .overlay(Capsule().strokeBorder(Color(.chimpTextSecondary), lineWidth: 1))
                        .frame(width: 7, height: 7)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(current + 1) of \(count)"))
    }
}

#Preview {
    VStack(spacing: 20) {
        ForEach(0..<4) { ChimpPageDots(count: 4, current: $0) }
    }
    .padding()
    .background(Color(.chimpBackground))
}
