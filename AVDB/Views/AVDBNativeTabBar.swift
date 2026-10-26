import SwiftUI

// Six peer native buttons, never UIKit's five-item More overflow. Visited roots
// remain mounted so navigation paths and scroll positions survive tab changes.
struct AVDBNativeTabBar: View {
    @Binding var selection: AppTab
    private var buttons: some View {
        HStack(spacing:0) {
            ForEach(AppTab.allCases) { tab in
                Button { selection = tab } label: {
                    VStack(spacing:3) {
                        Image(systemName:tab.icon).font(.system(size:19,weight:selection == tab ? .semibold : .regular))
                        Text(tab.title).font(.system(size:10,weight:selection == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                    .frame(maxWidth:.infinity,minHeight:52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("app.tab.\(tab.rawValue)")
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
            }
        }.padding(.horizontal,6)
    }
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                buttons.glassEffect(.regular, in: .rect(cornerRadius:28))
            } else {
                buttons.background(.regularMaterial,in:RoundedRectangle(cornerRadius:28))
            }
        }.padding(.horizontal,8).padding(.top,6).padding(.bottom,2)
    }
}
