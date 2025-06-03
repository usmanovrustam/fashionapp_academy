import SwiftUI
import CloudKit
import UIKit
import AuthenticationServices

struct ProfileView: View {
    @Binding var showClearAlert: Bool
    @Binding var showResetOnboardingAlert: Bool
    var clearAllData: () -> Void
    var resetOnboarding: () -> Void

    @State private var userName: String? = nil
    @State private var isLoading = true
    @State private var iCloudAvailable = true
    @State private var showSettingsSheet = false
    @State private var appleName: String? = nil
    @State private var isAppleSignedIn = false
    @State private var signInErrorMessage: String? = nil
    let profileImage: Image = Image(systemName: "person.crop.circle.fill")

    @AppStorage("selectedTheme") private var selectedTheme: String = "system"
    @State private var showLanguageSheet = false
    @State private var showPrivacyPolicy = false
    @State private var showAboutUs = false
    @State private var showShareSheet = false
    @State private var showLogoutAlert = false

    @State private var profileImageScale: CGFloat = 0.8
    @AppStorage("selectedLanguage") private var selectedLanguage: String = Locale.current.languageCode ?? "en"

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                 // Modern gradient background
              
                ScrollView(showsIndicators: false) {
                    VStack {
                        Spacer(minLength: geometry.size.height * 0.04)
                        // Profile Card with glassmorphism
                        VStack(spacing: geometry.size.height * 0.025) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.18))
                                    .frame(width: min(geometry.size.width * 0.32, 130), height: min(geometry.size.width * 0.32, 130))
                                    .blur(radius: 0.5)
                                profileImage
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: min(geometry.size.width * 0.27, 110), height: min(geometry.size.width * 0.27, 110))
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 3))
                                    .shadow(color: Color.accentColor.opacity(0.18), radius: 16, x: 0, y: 8)
                                    .scaleEffect(profileImageScale)
                                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: profileImageScale)
                                    .onAppear { profileImageScale = 1.0 }
                            }
                            if isLoading {
                                ProgressView()
                                    .frame(width: 100, height: 20)
                            } else if let name = appleName ?? userName {
                                Text(name)
                                    .font(.system(size: min(geometry.size.width * 0.07, 28), weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .accessibilityLabel("Name: \(name)")
                            } else {
                                Text(NSLocalizedString("User", comment: ""))
                                    .font(.system(size: min(geometry.size.width * 0.07, 28), weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                Text(NSLocalizedString("If your name does not appear, it means your Apple ID is not discoverable to apps. This is controlled by your Apple ID privacy settings. The 'Look Me Up' section in iCloud Settings is informational only.", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            Text(NSLocalizedString("iCloud Account", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .accessibilityLabel("iCloud Account")
                            if !iCloudAvailable {
                                Spacer(minLength: 12)
                            } else if !isAppleSignedIn {
                                SignInWithAppleButton(
                                    .signIn,
                                    onRequest: { request in
                                        request.requestedScopes = [.fullName, .email]
                                    },
                                    onCompletion: handleAppleSignIn
                                )
                                .signInWithAppleButtonStyle(.black)
                                .frame(height: 45)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .padding(.horizontal, 32)
                                .accessibilityLabel("Sign in with Apple")
                                Text(NSLocalizedString("Sign in with Apple to display your name.", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                if let errorMsg = signInErrorMessage {
                                    Text(errorMsg)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.vertical, geometry.size.height * 0.04)
                        .padding(.horizontal, min(geometry.size.width * 0.05, 32))
                        .frame(maxWidth: min(geometry.size.width * 0.95, 440))
                        .background(
                            BlurView(style: .systemUltraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                                .shadow(color: Color.black.opacity(0.10), radius: 24, x: 0, y: 12)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 36, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .accessibilityElement(children: .combine)
                        Spacer(minLength: geometry.size.height * 0.03)
                        // THEME & LANGUAGE SECTION
                        VStack(alignment: .leading, spacing: 0) {
                            Text(NSLocalizedString("Appearance", comment: ""))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.leading, 28)
                                .padding(.top, 8)
                            HStack {
                                Label(NSLocalizedString("Theme", comment: ""), systemImage: "moon.circle")
                                    .font(.headline)
                                Spacer()
                                Picker("Theme", selection: $selectedTheme) {
                                    Text(NSLocalizedString("System", comment: "")).tag("system")
                                    Text(NSLocalizedString("Light", comment: "")).tag("light")
                                    Text(NSLocalizedString("Dark", comment: "")).tag("dark")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: min(geometry.size.width * 0.45, 180))
                                .onChange(of: selectedTheme) { newValue in
                                    applyTheme(newValue)
                                }
                            }
                            .padding(.vertical, 16)
                            .padding(.horizontal, 24)
                            Divider().padding(.horizontal, 16)
                            Button {
                                showLanguageSheet = true
                            } label: {
                                HStack {
                                    Label(NSLocalizedString("Language", comment: ""), systemImage: "globe")
                                        .font(.headline)
                                    Spacer()
                                    Text(Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? NSLocalizedString("System", comment: ""))
                                        .foregroundColor(.secondary)
                                        .font(.subheadline)
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 16)
                                .padding(.horizontal, 24)
                            }
                        }
                        .frame(maxWidth: min(geometry.size.width * 0.95, 440))
                        .background(
                            BlurView(style: .systemUltraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                                .shadow(color: Color.black.opacity(0.07), radius: 12, x: 0, y: 6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                        .padding(.horizontal, min(geometry.size.width * 0.05, 16))
                        .padding(.top, 8)
                        .sheet(isPresented: $showLanguageSheet) {
                            VStack(spacing: 24) {
                                Text(NSLocalizedString("Select Language", comment: ""))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                VStack(spacing: 12) {
                                    LanguageTile(languageCode: "en", languageName: "English", flag: "🇬🇧", selectedLanguage: $selectedLanguage) { showLanguageSheet = false }
                                    LanguageTile(languageCode: "it", languageName: "Italiano", flag: "🇮🇹", selectedLanguage: $selectedLanguage) { showLanguageSheet = false }
                                }
                                .padding(.top, 8)
                                Button(NSLocalizedString("Close", comment: "")) { showLanguageSheet = false }
                                    .padding(.top, 16)
                            }
                            .padding()
                        }
                        Spacer(minLength: geometry.size.height * 0.03)
                        // INFO & SHARE SECTION
                        VStack(alignment: .leading, spacing: 0) {
                            Text(NSLocalizedString("Info & Sharing", comment: ""))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.leading, 28)
                                .padding(.top, 8)
                            Button {
                                showPrivacyPolicy = true
                            } label: {
                                HStack {
                                    Label(NSLocalizedString("Privacy Policy", comment: ""), systemImage: "lock.shield")
                                        .font(.headline)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 16)
                                .padding(.horizontal, 24)
                            }
                            Divider().padding(.horizontal, 16)
                            Button {
                                showAboutUs = true
                            } label: {
                                HStack {
                                    Label(NSLocalizedString("About Us", comment: ""), systemImage: "info.circle")
                                        .font(.headline)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 16)
                                .padding(.horizontal, 24)
                            }
                            Divider().padding(.horizontal, 16)
                            Button {
                                showShareSheet = true
                            } label: {
                                HStack {
                                    Label(NSLocalizedString("Share App", comment: ""), systemImage: "square.and.arrow.up")
                                        .font(.headline)
                                    Spacer()
                                }
                                .padding(.vertical, 16)
                                .padding(.horizontal, 24)
                            }
                        }
                        .frame(maxWidth: min(geometry.size.width * 0.95, 440))
                        .background(
                            BlurView(style: .systemUltraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                                .shadow(color: Color.black.opacity(0.07), radius: 12, x: 0, y: 6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                        .padding(.horizontal, min(geometry.size.width * 0.05, 16))
                        .padding(.top, 8)
                        .sheet(isPresented: $showPrivacyPolicy) {
                            VStack(spacing: 24) {
                                Text(NSLocalizedString("Privacy Policy", comment: ""))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                // Add your privacy policy content here
                                Button(NSLocalizedString("Close", comment: "")) { showPrivacyPolicy = false }
                                    .padding(.top, 32)
                            }
                            .padding()
                        }
                        .sheet(isPresented: $showAboutUs) {
                            VStack(spacing: 24) {
                                Text(NSLocalizedString("About Us", comment: ""))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                // Add your about us content here
                                Button(NSLocalizedString("Close", comment: "")) { showAboutUs = false }
                                    .padding(.top, 32)
                            }
                            .padding()
                        }
                        .sheet(isPresented: $showShareSheet) {
                            ActivityView(activityItems: [URL(string: "https://yourapp.com")!])
                        }
                        Spacer(minLength: geometry.size.height * 0.03)
                        // LOGOUT SECTION
                        VStack(alignment: .leading, spacing: 0) {
                            Text(NSLocalizedString("Account", comment: ""))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.leading, 28)
                                .padding(.top, 8)
                            Button(role: .destructive) {
                                showLogoutAlert = true
                            } label: {
                                HStack {
                                    Label(NSLocalizedString("Log Out", comment: ""), systemImage: "rectangle.portrait.and.arrow.right")
                                        .font(.headline)
                                    Spacer()
                                }
                                .padding(.vertical, 16)
                                .padding(.horizontal, 24)
                            }
                        }
                        .frame(maxWidth: min(geometry.size.width * 0.95, 440))
                        .background(
                            BlurView(style: .systemUltraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                                .shadow(color: Color.black.opacity(0.07), radius: 12, x: 0, y: 6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                        .padding(.horizontal, min(geometry.size.width * 0.05, 16))
                        .padding(.top, 8)
                        .alert("Are you sure you want to log out?", isPresented: $showLogoutAlert) {
                            Button(NSLocalizedString("Log Out", comment: ""), role: .destructive) {
                                // Add your logout logic here
                            }
                            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
                        }
                        Spacer(minLength: geometry.size.height * 0.04)
                    }
                }
            }
        }
        .onAppear {
            checkiCloudStatus()
            if let savedName = UserDefaults.standard.string(forKey: "appleUserName") {
                print("onAppear loaded Apple name from UserDefaults: \(savedName)")
                self.appleName = savedName
                self.isAppleSignedIn = true
            }
            applyTheme(selectedTheme)
        }
        .sheet(isPresented: $showSettingsSheet) {
            VStack(spacing: 24) {
                Image(systemName: "icloud.slash")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.red)
                Text(NSLocalizedString("iCloud Required", comment: ""))
                    .font(.title2)
                    .fontWeight(.bold)
                Text(NSLocalizedString("You must be signed in to iCloud to use your profile. Please sign in to iCloud in Settings.", comment: ""))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button(action: openSettings) {
                    Text(NSLocalizedString("Open Settings", comment: ""))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                Spacer()
            }
            .padding(.top, 60)
            .presentationDetents([.medium, .large])
        }
    }

    private func checkiCloudStatus() {
        let container = CKContainer.default()
        container.accountStatus { status, error in
            DispatchQueue.main.async {
                if status == .available {
                    self.iCloudAvailable = true
                    self.showSettingsSheet = false
                    self.fetchUserName()
                } else {
                    self.iCloudAvailable = false
                    self.showSettingsSheet = true
                    self.isLoading = false
                }
            }
        }
    }

    private func fetchUserName() {
        let container = CKContainer.default()
        container.fetchUserRecordID { recordID, error in
            guard let recordID = recordID, error == nil else {
                DispatchQueue.main.async {
                    self.userName = nil
                    self.isLoading = false
                }
                return
            }
            container.discoverUserIdentity(withUserRecordID: recordID) { identity, error in
                DispatchQueue.main.async {
                    if let name = identity?.nameComponents?.formatted() {
                        self.userName = name
                    } else {
                        self.userName = nil
                    }
                    self.isLoading = false
                }
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                print("Apple credential fullName: \(String(describing: credential.fullName))")
                if let fullName = credential.fullName {
                    let formatter = PersonNameComponentsFormatter()
                    let name = formatter.string(from: fullName)
                    print("Saving Apple name to UserDefaults: \(name)")
                    self.appleName = name
                    // Save to UserDefaults for future use
                    UserDefaults.standard.set(name, forKey: "appleUserName")
                } else {
                    let savedName = UserDefaults.standard.string(forKey: "appleUserName")
                    print("Loaded Apple name from UserDefaults: \(String(describing: savedName))")
                    self.appleName = savedName
                }
                self.isAppleSignedIn = true
                self.signInErrorMessage = nil
            }
        case .failure(let error):
            print("Apple sign-in failed: \(error.localizedDescription)")
            self.isAppleSignedIn = false
            self.signInErrorMessage = "Sign in was canceled or failed. Please try again."
        }
    }

    // Helper for theme switching
    private func applyTheme(_ theme: String) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        switch theme {
        case "light": window.overrideUserInterfaceStyle = .light
        case "dark": window.overrideUserInterfaceStyle = .dark
        default: window.overrideUserInterfaceStyle = .unspecified
        }
    }

    // UIKit wrapper for share sheet
    struct ActivityView: UIViewControllerRepresentable {
        let activityItems: [Any]
        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        }
        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    }
}

// Glassmorphism BlurView helper
import SwiftUI
import UIKit
struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

struct LanguageTile: View {
    let languageCode: String
    let languageName: String
    let flag: String
    @Binding var selectedLanguage: String
    var onSelect: () -> Void
    var body: some View {
        Button(action: {
            selectedLanguage = languageCode
            onSelect()
        }) {
            HStack {
                Text(flag)
                    .font(.title2)
                Text(languageName)
                    .font(.headline)
                Spacer()
                if selectedLanguage == languageCode {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
} 
