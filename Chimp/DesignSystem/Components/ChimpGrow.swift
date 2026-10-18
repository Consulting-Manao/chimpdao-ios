import SwiftUI

/// Composants de l'onglet Grow (maquette « Chimp Grow Final », Claude Design, 2026-10-18 ; `design/GROW_HANDOFF.md`).
/// Un « pot » par protocole : DeFindex (XLM), XOXNO (USDC), Etherfuse (CETES).

/// Le protocole d'un pot, tel que l'écran le dessine : logo et nom.
enum ChimpPotProtocol: String, CaseIterable, Identifiable, Hashable, Sendable {
    case defindex
    case xoxno
    case etherfuse

    var id: String { rawValue }

    var name: String {
        switch self {
        case .defindex: "DeFindex"
        case .xoxno: "XOXNO"
        case .etherfuse: "Etherfuse"
        }
    }

    var logo: ImageResource {
        switch self {
        case .defindex: .protocolDefindex
        case .xoxno: .protocolXoxno
        case .etherfuse: .protocolEtherfuse
        }
    }
}

/// Logo d'un protocole dans sa tuile : coins arrondis à 28 % de la taille, contour encre.
struct ChimpProtocolLogo: View {
    let mark: ChimpPotProtocol
    var size: CGFloat = 48
    var border: CGFloat = ChimpBorder.regular

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Image(mark.logo)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color(.chimpOutline), lineWidth: border) }
            .accessibilityHidden(true)
    }
}

/// « +0.12 XLM » dans sa pastille verte (rouge si la valeur a baissé).
struct ChimpGrowthChip: View {
    let text: String
    var isNegative = false

    var body: some View {
        Text(verbatim: text)
            .chimpFont(.chip)
            .lineLimit(1)
            .foregroundStyle(isNegative ? Color(.chimpTicketPaper) : Color(.chimpTicketInk))
            .padding(.horizontal, 9)
            .padding(.vertical, 2)
            .background(Capsule().fill(isNegative ? Color(.chimpNegative) : Color(.chimpCardLeaf)))
            .overlay { Capsule().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin) }
    }
}

/// G1 · une carte de pot : logo, nom, sous-titre, montant et pastille de croissance.
struct ChimpPotCard<Trailing: View>: View {
    let mark: ChimpPotProtocol
    let subtitle: String
    var compact = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            ChimpProtocolLogo(mark: mark, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: mark.name).chimpFont(.potName).foregroundStyle(.chimpTextPrimary).lineLimit(1)
                Text(verbatim: subtitle).chimpFont(.captionStrong).foregroundStyle(.chimpTextSecondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, compact ? 10 : 13)
        .padding(.horizontal, compact ? 14 : 15)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface), shadow: .card)
        .accessibilityElement(children: .combine)
    }
}

/// Le côté droit d'une carte de pot : montant, puis pastille.
struct ChimpPotAmount: View {
    let amount: String
    var chip: String?
    var isNegative = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(verbatim: amount).chimpFont(.potAmount).foregroundStyle(.chimpTextPrimary).lineLimit(1).minimumScaleFactor(0.6)
            if let chip { ChimpGrowthChip(text: chip, isNegative: isNegative) }
        }
    }
}

/// G1 · « Plant something else » : bord en pointillés, logos qui se chevauchent, liste des protocoles, bouton « + ».
struct ChimpPlantSomethingElse: View {
    let marks: [ChimpPotProtocol]

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: -10) {
                ForEach(marks) { ChimpProtocolLogo(mark: $0, size: 32) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Plant something else").chimpFont(.button).foregroundStyle(.chimpTextPrimary).lineLimit(1)
                Text(verbatim: marks.map(\.name).joined(separator: " · ")).chimpFont(.captionStrong).foregroundStyle(.chimpTextSecondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ChimpPlusDisc()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background {
            RoundedRectangle(cornerRadius: ChimpRadius.panel)
                .strokeBorder(Color(.chimpTextSecondary), style: StrokeStyle(lineWidth: ChimpBorder.regular, dash: [7, 5]))
        }
        .contentShape(RoundedRectangle(cornerRadius: ChimpRadius.panel))
        .accessibilityElement(children: .combine)
    }
}

/// Le disque jaune et son « + » (deux barres arrondies).
struct ChimpPlusDisc: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).frame(width: 20, height: 5)
            RoundedRectangle(cornerRadius: 3).frame(width: 5, height: 20)
        }
        .foregroundStyle(Color(.chimpTicketInk))
        .frame(width: 42, height: 42)
        .cartoonSurface(Circle(), fill: Color(.chimpAccent), shadow: ChimpShadow(x: 0, y: 3))
        .accessibilityHidden(true)
    }
}

/// G1 · une pastille de tiroir (« All drawers », « Main », « Jungle »…).
struct ChimpDrawerPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .chimpFont(.pill)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color(.chimpTicketInk) : Color(.chimpTextPrimary))
                .padding(.horizontal, 13)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .cartoonSurface(Capsule(), fill: isSelected ? Color(.chimpAccent) : Color(.chimpSurface))
        }
        .buttonStyle(ChimpPressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Le ticket papier (G2, G3r) : papier, contour encre, coins du haut arrondis, bord du bas déchiré en zigzag, légèrement
/// tourné, ombre portée douce.
struct ChimpPaperReceipt<Content: View>: View {
    var padding = EdgeInsets(top: 18, leading: 18, bottom: 14, trailing: 18)
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .foregroundStyle(Color(.chimpTicketInk))
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.chimpTicketPaper))
                .overlay { ReceiptOutline().stroke(Color(.chimpTicketInk), lineWidth: ChimpBorder.regular) }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
            ChimpZigzagEdge()
                .fill(Color(.chimpTicketPaper))
                .frame(height: 12)
        }
        .rotationEffect(.degrees(-0.6))
        .shadow(color: Color(.chimpTicketInk).opacity(0.28), radius: 0, x: 4, y: 5)
    }
}

/// Contour du ticket : côtés et haut arrondi, rien en bas (le zigzag prend le relais).
private struct ReceiptOutline: Shape {
    var radius: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let inset = ChimpBorder.regular / 2
        let r = rect.insetBy(dx: inset, dy: 0)
        let top = rect.minY + inset
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: top + radius))
        path.addArc(center: CGPoint(x: r.minX + radius, y: top + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: r.maxX - radius, y: top))
        path.addArc(center: CGPoint(x: r.maxX - radius, y: top + radius), radius: radius, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: r.maxX, y: rect.maxY))
        return path
    }
}

/// Bord déchiré du ticket : triangles de 14 pt.
struct ChimpZigzagEdge: Shape {
    var tooth: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        var x = rect.minX
        while x < rect.maxX {
            let mid = min(x + tooth / 2, rect.maxX)
            let end = min(x + tooth, rect.maxX)
            path.addLine(to: CGPoint(x: mid, y: rect.maxY))
            path.addLine(to: CGPoint(x: end, y: rect.minY))
            x = end
        }
        path.closeSubpath()
        return path
    }
}

/// Trait en pointillés du ticket.
struct ChimpReceiptRule: View {
    var body: some View {
        Line()
            .stroke(Color(.chimpTicketRule), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            .frame(height: 2)
            .padding(.horizontal, -4)
            .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: rect.minX, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}

/// Une ligne du ticket : libellé à gauche (atténué), valeur à droite.
struct ChimpReceiptRow: View {
    let label: LocalizedStringKey
    let value: String
    var tone: Tone = .plain

    enum Tone { case plain, positive, negative }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).textCase(.uppercase).foregroundStyle(Color(.chimpTicketMuted))
            Spacer(minLength: 0)
            Text(verbatim: value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(tone == .positive ? Color(.chimpPositive) : tone == .negative ? Color(.chimpNegative) : Color(.chimpTicketInk))
        }
        .chimpFont(.potRow)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

/// Tampon du ticket d'un pot (« GROWING », « TESTNET PRICES »), légèrement de travers.
struct ChimpPotStamp: View {
    let text: LocalizedStringKey
    var color: Color = Color(.chimpPositive)

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .chimpFont(.potStamp)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 3)
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(color, lineWidth: 3.5) }
            .rotationEffect(.degrees(-5))
    }
}

/// G2 · la courbe sous l'en-tête vert : la ligne des valeurs relevées (de la plus ancienne à aujourd'hui), la zone
/// dessous au fond de la page (l'en-tête « fond » dans la page), la date de départ, le point jaune « TODAY » et le logo du
/// protocole au milieu. `values` : au moins deux valeurs ; une seule valeur donne une ligne plate.
struct ChimpGrowCurve: View {
    let values: [Double]
    let startLabel: String
    let mark: ChimpPotProtocol

    /// Les points, en coordonnées 0…1 (y vers le bas), entre 85 % (plus bas) et 10 % (plus haut) de la hauteur.
    static func points(_ values: [Double]) -> [CGPoint] {
        let series = values.count >= 2 ? values : [values.first ?? 0, values.first ?? 0]
        let low = series.min() ?? 0, high = series.max() ?? 0
        let span = high - low
        return series.enumerated().map { index, value in
            let x = Double(index) / Double(series.count - 1)
            let level = span > 0 ? (value - low) / span : 0.5
            return CGPoint(x: x, y: 0.85 - level * 0.75)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let points = Self.points(values).map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            ZStack(alignment: .topLeading) {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: 0, y: size.height))
                    path.addLine(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.closeSubpath()
                }
                .fill(Color(.chimpBackground))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(Color(.chimpTicketInk), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                Text(verbatim: startLabel)
                    .chimpFont(.curveLabel)
                    .foregroundStyle(Color(.chimpTicketInk))
                    .position(x: 14 + 30, y: size.height * 0.62 + 6)
                if let last = points.last {
                    Circle()
                        .fill(Color(.chimpAccent))
                        .overlay { Circle().strokeBorder(Color(.chimpTicketInk), lineWidth: ChimpBorder.regular) }
                        .frame(width: 18, height: 18)
                        .position(x: size.width - 19, y: last.y)
                    Text("Today")
                        .textCase(.uppercase)
                        .chimpFont(.curveLabel)
                        .foregroundStyle(Color(.chimpTicketInk))
                        .position(x: size.width - 30, y: last.y + 22)
                }
                ChimpProtocolLogo(mark: mark, size: 82)
                    .background { RoundedRectangle(cornerRadius: 24).fill(Color(.chimpTicketInk)).offset(x: 4, y: 5) }
                    .rotationEffect(.degrees(-6))
                    .position(x: size.width / 2, y: size.height * 0.61)
            }
        }
        .accessibilityHidden(true)
    }
}

/// G3, G5 · les raccourcis de montant (« 10 », « 50 », « Max »).
struct ChimpQuickPick: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .chimpFont(.pill)
                .foregroundStyle(isSelected ? Color(.chimpTicketInk) : Color(.chimpTextPrimary))
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .cartoonSurface(Capsule(), fill: isSelected ? Color(.chimpAccent) : Color(.chimpSurface))
        }
        .buttonStyle(ChimpPressableStyle())
    }
}

/// G5 · note dans l'écran du montant (pas un écran d'erreur) : fond jaune pâle, tête de Chimpy.
struct ChimpGrowNote: View {
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(.tileHead).resizable().scaledToFit().frame(width: 26).accessibilityHidden(true)
            Text(text).chimpFont(.captionStrong).foregroundStyle(Color(.chimpTicketInk)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .frame(maxWidth: 330, alignment: .leading)
        .cartoonSurface(RoundedRectangle(cornerRadius: 16), fill: Color(.chimpGrowNote))
        .accessibilityElement(children: .combine)
    }
}

/// Le pied de page des écrans Grow.
struct ChimpGrowFinePrint: View {
    var body: some View {
        Text("Not guaranteed · Not advice · You keep control of your money")
            .chimpFont(.captionS)
            .fontWeight(.heavy)
            .foregroundStyle(.chimpTextSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}
