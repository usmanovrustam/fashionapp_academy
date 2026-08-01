import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case signUp = "Join"

        var id: String { rawValue }

        var ctaTitle: String {
            switch self {
            case .signIn: return "Welcome back"
            case .signUp: return "Create account"
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

/// Fashion editorial login — animated atmosphere + one Liquid Glass form.
struct AuthFeatureView: View {
    @StateObject private var viewModel: AuthViewModel
    @Namespace private var glassNamespace
    @State private var appeared = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, email, password
    }

    init(auth: AuthServicing, analytics: AnalyticsTracking) {
        _viewModel = StateObject(wrappedValue: AuthViewModel(auth: auth, analytics: analytics))
    }

    var body: some View {
        ZStack {
            FashionLoginBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    brandHero
                        .padding(.top, 56)
                        .padding(.bottom, 36)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 18)

                    formCard
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 28)

                    guestSection
                        .padding(.top, 22)
                        .opacity(appeared ? 1 : 0)

                    Text("Your wardrobe syncs securely with Firebase.")
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 18)
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 24)
            }
        }
        .tint(AppColors.brand)
        .preferredColorScheme(.light)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.84)) {
                appeared = true
            }
        }
    }

    private var brandHero: some View {
        // Wordmark only for now — no logo mark / app icon treatment.
        VStack(spacing: 12) {
            Text("Sylyo")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)

            Text("Sign in to your AI wardrobe.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var formCard: some View {
        SylyoGlassContainer(spacing: 18) {
            VStack(alignment: .leading, spacing: 20) {
                modeSwitcher

                VStack(spacing: 12) {
                    if viewModel.mode == .signUp {
                        authField(
                            icon: "person",
                            title: "Name",
                            text: $viewModel.displayName,
                            contentType: .name,
                            field: .name
                        )
                        .sylyoGlassEffectID("auth-name", in: glassNamespace)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                    }

                    authField(
                        icon: "envelope",
                        title: "Email",
                        text: $viewModel.email,
                        contentType: .emailAddress,
                        keyboard: .emailAddress,
                        field: .email
                    )
                    .sylyoGlassEffectID("auth-email", in: glassNamespace)

                    passwordField
                        .sylyoGlassEffectID("auth-password", in: glassNamespace)
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.86), value: viewModel.mode)

                statusMessages

                if viewModel.mode == .signIn {
                    HStack {
                        Spacer()
                        Button("Forgot password?") {
                            Task { await viewModel.resetPassword() }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .disabled(viewModel.isLoading)
                    }
                }

                Button {
                    focusedField = nil
                    Task { await viewModel.submit() }
                } label: {
                    HStack(spacing: 10) {
                        if viewModel.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(AppColors.textPrimary)
                        }
                        Text(viewModel.mode.ctaTitle)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(LiquidGlassButtonStyle(
                    prominent: true,
                    isDisabled: !viewModel.canSubmit
                ))
                .disabled(!viewModel.canSubmit)
                .sylyoGlassEffectID("auth-primary", in: glassNamespace)
            }
            .padding(22)
            .liquidGlass(cornerRadius: 28)
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(AuthViewModel.Mode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        viewModel.mode = mode
                        viewModel.errorMessage = nil
                        viewModel.infoMessage = nil
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(viewModel.mode == mode ? AppColors.textPrimary : AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            if viewModel.mode == mode {
                                Capsule()
                                    .fill(Color.clear)
                                    .liquidGlassCapsule(interactive: false)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .liquidGlassCapsule(interactive: false)
    }

    private var passwordField: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock")
                .font(.body.weight(.medium))
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 22)

            Group {
                if viewModel.isPasswordVisible {
                    TextField("Password", text: $viewModel.password)
                        .textContentType(viewModel.mode == .signUp ? .newPassword : .password)
                } else {
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(viewModel.mode == .signUp ? .newPassword : .password)
                }
            }
            .focused($focusedField, equals: .password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                viewModel.isPasswordVisible.toggle()
            } label: {
                Image(systemName: viewModel.isPasswordVisible ? "eye.slash" : "eye")
                    .font(.body)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .liquidGlass(cornerRadius: AppRadius.medium, interactive: true)
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppColors.textTertiary.opacity(focusedField == .password ? 0.45 : 0.22), lineWidth: 1)
        }
    }

    private var guestSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(AppColors.textTertiary.opacity(0.22))
                    .frame(height: 1)
                Text("or")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.textSecondary)
                Rectangle()
                    .fill(AppColors.textTertiary.opacity(0.22))
                    .frame(height: 1)
            }

            Button {
                focusedField = nil
                Task { await viewModel.continueAsGuest() }
            } label: {
                Text("Continue as guest")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LiquidGlassButtonStyle(
                prominent: false,
                isDisabled: viewModel.isLoading
            ))
            .disabled(viewModel.isLoading)
            .sylyoGlassEffectID("auth-guest", in: glassNamespace)
        }
    }

    @ViewBuilder
    private var statusMessages: some View {
        if let error = viewModel.errorMessage {
            Label(error, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Color(red: 0.72, green: 0.22, blue: 0.24))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .liquidGlass(cornerRadius: 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }

        if let info = viewModel.infoMessage {
            Label(info, systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Color(red: 0.22, green: 0.48, blue: 0.34))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .liquidGlass(cornerRadius: 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func authField(
        icon: String,
        title: String,
        text: Binding<String>,
        contentType: UITextContentType,
        keyboard: UIKeyboardType = .default,
        field: Field
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 22)

            TextField(title, text: text)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(contentType == .name ? .words : .never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: field)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .liquidGlass(cornerRadius: AppRadius.medium, interactive: true)
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppColors.textTertiary.opacity(focusedField == field ? 0.45 : 0.22), lineWidth: 1)
        }
    }
}

// MARK: - Atmosphere

/// Soft sky atmosphere — static radial washes (no live blur animation).
private struct FashionLoginBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.98, blue: 1.0),
                    Color(red: 0.94, green: 0.97, blue: 1.0),
                    Color(red: 0.92, green: 0.95, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [AppColors.brand.opacity(0.28), Color.clear],
                center: UnitPoint(x: 0.15, y: 0.05),
                startRadius: 20,
                endRadius: 320
            )
            RadialGradient(
                colors: [AppColors.accent.opacity(0.30), Color.clear],
                center: UnitPoint(x: 0.9, y: 0.75),
                startRadius: 10,
                endRadius: 340
            )
            RadialGradient(
                colors: [AppColors.blush.opacity(0.35), Color.clear],
                center: UnitPoint(x: 0.55, y: 0.45),
                startRadius: 10,
                endRadius: 260
            )
        }
        .ignoresSafeArea()
    }
}
