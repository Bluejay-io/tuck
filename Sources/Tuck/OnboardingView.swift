import AppKit
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, access, choose, ready
}

struct OnboardingView: View {
    @ObservedObject var store: TuckStore
    let finish: () -> Void
    @AppStorage("onboardingStep") private var stepRaw = 0

    private var step: OnboardingStep { OnboardingStep(rawValue: stepRaw) ?? .welcome }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Group {
                switch step {
                case .welcome: WelcomePage()
                case .access: AccessPage(store: store, advance: advance)
                case .choose: ChoosePage(store: store)
                case .ready: ReadyPage()
                }
            }
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 24)), removal: .opacity.combined(with: .offset(x: -24))))
            .id(step)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if step != .welcome {
                    Button("Back") { stepRaw -= 1 }.controlSize(.large)
                }
                Button(primaryTitle) {
                    if step == .ready { finish() } else { advance() }
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(step == .access && !store.trusted)
            }
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item == step ? Color.primary : Color.primary.opacity(0.15))
                        .frame(width: item == step ? 16 : 6, height: 6)
                }
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 48)
        .padding(.top, 40)
        .padding(.bottom, 24)
        .frame(width: 560, height: 520)
        .background(.background)
        .animation(.spring(duration: 0.45), value: stepRaw)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Get started"
        case .ready: return "Done"
        default: return "Continue"
        }
    }

    private func advance() {
        stepRaw = min(stepRaw + 1, OnboardingStep.ready.rawValue)
    }
}

private struct Header: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 440)
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Header(title: "Welcome to Tuck",
                   subtitle: "Keep the menu bar icons you use, and tuck the rest into one tidy menu. Nothing moves until you say so.")
        }
    }
}

private struct AccessPage: View {
    @ObservedObject var store: TuckStore
    let advance: () -> Void
    @State private var asked = false
    @State private var advanced = false

    var body: some View {
        VStack(spacing: 22) {
            Header(title: "Let Tuck see your menu bar",
                   subtitle: "Tuck needs \(PermissionGuide.listName) access to list your menu bar icons, hide the ones you tuck, and open them from its menu.")
            HStack(spacing: 12) {
                Image(systemName: "hand.raised").font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(PermissionGuide.listName).font(.system(size: 13, weight: .medium))
                    Text(store.trusted ? "Allowed" : "Drag Tuck into the list, then switch it on")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if store.trusted {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Button("Allow") {
                        asked = true
                        PermissionGuide.shared.show()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .frame(width: 440)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
            if asked && !store.trusted {
                Button("Switched on but still not allowed? Fix it") { PermissionGuide.shared.fix() }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
        }
        .animation(.spring(duration: 0.35), value: store.trusted)
        .onChange(of: store.trusted) { _, trusted in
            guard trusted, asked, !advanced else { return }
            advanced = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { advance() }
        }
    }
}

private struct ChoosePage: View {
    @ObservedObject var store: TuckStore

    var body: some View {
        VStack(spacing: 18) {
            Header(title: "Choose what to tuck",
                   subtitle: "Inline icons stay in the menu bar. Tucked ones move into Tuck's menu. You can change this any time.")
            ScrollView { AppList(store: store) }
                .frame(width: 440, height: 230)
        }
        .onAppear { store.rescan() }
    }
}

private struct ReadyPage: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "command")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Header(title: "Put Tuck where your icons end",
                   subtitle: "Hold ⌘ and drag Tuck's icon in the menu bar to the right, next to the clock. Your inline icons sit to its left, and everything tucked is one click away.")
        }
    }
}
