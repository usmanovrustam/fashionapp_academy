import SwiftUI
import PhotosUI

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profile: UserProfile = .default
    @Published var statistics: WardrobeStatistics = WardrobeStatistics(
        totalItems: 0,
        favoritesCount: 0,
        wornThisWeek: 0,
        categoryCounts: [:],
        mostWornItemID: nil,
        leastWornItemID: nil,
        averageFormality: 0
    )
    @Published var showLanguage = false
    @Published var showPrivacy = false
    @Published var showAbout = false
    @Published var showClearAlert = false
    @Published var showResetAlert = false
    @Published var showSignOutAlert = false
    @Published var avatarImage: UIImage?
    @Published var authUser: AuthUser?

    private let profileRepository: UserProfileRepository
    private let wardrobeRepository: WardrobeRepository
    private let statisticsUseCase: ComputeWardrobeStatisticsUseCase
    private let settings: AppSettingsProviding
    private let imageStorage: ImageStorage
    private let analytics: AnalyticsTracking
    private let signOutAction: () -> Void

    init(container: AppContainer) {
        self.profileRepository = container.profileRepository
        self.wardrobeRepository = container.wardrobeRepository
        self.statisticsUseCase = container.statisticsUseCase
        self.settings = container.settings
        self.imageStorage = container.imageStorage
        self.analytics = container.analytics
        self.signOutAction = { container.signOut() }
        self.authUser = container.currentAuthUser
    }

    var usesCelsius: Bool {
        get { settings.usesCelsius }
        set {
            objectWillChange.send()
            settings.usesCelsius = newValue
        }
    }

    var selectedLanguage: String {
        get { settings.selectedLanguage }
        set {
            objectWillChange.send()
            settings.selectedLanguage = newValue
        }
    }

    func load() async {
        analytics.track(.screenView, parameters: ["screen_name": "profile"])
        do {
            profile = try await profileRepository.load()
            if let authName = authUser?.displayName, profile.displayName == UserProfile.default.displayName {
                profile.displayName = authName
            }
            let items = try await wardrobeRepository.fetchAll()
            statistics = statisticsUseCase.execute(items: items)
            if let path = profile.avatarImagePath {
                avatarImage = UIImage(data: (try? await imageStorage.loadImageData(at: path)) ?? Data())
            }
        } catch {
            // Keep defaults.
        }
    }

    func saveProfile() async {
        do {
            try await profileRepository.save(profile)
            analytics.track(.profileUpdated, parameters: [
                "language": profile.preferredLanguage
            ])
        } catch {
            // Ignore for now; surface via alerts in a later iteration.
        }
    }

    func signOut() {
        signOutAction()
    }

    func setAvatar(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        do {
            let path = try await imageStorage.saveImageData(data, preferredName: "avatar-\(profile.id.uuidString).jpg")
            profile.avatarImagePath = path
            avatarImage = image
            try await profileRepository.save(profile)
        } catch {
            // Keep previous avatar.
        }
    }

    func clearAllData() async {
        try? await wardrobeRepository.deleteAll()
        settings.clearLocalPreferences()
        profile = .default
        statistics = statisticsUseCase.execute(items: [])
        avatarImage = nil
    }

    func resetOnboarding() {
        settings.didFinishOnboarding = false
    }
}

struct ProfileFeatureView: View {
    @StateObject private var viewModel: ProfileViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @Binding var didFinishOnboarding: Bool

    init(container: AppContainer, didFinishOnboarding: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(container: container))
        _didFinishOnboarding = didFinishOnboarding
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    avatarHeader
                    accountCard
                    statsRow
                    preferencesCard
                    infoCard
                    dangerCard
                }
                .padding()
                .padding(.bottom, AppSpacing.lg)
            }
            .sylyoSafeScreenInsets()
            .sylyoScreenBackground()
            .navigationTitle(NSLocalizedString("Profile", comment: ""))
            .task { await viewModel.load() }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await viewModel.setAvatar(image)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showLanguage) {
                languageSheet
            }
            .sheet(isPresented: $viewModel.showPrivacy) {
                infoSheet(
                    title: NSLocalizedString("Privacy Policy", comment: ""),
                    bodyText: "Sylyo stores your account and wardrobe securely in your cloud project. Photos you add are processed on this device to remove backgrounds and suggest clothing details, then saved to your account storage. Anonymous usage events help improve the app. Location is used only while Sylyo is open to show local weather for outfit ideas — never for ads."
                )
            }
            .sheet(isPresented: $viewModel.showAbout) {
                infoSheet(
                    title: NSLocalizedString("About Us", comment: ""),
                    bodyText: "Sylyo helps you decide what to wear. Add clothes from photos, keep a digital wardrobe, and get ideas that match the weather."
                )
            }
            .alert(NSLocalizedString("Clear All Data?", comment: ""), isPresented: $viewModel.showClearAlert) {
                Button(NSLocalizedString("Delete", comment: ""), role: .destructive) {
                    Task { await viewModel.clearAllData() }
                }
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("This will remove all app data. This action cannot be undone.", comment: ""))
            }
            .alert(NSLocalizedString("Reset Onboarding?", comment: ""), isPresented: $viewModel.showResetAlert) {
                Button(NSLocalizedString("Reset", comment: ""), role: .destructive) {
                    viewModel.resetOnboarding()
                    didFinishOnboarding = false
                }
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("You will see the onboarding screens again on next launch.", comment: ""))
            }
            .alert(NSLocalizedString("Log Out", comment: ""), isPresented: $viewModel.showSignOutAlert) {
                Button(NSLocalizedString("Log Out", comment: ""), role: .destructive) {
                    viewModel.signOut()
                }
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("Are you sure you want to log out?", comment: ""))
            }
        }
    }

    private var accountCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("Account", comment: ""))
                    .font(AppTypography.headline)
                if viewModel.authUser?.usesSignInWithApple == true {
                    // HIG Sign in with Apple — indicate current sign-in method.
                    Text("Using Sign in with Apple")
                        .foregroundStyle(.secondary)
                    if let email = viewModel.authUser?.email {
                        Text(email).foregroundStyle(.secondary)
                    }
                } else if let email = viewModel.authUser?.email {
                    Text(email).foregroundStyle(.secondary)
                } else if viewModel.authUser?.isAnonymous == true {
                    Text("Signed in anonymously").foregroundStyle(.secondary)
                } else {
                    Text("Not signed in").foregroundStyle(.secondary)
                }
                Text("UID: \(viewModel.authUser?.id ?? "—")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    viewModel.showSignOutAlert = true
                } label: {
                    Label(NSLocalizedString("Log Out", comment: ""), systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LiquidGlassButtonStyle(prominent: false, tint: .red))
                .controlSize(.large)
            }
        }
    }

    private var avatarHeader: some View {
        GlassCard {
            HStack(spacing: 16) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .stroke(AppColors.primaryGradient, lineWidth: 3)
                        .frame(width: 86, height: 86)
                        .overlay {
                            if let avatarImage = viewModel.avatarImage {
                                Image(uiImage: avatarImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 78, height: 78)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 34))
                                    .foregroundStyle(AppColors.primaryGradient)
                            }
                        }

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Image(systemName: "camera.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, AppColors.brand)
                    }
                    .offset(x: 4, y: 4)
                }

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Name", text: $viewModel.profile.displayName)
                        .font(.title3.bold())
                        .onSubmit {
                            Task { await viewModel.saveProfile() }
                        }
                    Text("Your wardrobe companion")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(title: "Items", value: "\(viewModel.statistics.totalItems)", icon: "tshirt.fill")
            StatCard(title: "Favorites", value: "\(viewModel.statistics.favoritesCount)", icon: "heart.fill")
            StatCard(title: "Worn / wk", value: "\(viewModel.statistics.wornThisWeek)", icon: "calendar")
        }
    }

    private var preferencesCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                Button { viewModel.showLanguage = true } label: {
                    SettingsRow(icon: "globe", title: NSLocalizedString("Language", comment: ""))
                }
                Toggle(isOn: Binding(
                    get: { viewModel.usesCelsius },
                    set: { viewModel.usesCelsius = $0 }
                )) {
                    Label("Use Celsius", systemImage: "thermometer")
                }
                .tint(AppColors.brand)

                Toggle(isOn: $viewModel.profile.genderNeutralPreferred) {
                    Label("Gender-neutral looks", systemImage: "person.2")
                }
                .tint(AppColors.brand)
                .onChange(of: viewModel.profile.genderNeutralPreferred) { _, _ in
                    Task { await viewModel.saveProfile() }
                }
            }
        }
    }

    private var infoCard: some View {
        GlassCard {
            VStack(spacing: 4) {
                Button { viewModel.showPrivacy = true } label: {
                    SettingsRow(icon: "lock.shield", title: NSLocalizedString("Privacy Policy", comment: ""))
                }
                Button { viewModel.showAbout = true } label: {
                    SettingsRow(icon: "info.circle", title: NSLocalizedString("About Us", comment: ""))
                }
            }
        }
    }

    private var dangerCard: some View {
        GlassCard {
            VStack(spacing: 4) {
                Button { viewModel.showResetAlert = true } label: {
                    SettingsRow(icon: "arrow.counterclockwise", title: "Reset Onboarding", tint: .orange)
                }
                Button { viewModel.showClearAlert = true } label: {
                    SettingsRow(icon: "trash", title: "Clear All Data", tint: .red)
                }
            }
        }
    }

    private var languageSheet: some View {
        NavigationStack {
            List {
                languageTile("English", code: "en")
                languageTile("Italiano", code: "it")
            }
            .navigationTitle(NSLocalizedString("Select Language", comment: ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Close", comment: "")) { viewModel.showLanguage = false }
                }
            }
        }
    }

    private func languageTile(_ title: String, code: String) -> some View {
        Button {
            viewModel.selectedLanguage = code
            viewModel.profile.preferredLanguage = code
            Task { await viewModel.saveProfile() }
            viewModel.showLanguage = false
        } label: {
            HStack {
                Text(title)
                Spacer()
                if viewModel.selectedLanguage == code {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.primaryGradient)
                }
            }
        }
    }

    private func infoSheet(title: String, bodyText: String) -> some View {
        NavigationStack {
            ScrollView {
                Text(bodyText)
                    .padding()
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Close", comment: "")) {
                        viewModel.showPrivacy = false
                        viewModel.showAbout = false
                    }
                }
            }
        }
    }
}
