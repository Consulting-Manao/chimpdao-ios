import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: ChimpSpacing.sectionGap) {
                Text("ChimpDAO")
                    .chimpFont(.displayL)
                #if DESIGN_CATALOG
                NavigationLink {
                    DesignSystemCatalogView()
                } label: {
                    Text("Design System")
                        .chimpFont(.link)
                        .frame(minHeight: ChimpSize.minimumTouchTarget)
                }
                #endif
            }
            .foregroundStyle(.chimpTextPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.chimpBackground))
        }
    }
}

#Preview {
    HomeView()
}
