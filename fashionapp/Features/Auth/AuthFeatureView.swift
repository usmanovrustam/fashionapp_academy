import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case signUp = "Create Account"

        var id: String { rawValue }
    }

    @Published var mode: Mode = .signIn
    @Published var email = ""
    @Published var password = ""
    @Published var displayName = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    private let auth: AuthServicing
    private let analytics: AnalyticsTracking

    init(auth: AuthServicing, analytics: AnalyticsTracking) {
        self.auth = auth
        self.analytics = analytics
    }

    var canSubmit: Bool {
        !isLoading && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    func submit() async {
        isLoading = true
        errorMessage = nil
        infoMessage = nil
        defer { isLoading = false }

        do {
            switch mode {
            case .signIn:
                let user = try await auth.signIn(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
                analytics.setUserID(user.id)
                analytics.track(.login, parameters: ["method": "password"])
            case .signUp:
                let user = try await auth.signUp(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                analytics.setUserID(user.id)
                analytics.track(.signUp, parameters: ["method": "password"])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func continueAsGuest() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let user = try await auth.signInAnonymously()
            analytics.setUserID(user.id)
            analytics.track(.login, parameters: ["method": "anonymous"])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetPassword() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter your email to reset your password."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await auth.sendPasswordReset(email: trimmed)
            infoMessage = "Password reset email sent."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Firebase-only auth screen — iOS 27 Liquid Glass, no iCloud / Sign in with Apple.
struct AuthFeatureView: View {
    @StateObject private var viewModel: AuthViewModel
    @Namespace private var glassNamespace

    init(auth: AuthServicing, analytics: AnalyticsTracking) {
        _viewModel = StateObject(wrappedValue: AuthViewModel(auth: auth, analytics: analytics))
    }

    var body: some View {
        ZStack {
            SoftBackground()

            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    header

                    SylyoGlassContainer(spacing: 16) {
                        VStack(spacing: 16) {
                            modePicker

                            if viewModel.mode == .signUp {
                                field("Name", text: $viewModel.displayName, contentType: .name)
                                    .sylyoGlassEffectID("auth-name", in: glassNamespace)
                            }

                            field(
                                "Email",
                                text: $viewModel.email,
                                contentType: .emailAddress,
                                keyboard: .emailAddress
                            )
                            .sylyoGlassEffectID("auth-email", in: glassNamespace)

                            SecureField("Password", text: $viewModel.password)
                                .textContentType(viewModel.mode == .signUp ? .newPassword : .password)
                                .padding()
                                .liquidGlass(cornerRadius: AppRadius.medium, interactive: true, tint: AppColors.brand)
                                .sylyoGlassEffectID("auth-password", in: glassNamespace)
                        }
                    }

                    statusMessages

                    SylyoGlassContainer(spacing: 12) {
                        VStack(spacing: 12) {
                            Button {
                                Task { await viewModel.submit() }
                            } label: {
                                HStack(spacing: 8) {
                                    if viewModel.isLoading {
                                        ProgressView().controlSize(.small)
                                    }
                                    Text(viewModel.mode == .signIn ? "Sign In" : "Create Account")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(LiquidGlassButtonStyle(
                                prominent: true,
                                tint: AppColors.brand,
                                isDisabled: !viewModel.canSubmit
                            ))
                            .disabled(!viewModel.canSubmit)
                            .sylyoGlassEffectID("auth-primary", in: glassNamespace)

                            if viewModel.mode == .signIn {
                                Button("Forgot password?") {
                                    Task { await viewModel.resetPassword() }
                                }
                                .buttonStyle(LiquidGlassButtonStyle(prominent: false, tint: AppColors.brand))
                                .disabled(viewModel.isLoading)
                                .sylyoGlassEffectID("auth-reset", in: glassNamespace)
                            }

                            Button {
                                Task { await viewModel.continueAsGuest() }
                            } label: {
                                Text("Continue as guest")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(LiquidGlassButtonStyle(
                                prominent: false,
                                tint: AppColors.brand,
                                isDisabled: viewModel.isLoading
                            ))
                            .disabled(viewModel.isLoading)
                            .sylyoGlassEffectID("auth-guest", in: glassNamespace)
                        }
                    }

                    Text("Signed-in wardrobe data syncs with Firebase Auth, Firestore, and Storage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(AppSpacing.xl)
            }
        }
        .onAppear {
            analyticsScreen()
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(AppColors.primaryGradient)
                .padding(26)
                .liquidGlass(cornerRadius: 36, tint: AppColors.brand)

            Text("Sylyo")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.primaryGradient)

            Text("Firebase sign-in for your AI wardrobe")
                .font(AppTypography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 28)
    }

    private var modePicker: some View {
        Picker("Mode", selection: $viewModel.mode) {
            ForEach(AuthViewModel.Mode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(6)
        .liquidGlass(cornerRadius: AppRadius.medium, tint: AppColors.brand)
    }

    @ViewBuilder
    private var statusMessages: some View {
        if let error = viewModel.errorMessage {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .liquidGlass(cornerRadius: AppRadius.medium, tint: .red)
        }

        if let info = viewModel.infoMessage {
            Text(info)
                .font(.footnote)
                .foregroundStyle(.green)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .liquidGlass(cornerRadius: AppRadius.medium, tint: .green)
        }
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        contentType: UITextContentType,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        TextField(title, text: text)
            .textContentType(contentType)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding()
            .liquidGlass(cornerRadius: AppRadius.medium, interactive: true, tint: AppColors.brand)
    }

    private func analyticsScreen() {
        // RootView also tracks transitions; keep auth screen lightweight.
    }
}
