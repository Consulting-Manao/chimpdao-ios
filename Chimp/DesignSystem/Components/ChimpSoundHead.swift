import SwiftUI

/// Tête de Chimpy du réglage « Sounds » (I2, demande de Barth du 2026-10-02) : le singe joyeux quand les sons sont
/// activés, le singe qui fait « chut » quand ils sont coupés. La tête seule, sans fond ni contour (retour de Barth).
/// Au changement, elle rebondit en changeant d'image ; avec « Réduire les animations », un fondu.
/// Décorative : la ligne qui la contient porte le libellé et l'état pour VoiceOver.
struct ChimpSoundHead: View {
    let isOn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Image(isOn ? .chimpySoundOn : .chimpySoundOff)
                .resizable()
                .scaledToFit()
                .frame(width: ChimpSize.soundHead, height: ChimpSize.soundHead)
                // Une vue par état : l'ancienne tête s'en va, la nouvelle arrive.
                .id(isOn)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
        }
        .frame(width: ChimpSize.soundHead, height: ChimpSize.soundHead)
        .animation(reduceMotion ? .easeInOut(duration: ChimpMotion.Micro.fade) : ChimpMotion.Micro.pop, value: isOn)
        .accessibilityHidden(true)
    }
}

private struct ChimpSoundHeadPreview: View {
    @State private var isOn = true

    var body: some View {
        Button { isOn.toggle() } label: { ChimpSoundHead(isOn: isOn) }
            .buttonStyle(ChimpBouncyPressStyle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.chimpBackground))
    }
}

#Preview("Clair") {
    ChimpSoundHeadPreview()
}

#Preview("Sombre") {
    ChimpSoundHeadPreview()
        .preferredColorScheme(.dark)
}
