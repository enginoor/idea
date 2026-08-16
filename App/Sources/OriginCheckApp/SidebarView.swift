import SwiftUI

/// The classic macOS sidebar: a grouped list of destinations on top and the
/// Settings entry pinned at the bottom, just under the divider, the way
/// Finder and Mail arrange their footers.
struct SidebarView: View {
    @Binding var selection: AppSection?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Verify") {
                    ForEach(AppSection.allCases) { section in
                        Label(section.title, systemImage: section.icon)
                            .tag(section)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            SettingsLink {
                Label("Settings...", systemImage: "gearshape")
            }
            .labelStyle(.titleAndIcon)
            .font(.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
