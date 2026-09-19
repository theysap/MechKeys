import SwiftUI

/// Three short screens: what this is, the one permission it needs, and done.
///
/// Nothing is configured here. The defaults are good, and the fastest way to
/// understand the app is to type with it running — not to answer questions
/// about a sound you have not heard yet.
public struct OnboardingView: View {

    let controller: MechKeysController

    public var onFinish: () -> Void

    @StateObject private var stepState = ViewState(Step.welcome)

    private var permissions: PermissionManager { controller.permissions }

    enum Step {
        case welcome, permission, ready
    }

    public init(controller: MechKeysController, onFinish: @escaping () -> Void = {}) {
        self.controller = controller
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            content
                .padding(.horizontal, 44)
            Spacer(minLength: 0)
        }
        .frame(width: 420, height: 380)
        .onChange(of: permissions.isTrusted) { _, trusted in
            // The moment permission lands, move on — the user is coming back
            // from System Settings and should not have to find the button.
            if trusted && stepState.value == .permission {
                withAnimation(.easeInOut(duration: 0.25)) { stepState.value = .ready }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stepState.value {
        case .welcome: welcome
        case .permission: permission
        case .ready: ready
        }
    }

    // MARK: - Screens

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)

            Text("MechKeys")
                .font(.system(size: 26, weight: .semibold))

            Text("Mechanical keyboard sounds for your Mac.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text("Choose a switch profile, adjust the dampening, and type.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button("Get Started") {
                withAnimation(.easeInOut(duration: 0.25)) {
                    stepState.value = permissions.isTrusted ? .ready : .permission
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
    }

    private var permission: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)

            Text("Keyboard Access Required")
                .font(.system(size: 19, weight: .semibold))

            Text("MechKeys needs macOS Accessibility permission to detect when keys are pressed.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(
                "Your keystrokes are never recorded, stored or transmitted. MechKeys only learns that *a* key was pressed and how large it was."
            )
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                Button("Open Accessibility Settings") {
                    controller.requestKeyboardAccess()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Text("Find MechKeys in the list and switch it on.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Button("Skip for now") {
                    withAnimation(.easeInOut(duration: 0.25)) { stepState.value = .ready }
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
            .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
    }

    private var ready: some View {
        VStack(spacing: 16) {
            Image(systemName: permissions.isTrusted ? "checkmark.circle" : "exclamationmark.circle")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(permissions.isTrusted ? Color.green : Color.orange)

            Text(permissions.isTrusted ? "You're ready." : "Almost there.")
                .font(.system(size: 21, weight: .semibold))

            Text(
                permissions.isTrusted
                    ? "Try typing anywhere. MechKeys lives in the menu bar — click the keyboard icon to change the switch or the dampening."
                    : "MechKeys will stay quiet until you grant Accessibility permission. You can do it any time from the menu bar."
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    controller.playTestSound()
                } label: {
                    Label("Hear It", systemImage: "play.circle")
                }
                .buttonStyle(.glass)
                .controlSize(.large)

                Button("Start MechKeys") {
                    controller.completeOnboarding()
                    controller.setEnabled(true)
                    onFinish()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
    }
}
