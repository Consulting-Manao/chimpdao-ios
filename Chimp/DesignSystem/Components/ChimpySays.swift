import SwiftUI

/// Pose de Chimpy.
enum ChimpyPose: String, CaseIterable, Identifiable {
    case crawl
    case banana
    case stand
    case hamac
    case head
    // Chimpy v2 (2026-10-02) : une pose par humeur.
    case wave        // salut, clin d'œil : accueil
    case armsCrossed // bras croisés, sûr de lui : ce qu'il faut savoir
    case teacher     // professeur : visite, conseils
    case plant       // plante une pousse : tiroir vide
    case stop        // nez bouché, main tendue : action refusée
    case stick       // bâton et banane pourrie : adresse ou code refusé
    case peel        // peau de banane : rien n'est parti
    case unsure      // hésite entre deux bananes : choix d'un tiroir ou d'un compte
    case sniff       // caleçon, odeur de banane : carte toute neuve

    var id: String { rawValue }

    var image: ImageResource {
        switch self {
        case .crawl: .chimpyCrawl
        case .banana: .chimpyBanana
        case .stand: .chimpyStand
        case .hamac: .chimpyHamac
        case .head: .tileHead
        case .wave: .chimpyWave
        case .armsCrossed: .chimpyArmsCrossed
        case .teacher: .chimpyTeacher
        case .plant: .chimpyPlant
        case .stop: .chimpyStop
        case .stick: .chimpyStick
        case .peel: .chimpyPeel
        case .unsure: .chimpyUnsure
        case .sniff: .chimpySniff
        }
    }
}

/// Bulle de Chimpy (« Chimpy Says ») : Chimpy explique une règle au moment où elle compte.
/// L'image est décorative ; VoiceOver lit « Chimpy » puis le texte.
struct ChimpySays: View {
    private let text: Text
    var pose: ChimpyPose = .crawl

    init(text: LocalizedStringKey, pose: ChimpyPose = .crawl) {
        self.text = Text(text)
        self.pose = pose
    }

    /// Texte tiré d'une liste (`ChimpyLines`) : une ressource du String Catalog.
    init(line: LocalizedStringResource, pose: ChimpyPose = .crawl) {
        self.text = Text(line)
        self.pose = pose
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: ChimpSpacing.s) {
            bubble
            Image(pose.image)
                .resizable()
                .scaledToFit()
                .frame(width: ChimpSize.chimpyThumbnail)
                .frame(maxHeight: ChimpSize.chimpyThumbnailMaxHeight, alignment: .bottom)
                .accessibilityHidden(true)
        }
    }

    private var bubble: some View {
        // Coin bas-droit presque carré : la bulle « pointe » vers Chimpy.
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: ChimpRadius.control,
            bottomLeadingRadius: ChimpRadius.control,
            bottomTrailingRadius: 4,
            topTrailingRadius: ChimpRadius.control
        )
        return VStack(alignment: .leading, spacing: 2) {
            Text("Chimpy")
                .chimpFont(.labelS)
                .textCase(.uppercase)
                .foregroundStyle(.chimpTextSecondary)
            text
                .chimpFont(.bodyS)
                .lineSpacing(4)
                .foregroundStyle(.chimpTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 10 + ChimpBorder.regular)
        .padding(.horizontal, ChimpSpacing.ml + ChimpBorder.regular)
        .padding(.bottom, ChimpSpacing.m + ChimpBorder.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartoonSurface(shape, fill: Color(.chimpSurface), shadow: .tile)
        .accessibilityElement(children: .combine)
    }
}

private struct ChimpySaysPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: ChimpSpacing.xl) {
                ForEach(ChimpyPose.allCases) { pose in
                    ChimpySays(text: "Looking is free. Moving money takes a tap.", pose: pose)
                }
            }
            .padding(ChimpSpacing.screenMargin)
        }
        .background(Color(.chimpBackground))
    }
}

#Preview("Light") {
    ChimpySaysPreview()
}

#Preview("Dark") {
    ChimpySaysPreview()
        .preferredColorScheme(.dark)
}
