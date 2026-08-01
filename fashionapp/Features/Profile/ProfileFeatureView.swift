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

    var languageDisplayName: String {
        switch selectedLanguage {
        case "it": return "Italiano"
        default: return "English"
        }
    }

    func load() async {
        analytics.track(.screenView, parameters: ["screen_name": "profile"])
        do {
            profile = try await profileRepository.load()
            // Gender-preference flags are not used — keep wardrobe styling modest and practical.
            profile.genderNeutralPreferred = false
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
            profile.genderNeutralPreferred = false
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
            // Apple HIG: Settings-style inset grouped list — sections, succinct rows, clear hierarchy.
            List {
                profileSection
                wardrobeSection
                accountSection
                preferencesSection
                aboutSection
                dataSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .nookSafeScreenInsets()
            .nookScreenBackground()
            .navigationTitle(NSLocalizedString("Profile", comment: ""))
            .navigationBarTitleDisplayMode(.large)
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
                    bodyText: "Nook stores your account and wardrobe securely in your cloud project. Photos you add are processed on this device to remove backgrounds and suggest clothing details, then saved to your account storage. Anonymous usage events help improve the app. Location is used only while Nook is open to show local weather for outfit ideas — never for ads."
                )
            }
            .sheet(isPresented: $viewModel.showAbout) {
                infoSheet(
                    title: NSLocalizedString("About Us", comment: ""),
                    bodyText: "Nook: Private wardrobe helps you manage your closet and choose modest, practical outfits. Add clothes from photos, organize what you own, and get ideas that match the weather — without a public social feed."
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

    // MARK: - Sections (HIG grouped list)

    private var profileSection: some View {
        Section {
            HStack(spacing: 16) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let avatarImage = viewModel.avatarImage {
                            Image(uiImage: avatarImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.secondary)
                                .padding(10)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .background(Color(.secondarySystemFill))
                    .clipShape(Circle())

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Image(systemName: "camera.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .font(.title3)
                            .accessibilityLabel(NSLocalizedString("Change photo", comment: ""))
                    }
                    .offset(x: 4, y: 4)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    TextField(
                        NSLocalizedString("Name", comment: ""),
                        text: $viewModel.profile.displayName
                    )
                    .font(.headline)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit {
                        Task { await viewModel.saveProfile() }
                    }

                    Text(NSLocalizedString("Private wardrobe", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private var wardrobeSection: some View {
        Section {
            labeledValueRow(
                title: NSLocalizedString("Items", comment: ""),
                value: "\(viewModel.statistics.totalItems)",
                systemImage: "tshirt"
            )
            labeledValueRow(
                title: NSLocalizedString("Favorites", comment: ""),
                value: "\(viewModel.statistics.favoritesCount)",
                systemImage: "heart"
            )
            labeledValueRow(
                title: NSLocalizedString("Worn this week", comment: ""),
                value: "\(viewModel.statistics.wornThisWeek)",
                systemImage: "calendar"
            )
        } header: {
            Text(NSLocalizedString("Wardrobe", comment: ""))
        }
    }

    private var accountSection: some View {
        Section {
            LabeledContent(NSLocalizedString("Sign-in", comment: "")) {
                Text(accountStatusText)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            if let email = viewModel.authUser?.email, !email.isEmpty {
                LabeledContent(NSLocalizedString("Email", comment: "")) {
                    Text(email)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Button(role: .destructive) {
                viewModel.showSignOutAlert = true
            } label: {
                Text(NSLocalizedString("Log Out", comment: ""))
            }
        } header: {
            Text(NSLocalizedString("Account", comment: ""))
        } footer: {
            if let id = viewModel.authUser?.id, !id.isEmpty {
                Text("UID \(id)")
                    .font(.caption2)
                    .textSelection(.enabled)
            }
        }
    }

    private var preferencesSection: some View {
        Section {
            Button {
                viewModel.showLanguage = true
            } label: {
                // HIG: succinct primary label + secondary value + disclosure cue.
                HStack {
                    Label(NSLocalizedString("Language", comment: ""), systemImage: "globe")
                    Spacer()
                    Text(viewModel.languageDisplayName)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)

            Toggle(isOn: Binding(
                get: { viewModel.usesCelsius },
                set: { viewModel.usesCelsius = $0 }
            )) {
                Label(NSLocalizedString("Use Celsius", comment: ""), systemImage: "thermometer.medium")
            }
        } header: {
            Text(NSLocalizedString("Preferences", comment: ""))
        } footer: {
            Text(NSLocalizedString(
                "Nook is a private closet tool. Outfit ideas stay on your device and account — not a public social feed.",
                comment: "Preferences footer explaining private-first product stance"
            ))
        }
    }

    private var aboutSection: some View {
        Section {
            disclosureButton(
                title: NSLocalizedString("Privacy Policy", comment: ""),
                systemImage: "lock.shield"
            ) {
                viewModel.showPrivacy = true
            }
            disclosureButton(
                title: NSLocalizedString("About Us", comment: ""),
                systemImage: "info.circle"
            ) {
                viewModel.showAbout = true
            }
        } header: {
            Text(NSLocalizedString("About", comment: ""))
        }
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                viewModel.showResetAlert = true
            } label: {
                Label(NSLocalizedString("Reset Onboarding", comment: ""), systemImage: "arrow.counterclockwise")
            }

            Button(role: .destructive) {
                viewModel.showClearAlert = true
            } label: {
                Label(NSLocalizedString("Clear All Data", comment: ""), systemImage: "trash")
            }
        } header: {
            Text(NSLocalizedString("Data", comment: ""))
        } footer: {
            Text(NSLocalizedString(
                "Clearing data permanently removes wardrobe items stored for this account on this device.",
                comment: "Data section footer"
            ))
        }
    }

    // MARK: - Rows

    private var accountStatusText: String {
        if viewModel.authUser?.usesSignInWithApple == true {
            return NSLocalizedString("Sign in with Apple", comment: "")
        }
        if viewModel.authUser?.isAnonymous == true {
            return NSLocalizedString("Anonymous", comment: "")
        }
        if viewModel.authUser != nil {
            return NSLocalizedString("Signed in", comment: "")
        }
        return NSLocalizedString("Not signed in", comment: "")
    }

    private func labeledValueRow(title: String, value: String, systemImage: String) -> some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } label: {
            Label(title, systemImage: systemImage)
        }
        .accessibilityElement(children: .combine)
    }

    private func disclosureButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Sheets

    private var languageSheet: some View {
        NavigationStack {
            List {
                languageRow("English", code: "en")
                languageRow("Italiano", code: "it")
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("Select Language", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Close", comment: "")) {
                        viewModel.showLanguage = false
                    }
                }
            }
        }
    }

    private func languageRow(_ title: String, code: String) -> some View {
        Button {
            viewModel.selectedLanguage = code
            viewModel.profile.preferredLanguage = code
            Task { await viewModel.saveProfile() }
            viewModel.showLanguage = false
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if viewModel.selectedLanguage == code {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel(NSLocalizedString("Selected", comment: ""))
                }
            }
        }
    }

    private func infoSheet(title: String, bodyText: String) -> some View {
        NavigationStack {
            List {
                Section {
                    Text(bodyText)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
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
