import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: TuckStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Menu bar apps").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Rescan") { store.rescan() }
            }
            Text("Inline apps stay in the menu bar, left of Tuck's icon. Tucked apps live in Tuck's menu.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            ScrollView { AppList(store: store) }
            if let error = store.lastError {
                Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange)
            }
            Divider()
            Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 }))
            Text("Tip: hold ⌘ and drag Tuck's icon to choose where your inline icons end.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 460, height: 520)
        .onAppear { store.rescan() }
    }
}
