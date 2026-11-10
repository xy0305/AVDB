import SwiftUI

// Seven peer native buttons, never UIKit's five-item More overflow. Visited roots
// remain mounted so navigation paths and scroll positions survive tab changes.
// Build 325: dark warm glass bar (home glass recipe + shadow), selected item in the
// single accent #FF8A3D with a subtle white-12% capsule, unselected white 55%. The bar is
// always dark, so it stays legible over the light tabs too (a little more opaque there).
struct AVDBNativeTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private static let accent = Color(red: 1.0, green: 138.0 / 255.0, blue: 61.0 / 255.0)   // #FF8A3D
    private static let warm = Color(red: 20.0 / 255.0, green: 16.0 / 255.0, blue: 13.0 / 255.0) // #14100D

    private var buttons: some View {
        HStack(spacing:0) {
            ForEach(AppTab.allCases) { tab in
                let selected = selection == tab
                Button { selection = tab } label: {
                    VStack(spacing:3) {
                        Image(systemName:tab.icon).font(.system(size:19,weight:selected ? .semibold : .regular))
                        Text(tab.title).font(.system(size:10,weight:selected ? .semibold : .regular))
                    }
                    .foregroundStyle(selected ? Self.accent : Color.white.opacity(0.55))
                    .frame(maxWidth:.infinity,minHeight:52)
                    .background {
                        if selected {
                            Capsule().fill(Color.white.opacity(0.12)).padding(.vertical,4)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("app.tab.\(tab.rawValue)")
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }.padding(.horizontal,6)
    }

    /// The bar stays the same dark warm glass on every tab. Build 325 used 0.32
    /// over a dark home; Build 328's light home makes that fill unreadable
    /// (white 55% labels on a mostly-transparent bar over systemBackground),
    /// so home uses the existing non-home 0.66 fill. Nothing else changes.
    private var fillOpacity: Double {
        reduceTransparency ? 1 : 0.66
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius:28, style:.continuous)
        buttons
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Self.warm.opacity(fillOpacity))
                    shape.fill(Self.accent.opacity(0.10))
                }
                .environment(\.colorScheme, .dark)
                .shadow(color:.black.opacity(0.35), radius:16, y:6)
            }
            .overlay { shape.strokeBorder(Color.white.opacity(0.16), lineWidth:0.5) }
            .environment(\.colorScheme, .dark)
            .animation(.easeInOut(duration:0.22), value: selection)
            .padding(.horizontal,8).padding(.top,6).padding(.bottom,2)
    }
}
