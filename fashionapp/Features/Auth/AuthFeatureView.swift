import AuthenticationServices
import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case signUp = "Register"

        var id: String { rawValue }

        /// Verb-led primary action (HIG Buttons).
        var ctaTitle: String { rawValue }

        var loadingTitle: String {
            switch self {
            case .signIn: return "Signing In…"
            case .signUp: return "Registering…"
            }
        }

        var appleButtonType: SignInWithAppleButton.Label {
            switch self {
            case .signIn: return .signIn
            case .signUp: return .signUp
            }
        }
    }

    @Published var mode: Mode = .signIn
    @Published var email = ""
    @Published var password = ""
    @Published var displayName = ""
    @Published var isLoading = false
    @Published var isPasswordVisible = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    /// Raw nonce paired with the hashed value sent in the Apple request.
    private(set) var currentAppleNonce: String?

    private let auth: AuthServicing
    private let analytics: AnalyticsTracking

    init(auth: AuthServicing, analytics: AnalyticsTracking) {
        self.auth = auth
        self.analytics = analytics
    }

    var canSubmit: Bool {
        !isLoading
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleSignInSupport.randomNonce()
        currentAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleSignInSupport.sha256(nonce)
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            errorMessage = error.localizedDescription
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let rawNonce = currentAppleNonce
            else {
                errorMessage = "Unable to complete Sign in with Apple."
                return
            }

            isLoading = true
            errorMessage = nil
            infoMessage = nil
            defer {
                isLoading = false
                currentAppleNonce = nil
            }

            do {
                let user = try await auth.signInWithApple(
                    idToken: idToken,
                    rawNonce: rawNonce,
                    fullName: credential.fullName
                )
                analytics.setUserID(user.id)
                analytics.track(
                    mode == .signUp ? .signUp : .login,
                    parameters: ["method": "apple"]
                )
            } catch let authError as AuthError where authError == .cancelled {
                // User dismissed — stay quiet.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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

/// HIG-aligned auth with prominent system Sign in with Apple button
/// (https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple).
struct AuthFeatureView: View {
    @StateObject private var viewModel: AuthViewModel
    @FocusState private var focusedField: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field: Hashable {
        case name, email, password
    }

    /// Shared metrics so every text field stays the same height (HIG: consistent widths/layout).
    private enum FieldMetrics {
        static let height: CGFloat = 52
        static let control: CGFloat = 28
    }

    init(auth: AuthServicing, analytics: AnalyticsTracking) {
        _viewModel = StateObject(wrappedValue: AuthViewModel(auth: auth, analytics: analytics))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Authentication")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .accessibilityAddTraits(.isHeader)

                        Text("Sign in to access your wardrobe and personalized outfits.")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .padding(.bottom, 4)

                    formFields
                    statusMessages
                    emailActions

                    modeSwitchLink
                        .padding(.top, 4)

                    dividerLabel("or")
                        .padding(.vertical, 4)

                    // Apple under email path; privacy note sits with the button.
                    signInWithAppleSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
                .padding(.bottom, 32)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
                .sylyoSafeScreenInsets()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(SoftBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(AppColors.buttonBlue)
        .preferredColorScheme(.light)
    }

    // MARK: - Sign in with Apple

    private var signInWithAppleSection: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(viewModel.mode.appleButtonType) { request in
                viewModel.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await viewModel.handleAppleCompletion(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .clipShape(Capsule())
            .disabled(viewModel.isLoading)
            .opacity(viewModel.isLoading ? 0.6 : 1)
            .accessibilityHint("Uses your Apple Account with Face ID or Touch ID when available")

            Text("Sign in with Apple shares only the name and email you choose.")
                .font(.caption)
                .foregroundStyle(AppColors.placeholder)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
        }
    }

    private func dividerLabel(_ text: String) -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(AppColors.textTertiary.opacity(0.22))
                .frame(height: 1)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColors.placeholder)
                .layoutPriority(1)
            Rectangle()
                .fill(AppColors.textTertiary.opacity(0.22))
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Mode switch (text link — no segmented control)

    private var modeSwitchLink: some View {
        HStack(spacing: 4) {
            if viewModel.mode == .signIn {
                Text("Don't have an account?")
                    .foregroundStyle(AppColors.placeholder)
                Button("Register") {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        viewModel.mode = .signUp
                        viewModel.errorMessage = nil
                        viewModel.infoMessage = nil
                        focusedField = .name
                    }
                }
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.buttonBlue)
            } else {
                Text("Already have an account?")
                    .foregroundStyle(AppColors.placeholder)
                Button("Sign In") {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        viewModel.mode = .signIn
                        viewModel.errorMessage = nil
                        viewModel.infoMessage = nil
                        focusedField = .email
                    }
                }
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.buttonBlue)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Fields (HIG Text Fields)

    private var formFields: some View {
        // Even vertical spacing + consistent full widths (HIG: stack fields, same width).
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.mode == .signUp {
                labeledField(title: "Name") {
                    HStack(spacing: 8) {
                        TextField(
                            "",
                            text: $viewModel.displayName,
                            prompt: Text("Name").foregroundStyle(AppColors.placeholder)
                        )
                        .font(.body)
                        .multilineTextAlignment(.leading)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .name)
                        .onSubmit { focusedField = .email }

                        clearButton(text: $viewModel.displayName)
                    }
                }
                .transition(.opacity)
            }

            labeledField(title: "Email") {
                HStack(spacing: 8) {
                    TextField(
                        "",
                        text: $viewModel.email,
                        prompt: Text("Email").foregroundStyle(AppColors.placeholder)
                    )
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }

                    clearButton(text: $viewModel.email)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                labeledField(title: "Password") {
                    HStack(spacing: 8) {
                        Group {
                            if viewModel.isPasswordVisible {
                                TextField(
                                    "",
                                    text: $viewModel.password,
                                    prompt: Text("Password").foregroundStyle(AppColors.placeholder)
                                )
                                .textContentType(viewModel.mode == .signUp ? .newPassword : .password)
                            } else {
                                // HIG: use a secure text field for sensitive data.
                                SecureField(
                                    "",
                                    text: $viewModel.password,
                                    prompt: Text("Password").foregroundStyle(AppColors.placeholder)
                                )
                                .textContentType(viewModel.mode == .signUp ? .newPassword : .password)
                            }
                        }
                        .font(.body)
                        .multilineTextAlignment(.leading)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focusedField, equals: .password)
                        .onSubmit {
                            guard viewModel.canSubmit else { return }
                            focusedField = nil
                            Task { await viewModel.submit() }
                        }

                        // Trailing controls for extra features (HIG).
                        if !viewModel.password.isEmpty {
                            clearButton(text: $viewModel.password)
                        }

                        Button {
                            viewModel.isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: viewModel.isPasswordVisible ? "eye.slash" : "eye")
                                .font(.body)
                                .foregroundStyle(AppColors.placeholder)
                                .frame(width: FieldMetrics.control, height: FieldMetrics.control)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(viewModel.isPasswordVisible ? "Hide password" : "Show password")
                    }
                }

                if viewModel.mode == .signIn {
                    HStack {
                        Spacer(minLength: 0)
                        Button("Forgot Password?") {
                            Task { await viewModel.resetPassword() }
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppColors.buttonBlue)
                        .disabled(viewModel.isLoading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.mode)
    }

    /// Persistent label + placeholder (HIG: placeholder disappears while typing).
    private func labeledField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityHidden(true)

            content()
                .padding(.horizontal, 16)
                // Fixed height — trailing icons must not grow the field.
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: FieldMetrics.height)
                .liquidGlass(cornerRadius: AppRadius.medium, interactive: true)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Trailing Clear control (HIG iOS/iPadOS text fields).
    @ViewBuilder
    private func clearButton(text: Binding<String>) -> some View {
        if !text.wrappedValue.isEmpty {
            Button {
                text.wrappedValue = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(AppColors.placeholder)
                    .frame(width: FieldMetrics.control, height: FieldMetrics.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear text")
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusMessages: some View {
        if let error = viewModel.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Color(.systemRed))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(12)
                .liquidGlass(cornerRadius: 12)
                .accessibilityAddTraits(.isStaticText)
        }

        if let info = viewModel.infoMessage {
            Label(info, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color(.systemGreen))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(12)
                .liquidGlass(cornerRadius: 12)
                .accessibilityAddTraits(.isStaticText)
        }
    }

    // MARK: - Actions

    private var emailActions: some View {
        Button {
            focusedField = nil
            Task { await viewModel.submit() }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(viewModel.isLoading ? viewModel.mode.loadingTitle : viewModel.mode.ctaTitle)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(LiquidGlassButtonStyle(
            prominent: true,
            isDisabled: !viewModel.canSubmit
        ))
        .disabled(!viewModel.canSubmit)
        .accessibilityHint(
            viewModel.mode == .signIn
                ? "Signs in with email and password"
                : "Creates a new account with email and password"
        )
    }
}
