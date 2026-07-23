import SwiftUI
import BandPilotKit

/// Combined sign-in / register screen (mirrors the Android AuthScreen). Blue actions here rather
/// than the pink brand accent — a field/button you're just signing in with reads oddly in red.
struct AuthView: View {
    @State private var vm: AuthViewModel
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showForgotSheet = false
    @State private var forgotEmail = ""

    init(session: SessionStore, api: APIClient) {
        _vm = State(wrappedValue: AuthViewModel(api: api, session: session))
    }

    private var registerMode: Bool { vm.mode == .register }

    private var passwordTooShort: Bool {
        registerMode && !password.isEmpty && password.count < 8
    }

    private var formValid: Bool {
        guard email.contains("@") else { return false }
        if registerMode {
            return password.count >= 8 && !firstName.isEmpty && !lastName.isEmpty
        }
        return !password.isEmpty
    }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 32)
                    Image("BandPilotBanner")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 420)

                    Text(registerMode ? "Create your account" : "Sign in to your bands")
                        .foregroundStyle(Palette.textDim)

                    SectionCard {
                        if let error = vm.error { ErrorBanner(message: error) }
                        if let info = vm.info { InfoBanner(message: info) }

                        if registerMode {
                            HStack(spacing: 10) {
                                LabeledField(label: "First name", text: $firstName, autocapitalization: .words)
                                LabeledField(label: "Last name", text: $lastName, autocapitalization: .words)
                            }
                        }
                        LabeledField(label: "Email", text: $email, keyboard: .emailAddress)
                        LabeledField(label: "Password", text: $password, isSecure: true)

                        if passwordTooShort {
                            Text("Password needs at least 8 characters.")
                                .font(.footnote)
                                .foregroundStyle(Palette.danger)
                        }

                        HStack {
                            Spacer()
                            PrimaryButton(
                                title: vm.busy ? "Please wait…" : (registerMode ? "Register" : "Sign in"),
                                enabled: formValid,
                                busy: vm.busy,
                                fill: AnyShapeStyle(Palette.selected)
                            ) {
                                Task { await submit() }
                            }
                        }

                        Button {
                            vm.toggleMode()
                        } label: {
                            Text(registerMode ? "Already have an account? Sign in" : "No account yet? Register")
                                .foregroundStyle(Palette.selected)
                        }

                        if !registerMode {
                            Button {
                                forgotEmail = email
                                vm.error = nil
                                vm.info = nil
                                showForgotSheet = true
                            } label: {
                                Text("Forgot password?")
                                    .foregroundStyle(Palette.selected)
                            }
                        }
                    }
                    .frame(maxWidth: 420)
                    Spacer(minLength: 24)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            #if DEBUG
            // Dev-only convenience so the authenticated screens can be driven on the simulator
            // (headless UI typing is impractical). Never compiled into release builds.
            let env = ProcessInfo.processInfo.environment
            if let e = env["BP_AUTOLOGIN_EMAIL"], let p = env["BP_AUTOLOGIN_PASSWORD"], !vm.busy {
                email = e; password = p
                await vm.login(email: e, password: p)
            }
            #endif
        }
        .sheet(isPresented: $showForgotSheet) {
            ForgotPasswordSheet(vm: vm, email: $forgotEmail, isPresented: $showForgotSheet)
        }
    }

    private func submit() async {
        if registerMode {
            await vm.register(firstName: firstName, lastName: lastName, email: email, password: password)
            if vm.mode == .login { password = "" } // registration succeeded → switched to login
        } else {
            await vm.login(email: email, password: password)
        }
    }
}

/// Email-entry sheet for requesting a password reset. The reset itself happens on the web.
private struct ForgotPasswordSheet: View {
    @Bindable var vm: AuthViewModel
    @Binding var email: String
    @Binding var isPresented: Bool

    private var emailValid: Bool { email.contains("@") }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Enter your account email. We'll send a link to reset your password; open it to choose a new one.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LabeledField(label: "Email", text: $email, keyboard: .emailAddress)
                    PrimaryButton(
                        title: vm.busy ? "Please wait…" : "Send reset link",
                        enabled: emailValid,
                        busy: vm.busy,
                        fill: AnyShapeStyle(Palette.selected)
                    ) {
                        Task {
                            await vm.forgotPassword(email: email)
                            if vm.error == nil { isPresented = false }
                        }
                    }
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}
