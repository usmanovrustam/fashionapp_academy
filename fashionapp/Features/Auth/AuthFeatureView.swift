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

    var isFirebaseConfigured: Bool { auth.isFirebaseConfigured }

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

struct AuthFeatureView: View {
    @StateObject private var viewModel: AuthViewModel

    init(auth: AuthServicing, analytics: AnalyticsTracking) {
        _viewModel = StateObject(wrappedValue: AuthViewModel(auth: auth, analytics: analytics))
    }

    var body: some View {
        ZStack {
            SoftBackground()

            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    header

                    Picker("Mode", selection: $viewModel.mode) {
                        ForEach(AuthViewModel.Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    GlassEffectContainer(spacing: 14) {
                        VStack(spacing: 14) {
                            if viewModel.mode == .signUp {
                                field("Name", text: $viewModel.displayName, contentType: .name)
                            }
                            field("Email", text: $viewModel.email, contentType: .emailAddress, keyboard: .emailAddress)
                            SecureField("Password", text: $viewModel.password)
                                .textContentType(viewModel.mode == .signUp ? .newPassword : .password)
                                .padding()
                                .liquidGlass(cornerRadius: AppRadius.medium, interactive: true)
                        }
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }

                    if let info = viewModel.infoMessage {
                        Text(info)
                            .font(.footnote)
                            .foregroundColor(.green)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await viewModel.submit() }
                    } label: {
                        HStack {
                            if viewModel.isLoading { ProgressView().tint(.white) }
                            Text(viewModel.mode == .signIn ? "Sign In" : "Create Account")
                        }
                    }
                    .buttonStyle(GradientPrimaryButtonStyle(isDisabled: viewModel.isLoading))
                    .disabled(viewModel.isLoading || viewModel.email.isEmpty || viewModel.password.isEmpty)

                    if viewModel.mode == .signIn {
                        Button("Forgot password?") {
                            Task { await viewModel.resetPassword() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.purple)
                    }

                    Button {
                        Task { await viewModel.continueAsGuest() }
                    } label: {
                        Text("Continue as guest")
                            .font(AppTypography.headline)
                            .foregroundColor(.purple)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .liquidGlass(cornerRadius: AppRadius.medium, interactive: true, tint: .purple)
                    }
                    .disabled(viewModel.isLoading)

                    Text("Your wardrobe, scans, and recommendations sync to Firebase Firestore & Storage.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(AppSpacing.xl)
            }
        }
        .onAppear {
            // screen_view is also tracked from RootView transitions when signed out.
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("Sylyo")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.primaryGradient)
            Text("Sign in with your Firebase account to sync wardrobe data and power analytics.")
                .font(AppTypography.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
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
            .liquidGlass(cornerRadius: AppRadius.medium, interactive: true)
    }
}
