#if DESIGN_CATALOG
import SwiftUI

/// Bulle de Chimpy dans ses 5 poses, flottement et anneaux NFC.
struct CatalogChimpyPage: View {
    let settings: CatalogSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CatalogPage("Chimpy and motion", settings: settings) {
            HStack {
                Text("Reduce Motion").chimpFont(.rowTitle)
                Spacer()
                Text(reduceMotion ? "On" : "Off").chimpFont(.monoValue).foregroundStyle(.chimpTextSecondary)
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                CatalogSectionTitle("Chimpy says")
                ForEach(ChimpyPose.allCases) { pose in
                    VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                        Text(verbatim: pose.rawValue).chimpFont(.captionS).foregroundStyle(.chimpTextSecondary)
                        ChimpySays(text: "Looking is free. Moving money takes a tap.", pose: pose)
                    }
                }
                ChimpySays(
                    text: "You'll type it each time the card signs. I don't keep a copy, so pick one you won't forget.",
                    pose: .banana
                )
            }

            VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                CatalogSectionTitle("Bob")
                HStack(alignment: .bottom, spacing: ChimpSpacing.xl) {
                    bobSample(duration: 4.5, label: "4.5 s")
                    bobSample(duration: 3, label: "3 s")
                    bobSample(duration: 1.2, label: "1.2 s")
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                CatalogSectionTitle("NFC rings · sheet")
                ChimpNFCRings {
                    ChimpCardThumbnail(color: .jungle)
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                CatalogSectionTitle("NFC rings · full screen")
                ChimpNFCRings(config: ChimpMotion.Ring.fullScreen, size: 240) {
                    Image(.tileHead).resizable().scaledToFit().frame(width: 130)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, ChimpSpacing.xl)
                .background {
                    Color(.chimpHeader)
                        .overlay { ChimpPattern() }
                        .clipShape(RoundedRectangle(cornerRadius: ChimpRadius.control))
                }
            }
        }
    }

    private func bobSample(duration: Double, label: String) -> some View {
        VStack(spacing: ChimpSpacing.s) {
            Image(.chimpyBanana)
                .resizable()
                .scaledToFit()
                .frame(height: 90)
                .chimpBob(duration: duration)
                .accessibilityHidden(true)
            Text(verbatim: label).chimpFont(.mono)
        }
    }
}

#Preview {
    NavigationStack {
        CatalogChimpyPage(settings: CatalogSettings())
    }
}
#endif
