import SwiftUI

/// Un easter egg en plein écran (section J de la maquette) : fond et motif, Chimpy qui se balance, un titre, une phrase,
/// un bouton. Toucher n'importe où ramène où l'on était.
struct ChimpEasterEggView: View {
    let egg: ChimpEasterEgg
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            if egg == .bananaMode { FallingBananas(isStill: reduceMotion).ignoresSafeArea() }
            VStack(spacing: 0) {
                Spacer(minLength: ChimpSpacing.l)
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: egg == .nightOwl ? 260 : 220, maxHeight: 260)
                    .chimpBob(duration: egg == .thousandaire ? 1.6 : 1.2)
                    .accessibilityHidden(true)
                Text(title)
                    .chimpFont(.celebration)
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.top, ChimpSpacing.l)
                    .accessibilityAddTraits(.isHeader)
                Text(line)
                    .chimpFont(.bodyL)
                    .fontWeight(.heavy)
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ChimpSpacing.m)
                Spacer(minLength: ChimpSpacing.l)
                ChimpButton(button, action: onDismiss)
            }
            .padding(.horizontal, ChimpSpacing.xxl)
            .padding(.bottom, ChimpSpacing.xl)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .onAppear { ChimpSoundPlayer.shared.play(egg == .thousandaire ? .money : .leaves) }
    }

    private var background: some View {
        Group {
            switch egg {
            case .bananaMode: Color(.chimpAccent)
            case .nightOwl: Color(.chimpCardLeaf).overlay(Color.black.opacity(0.45))
            case .thousandaire: Color(.chimpCardLeaf)
            }
        }
        .overlay { ChimpPattern(opacity: 0.14) }
    }

    private var image: ImageResource {
        switch egg {
        case .bananaMode: .chimpyBanana
        case .nightOwl: .chimpyHamac
        case .thousandaire: .chimpyStand
        }
    }

    private var title: LocalizedStringKey {
        switch egg {
        case .bananaMode: "Banana mode"
        case .nightOwl: "Shhh."
        case .thousandaire: "Thousand-\naire!"
        }
    }

    private var line: LocalizedStringKey {
        switch egg {
        case .bananaMode: "You found my secret stash. It was empty. I ate it. Sorry."
        case .nightOwl: "It's 3am. Your bananas are asleep, and so should you be."
        case .thousandaire: "You just crossed $1,000. Chimpy bought a tiny hat to celebrate. You can't see it. It's very tiny."
        }
    }

    private var button: LocalizedStringKey {
        switch egg {
        case .bananaMode: "Give me back my app"
        case .nightOwl: "I'm just looking"
        case .thousandaire: "Tip the hat"
        }
    }

    private var titleColor: Color { egg == .nightOwl ? Color(.chimpAccent) : Color(.chimpTicketInk) }
    private var textColor: Color { egg == .nightOwl ? .white : Color(.chimpTicketInk) }
}

/// J1 : des bananes qui tombent en tournant, en boucle (immobiles si « Réduire les animations » est activé).
private struct FallingBananas: View {
    let isStill: Bool
    private static let count = 12

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: isStill)) { context in
                let time = isStill ? 0 : context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<Self.count, id: \.self) { index in
                        let seed = Double(index) / Double(Self.count)
                        let span = proxy.size.height + 140
                        let speed = 70 + 50 * seed
                        let y = (time * speed + seed * span * 3).truncatingRemainder(dividingBy: span) - 70
                        Image(.tileBanana)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44 + 16 * seed)
                            .rotationEffect(.degrees(time * (40 + 60 * seed) + 90 * Double(index)))
                            .position(x: proxy.size.width * (0.08 + 0.84 * ((seed * 7).truncatingRemainder(dividingBy: 1))), y: y)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("J1") { ChimpEasterEggView(egg: .bananaMode) {} }
#Preview("J2") { ChimpEasterEggView(egg: .nightOwl) {} }
#Preview("J3") { ChimpEasterEggView(egg: .thousandaire) {} }
