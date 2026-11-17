import SwiftUI

/// The list of menu bar apps with an Inline / Tucked choice each, shared by onboarding and Settings.
struct AppList: View {
    @ObservedObject var store: TuckStore

    var body: some View {
        VStack(spacing: 0) {
            if store.apps.isEmpty {
                Text(store.trusted ? "No menu bar apps found yet." : "Allow Accessibility first so Tuck can see your menu bar.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
            ForEach(Array(store.apps.enumerated()), id: \.element.id) { index, app in
                if index > 0 { Divider().padding(.leading, 44) }
                row(app)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
    }

    private func row(_ app: MenuBarApp) -> some View {
        let tucked = store.isTucked(app.bundleID)
        return HStack(spacing: 10) {
            Image(nsImage: app.icon).resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.system(size: 13))
                if !tucked && !app.canStayVisible {
                    Text("Move it to /Applications, or macOS will hide it anyway")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Picker("", selection: Binding(get: { tucked }, set: { store.setTucked(app.bundleID, $0) })) {
                Text("Inline").tag(false)
                Text("Tucked").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
