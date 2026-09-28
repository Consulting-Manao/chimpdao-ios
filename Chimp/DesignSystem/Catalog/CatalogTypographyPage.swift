#if DESIGN_CATALOG
import SwiftUI

struct CatalogTypographyPage: View {
    let settings: CatalogSettings

    var body: some View {
        CatalogPage("Typography", settings: settings) {
            Text("Sizes follow the text size set in iOS (Dynamic Type). Luckiest Guy styles stop growing at XXXL.")
                .chimpFont(.body)
                .foregroundStyle(.chimpTextSecondary)
            ForEach(ChimpTextStyle.allCases) { style in
                CatalogTypographyRow(style: style)
            }
        }
    }
}

private struct CatalogTypographyRow: View {
    let style: ChimpTextStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
            sample
                .chimpFont(style)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: style.rawValue)
                .chimpFont(.rowTitle)
            Text(verbatim: specification)
                .chimpFont(.mono)
                .foregroundStyle(.chimpTextSecondary)
        }
        .padding(ChimpSpacing.ml)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))
        .accessibilityElement(children: .combine)
    }

    /// « Luckiest Guy · 23 pt · title2 · max XXXL → 23.0 pt »
    private var specification: String {
        var parts = [style.family.displayName, "\(Int(style.size)) pt", Self.name(of: style.relativeTo)]
        if style.tracking > 0 { parts.append("tracking \(style.tracking)") }
        if style.maximumDynamicTypeSize != nil { parts.append("max XXXL") }
        return parts.joined(separator: " · ") + String(format: " → %.1f pt", style.pointSize(for: dynamicTypeSize))
    }

    private static func name(of textStyle: UIFont.TextStyle) -> String {
        switch textStyle {
        case .largeTitle: "largeTitle"
        case .title1: "title"
        case .title2: "title2"
        case .title3: "title3"
        case .headline: "headline"
        case .callout: "callout"
        case .subheadline: "subheadline"
        case .footnote: "footnote"
        case .caption1: "caption"
        case .caption2: "caption2"
        default: "body"
        }
    }

    @ViewBuilder
    private var sample: some View {
        switch style {
        case .celebration: Text("Swoosh!")
        case .displayXL: Text(verbatim: "$1,284.50")
        case .amountL: Text(verbatim: "$820.00")
        case .amountM: Text(verbatim: "$1,320.00")
        case .greeting: Text(verbatim: "Hey Léo")
        case .pill: Text("+ Add")
        case .displayL: Text("Wrong banana!")
        case .sheetTitle: Text("Hold your Jungle card to your phone")
        case .key: Text(verbatim: "1 2 3")
        case .displayM: Text("Send")
        case .amountS: Text(verbatim: "$62.50")
        case .displayS: Text("Your cards")
        case .buttonLarge: Text("Let's start")
        case .button: Text("Looks good")
        case .buttonSecondary: Text("No, stop")
        case .tab: Text("Wallet")
        case .link: Text("Cancel")
        case .buttonSmall: Text("+ Add")
        case .cardName: Text(verbatim: "Jungle")
        case .tile: Text("Receive")
        case .bodyL: Text("Nothing is moved yet. I'm just saying hello.")
        case .rowTitle: Text("Main account")
        case .optionTitle: Text("Jungle's wallet")
        case .body, .bodyS: Text("Looking is free. Moving money takes a tap.")
        case .caption: Text("$820 ready · $500 growing")
        case .captionS: Text("12:15 · into Main")
        case .captionStrong: Text("on card")
        case .labelWide: Text("Step 2 of 3").textCase(.uppercase)
        case .label: Text("Ready to spend").textCase(.uppercase)
        case .labelS: Text(verbatim: "CHIMPY")
        case .cardNumber: Text(verbatim: "N°0421")
        case .monoValue: Text(verbatim: "820.00 USDC")
        case .mono: Text(verbatim: "AAAAAgAAAACHm2nUx0FH")
        case .address: Text(verbatim: "CAIO2SJ6…AZVOX2")
        }
    }
}

#Preview {
    NavigationStack {
        CatalogTypographyPage(settings: CatalogSettings())
    }
}
#endif
