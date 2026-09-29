import SwiftUI

extension View {
    /// Fond des écrans pleins (A1, A2, H3…) : couleur de l'en-tête + motif, jusque sous les barres du système.
    func chimpFullScreenBackground(patternOpacity: Double = ChimpOpacity.pattern) -> some View {
        background {
            Color(.chimpHeader)
                .overlay { ChimpPattern(opacity: patternOpacity) }
                .ignoresSafeArea()
        }
    }
}

/// Bulle de Chimpy centrée, pointe vers le bas (A1 : « Hi, I'm Chimpy! »), posée au-dessus de son illustration.
struct ChimpSpeechBubble: View {
    let text: LocalizedStringKey

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ChimpRadius.chimpCard)
        Text(text)
            .chimpFont(.rowTitle)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .foregroundStyle(Color(.chimpOnCardBright))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, ChimpSpacing.m + ChimpBorder.regular)
            .padding(.horizontal, ChimpSpacing.l + ChimpBorder.regular)
            .frame(maxWidth: .infinity)
            .background { shape.fill(Color(.chimpQRBackground)) }
            .overlay { shape.strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
            .background { shape.fill(Color(.chimpOutline)).offset(x: ChimpShadow.card.x, y: ChimpShadow.card.y) }
            .overlay(alignment: .bottom) {
                // Pointe : un carré tourné de 45°, dont seuls les deux côtés du bas ont un contour.
                ChimpBubbleTail()
                    .fill(Color(.chimpQRBackground))
                    .overlay { ChimpBubbleTail().stroke(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(45))
                    .offset(y: 9)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Chimpy: \(Text(text))"))
    }
}

/// Coin bas-droit d'un carré (côtés droit et bas), qui devient la pointe d'une bulle une fois tourné de 45°.
private struct ChimpBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

/// Bandeau du bas des écrans « tapez la carte » (A2) : fond assombri, liseré clair, petite image et phrase rassurante.
struct ChimpFullScreenBanner: View {
    let text: LocalizedStringKey
    var image: ImageResource = .tileBanana

    var body: some View {
        HStack(spacing: ChimpSpacing.m) {
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(width: 38)
                .accessibilityHidden(true)
            Text(text)
                .chimpFont(.bodyM)
                .lineSpacing(3)
                .foregroundStyle(.chimpOnHeaderSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, ChimpSpacing.lg)
        .padding(.horizontal, ChimpSpacing.fullScreenMargin)
        .padding(.bottom, ChimpSpacing.s)
        .frame(maxWidth: .infinity)
        .background {
            Color(.chimpHeaderShade)
                .overlay(alignment: .top) {
                    Color(.chimpHeaderBannerBorder).frame(height: ChimpBorder.thin)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

#Preview {
    VStack(spacing: 30) {
        ChimpSpeechBubble(text: "Hi, I'm Chimpy! Ready to swing into your jungle?")
            .padding(.horizontal, 34)
        Spacer()
        ChimpFullScreenBanner(text: "Nothing is moved yet. I'm just saying hello to the card.")
    }
    .chimpFullScreenBackground()
}
