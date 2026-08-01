import AuthenticationServices
import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case signUp = "Create Account"

        var id: String { rawValue }

        /// Verb-led primary action (HIG Buttons).
        var ctaTitle: String { rawValue }

        var loadingTitle: String {
            switch self {
            case .signIn: return "Signing In…"
            case .signUp: return "Creating Account…"
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

/// HIG-aligned auth with prominent system Sign in with Apple button
/// (https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple).
struct AuthFeatureView: View {
    @StateObject private var viewModel: AuthViewModel
    @FocusState private var focusedField: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field: Hashable {
        case name, email, password
    }

    init(auth: AuthServicing, analytics: AnalyticsTracking) {
        _viewModel = StateObject(wrappedValue: AuthViewModel(auth: auth, analytics: analytics))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    // SIWA first — prominent, no scroll required on typical iPhone (HIG SIWA).
                    signInWithAppleSection

                    dividerLabel("or use email")

                    formFields
                    statusMessages
                    emailActions
                    modeSwitchLink
                    guestAction
                    privacyFootnote
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
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
        .tint(AppColors.brand)
        .preferredColorScheme(.light)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sylyo")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(viewModel.mode == .signIn ? "Sign in to your account" : "Create your account")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)

            Text("Sync your wardrobe and get personalized outfits across devices. Sign in with Apple is fast and private — or continue as a guest.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sign in with Apple

    private var signInWithAppleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SignInWithAppleButton(viewModel.mode.appleButtonType) { request in
                viewModel.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await viewModel.handleAppleCompletion(result) }
            }
            // Black style on light backgrounds (HIG SIWA).
            .signInWithAppleButtonStyle(.black)
            // Match capsule CTAs; min size 140×30, keep ≥ other buttons.
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .clipShape(Capsule())
            // Margin ≥ 1/10 of button height around the control.
            .padding(.vertical, 5)
            .disabled(viewModel.isLoading)
            .opacity(viewModel.isLoading ? 0.6 : 1)
            .accessibilityHint("Uses your Apple Account with Face ID or Touch ID when available")
        }
    }

    private func dividerLabel(_ text: String) -> some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(AppColors.textTertiary.opacity(0.22))
                .frame(height: 1)
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppColors.textSecondary)
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
                    .foregroundStyle(AppColors.textSecondary)
                Button("Register") {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        viewModel.mode = .signUp
                        viewModel.errorMessage = nil
                        viewModel.infoMessage = nil
                        focusedField = .name
                    }
                }
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.brand)
            } else {
                Text("Already have an account?")
                    .foregroundStyle(AppColors.textSecondary)
                Button("Sign In") {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        viewModel.mode = .signIn
                        viewModel.errorMessage = nil
                        viewModel.infoMessage = nil
                        focusedField = .email
                    }
                }
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.brand)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Fields

    private var formFields: some View {
        VStack(spacing: 16) {
            if viewModel.mode == .signUp {
                labeledField(title: "Name", field: .name) {
                    TextField("Your name", text: $viewModel.displayName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .name)
                        .onSubmit { focusedField = .email }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            labeledField(title: "Email", field: .email) {
                TextField("name@example.com", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Password")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer(minLength: 8)
                    if viewModel.mode == .signIn {
                        Button("Forgot Password?") {
                            Task { await viewModel.resetPassword() }
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColors.brand)
                        .disabled(viewModel.isLoading)
                        .frame(minHeight: 44)
                    }
                }

                HStack(spacing: 10) {
                    Group {
                        if viewModel.isPasswordVisible {
                            TextField("Required", text: $viewModel.password)
                                .textContentType(viewModel.mode == .signUp ? .newPassword : .password)
                        } else {
                            SecureField("Required", text: $viewModel.password)
                                .textContentType(viewModel.mode == .signUp ? .newPassword : .password)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit {
                        guard viewModel.canSubmit else { return }
                        focusedField = nil
                        Task { await viewModel.submit() }
                    }

                    Button {
                        viewModel.isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: viewModel.isPasswordVisible ? "eye.slash" : "eye")
                            .font(.body)
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(viewModel.isPasswordVisible ? "Hide password" : "Show password")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .frame(minHeight: 48)
                .background(fieldBackground(focused: focusedField == .password))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.mode)
    }

    private func labeledField<Content: View>(
        title: String,
        field: Field,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
                .background(fieldBackground(focused: focusedField == field))
        }
    }

    private func fieldBackground(focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        focused ? AppColors.brand.opacity(0.85) : Color(.separator).opacity(0.55),
                        lineWidth: focused ? 1.5 : 1
                    )
            }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusMessages: some View {
        if let error = viewModel.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Color(.systemRed))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemRed).opacity(0.10))
                )
                .accessibilityLiveRegion(.assertive)
        }

        if let info = viewModel.infoMessage {
            Label(info, systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Color(.systemGreen))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemGreen).opacity(0.10))
                )
                .accessibilityLiveRegion(.polite)
        }
    }

    // MARK: - Actions

    private var emailActions: some View {
        Button {
            focusedField = nil
            Task { await viewModel.submit() }
        } label: {
            HStack(spacing: 10) {
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

    private var guestAction: some View {
        Button {
            focusedField = nil
            Task { await viewModel.continueAsGuest() }
        } label: {
            Text("Continue as Guest")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(AppColors.brand)
        .disabled(viewModel.isLoading)
        .accessibilityHint("Explore Sylyo without creating an account")
    }

    private var privacyFootnote: some View {
        Text("Sign in with Apple shares only the name and email you choose. Guest mode keeps items on this device until you create an account.")
            .font(.footnote)
            .foregroundStyle(AppColors.textTertiary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}
