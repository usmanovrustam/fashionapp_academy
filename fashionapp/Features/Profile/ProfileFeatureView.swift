import SwiftUI
import PhotosUI
import StoreKit

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
    @Published var showTerms = false
    @Published var showAbout = false
    @Published var showFavorites = false
    @Published var showNeeds = false
    @Published var showSignOutAlert = false
    @Published var showMarkAllWashedAlert = false
    @Published var showExportShare = false
    @Published var showShareApp = false
    @Published var exportShareURL: URL?
    @Published var exportErrorMessage: String?
    @Published var avatarImage: UIImage?
    @Published var authUser: AuthUser?
    @Published var laundryItems: [WardrobeItem] = []
    @Published var favoriteItems: [WardrobeItem] = []

    private let profileRepository: UserProfileRepository
    private let wardrobeRepository: WardrobeRepository
    private let statisticsUseCase: ComputeWardrobeStatisticsUseCase
    private let settings: AppSettingsProviding
    private let notifications: NotificationScheduling
    let imageStorage: ImageStorage
    private let analytics: AnalyticsTracking
    private let signOutAction: () -> Void

    init(container: AppContainer) {
        self.profileRepository = container.profileRepository
        self.wardrobeRepository = container.wardrobeRepository
        self.statisticsUseCase = container.statisticsUseCase
        self.settings = container.settings
        self.notifications = container.notificationScheduler
        self.imageStorage = container.imageStorage
        self.analytics = container.analytics
        self.signOutAction = { container.signOut() }
        self.authUser = container.currentAuthUser
    }

    var laundryCount: Int { laundryItems.count }
    var favoritesCount: Int { favoriteItems.count }

    var usesCelsius: Bool {
        get { settings.usesCelsius }
        set {
            objectWillChange.send()
            settings.usesCelsius = newValue
        }
    }

    var appearanceMode: AppAppearanceMode {
        get { AppAppearanceMode.from(stored: settings.appearanceMode) }
        set {
            objectWillChange.send()
            settings.appearanceMode = newValue.rawValue
            UserDefaults.standard.set(newValue.rawValue, forKey: "appearanceMode")
        }
    }

    var dailyOutfitReminderEnabled: Bool {
        get { settings.dailyOutfitReminderEnabled }
        set {
            objectWillChange.send()
            settings.dailyOutfitReminderEnabled = newValue
            Task { await applyReminderSetting(enabled: newValue) }
        }
    }

    var dailyOutfitReminderHour: Int {
        get { settings.dailyOutfitReminderHour }
        set {
            objectWillChange.send()
            settings.dailyOutfitReminderHour = newValue
            if settings.dailyOutfitReminderEnabled {
                Task { await applyReminderSetting(enabled: true) }
            }
        }
    }

    var selectedLanguage: String {
        get { settings.selectedLanguage }
        set {
            objectWillChange.send()
            settings.selectedLanguage = newValue
            UserDefaults.standard.set(newValue, forKey: "selectedLanguage")
        }
    }

    private func applyReminderSetting(enabled: Bool) async {
        if enabled {
            let allowed = await notifications.requestAuthorization()
            guard allowed else {
                settings.dailyOutfitReminderEnabled = false
                objectWillChange.send()
                return
            }
            var components = DateComponents()
            components.hour = settings.dailyOutfitReminderHour
            components.minute = 0
            try? await notifications.scheduleDailyOutfitReminder(at: components)
        } else {
            await notifications.cancelDailyOutfitReminder()
        }
    }

    var languageDisplayName: String {
        switch selectedLanguage {
        case "it": return "Italiano"
        default: return "English"
        }
    }

    var weatherUnitLabel: String {
        usesCelsius
            ? NSLocalizedString("Celsius (°C)", comment: "Weather unit")
            : NSLocalizedString("Fahrenheit (°F)", comment: "Weather unit")
    }

    var appVersionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var shareAppItems: [Any] {
        let text = NSLocalizedString(
            "Nook: Private wardrobe — manage your closet and pick outfits privately.",
            comment: "Share app message"
        )
        // App Store page when published; marketing site fallback meanwhile.
        if let url = URL(string: "https://apps.apple.com/app/id0000000000") {
            return [text, url]
        }
        return [text]
    }

    func load() async {
        analytics.track(.screenView, parameters: ["screen_name": "profile"])
        do {
            profile = try await profileRepository.load()
            profile.genderNeutralPreferred = false
            if let authName = authUser?.displayName, profile.displayName == UserProfile.default.displayName {
                profile.displayName = authName
            }
            let items = try await wardrobeRepository.fetchAll()
            statistics = statisticsUseCase.execute(items: items)
            laundryItems = items
                .filter(\.isInLaundry)
                .sorted { $0.updatedAt > $1.updatedAt }
            favoriteItems = items
                .filter(\.isFavorite)
                .sorted { $0.updatedAt > $1.updatedAt }
            if let path = profile.avatarImagePath {
                avatarImage = UIImage(data: (try? await imageStorage.loadImageData(at: path)) ?? Data())
            }
        } catch {
            // Keep defaults.
        }
    }

    func markWashed(_ item: WardrobeItem) async {
        var updated = item
        updated.isInLaundry = false
        updated.updatedAt = Date()
        do {
            try await wardrobeRepository.save(updated)
            laundryItems.removeAll { $0.id == item.id }
            let items = try await wardrobeRepository.fetchAll()
            statistics = statisticsUseCase.execute(items: items)
        } catch {
            // Keep current list; refresh on next load.
        }
    }

    func markAllWashed() async {
        let pending = laundryItems
        guard !pending.isEmpty else { return }
        do {
            for item in pending {
                var updated = item
                updated.isInLaundry = false
                updated.updatedAt = Date()
                try await wardrobeRepository.save(updated)
            }
            laundryItems = []
            let items = try await wardrobeRepository.fetchAll()
            statistics = statisticsUseCase.execute(items: items)
        } catch {
            await load()
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

    func exportMyData() async {
        exportErrorMessage = nil
        do {
            let items = try await wardrobeRepository.fetchAll()
            let payload = ProfileDataExport(
                exportedAt: ISO8601DateFormatter().string(from: Date()),
                profile: ExportProfileSnapshot(
                    displayName: profile.displayName,
                    preferredLanguage: profile.preferredLanguage,
                    usesCelsius: settings.usesCelsius
                ),
                wardrobe: items.map { ExportWardrobeSnapshot(from: $0) }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("nook-export-\(Int(Date().timeIntervalSince1970)).json")
            try data.write(to: url, options: .atomic)
            exportShareURL = url
            showExportShare = true
            analytics.track(.profileUpdated, parameters: ["action": "export_data"])
        } catch {
            exportErrorMessage = NSLocalizedString(
                "Couldn’t export your data. Try again.",
                comment: "Export failure"
            )
        }
    }
}

// MARK: - Export models

private struct ProfileDataExport: Encodable {
    var exportedAt: String
    var profile: ExportProfileSnapshot
    var wardrobe: [ExportWardrobeSnapshot]
}

private struct ExportProfileSnapshot: Encodable {
    var displayName: String
    var preferredLanguage: String
    var usesCelsius: Bool
}

private struct ExportWardrobeSnapshot: Encodable {
    var id: String
    var name: String
    var category: String
    var subcategory: String?
    var material: String
    var isFavorite: Bool
    var isInLaundry: Bool
    var wornCount: Int
    var notes: String?

    init(from item: WardrobeItem) {
        id = item.id.uuidString
        name = item.name
        category = item.category.rawValue
        subcategory = item.subcategory
        material = item.material.rawValue
        isFavorite = item.isFavorite
        isInLaundry = item.isInLaundry
        wornCount = item.wornCount
        notes = item.notes
    }
}

struct ProfileFeatureView: View {
    @StateObject private var viewModel: ProfileViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @Binding var didFinishOnboarding: Bool
    @Environment(\.requestReview) private var requestReview

    init(container: AppContainer, didFinishOnboarding: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(container: container))
        _didFinishOnboarding = didFinishOnboarding
    }

    var body: some View {
        NavigationStack {
            List {
                profileSection
                preferencesSection
                legalSection
                aboutSection
                logOutSection
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
                    bodyText: privacyPolicyText,
                    dismiss: { viewModel.showPrivacy = false }
                )
            }
            .sheet(isPresented: $viewModel.showTerms) {
                infoSheet(
                    title: NSLocalizedString("Terms of Use", comment: ""),
                    bodyText: termsOfUseText,
                    dismiss: { viewModel.showTerms = false }
                )
            }
            .sheet(isPresented: $viewModel.showAbout) {
                infoSheet(
                    title: NSLocalizedString("About Us", comment: ""),
                    bodyText: aboutUsText,
                    dismiss: { viewModel.showAbout = false }
                )
            }
            .sheet(isPresented: $viewModel.showFavorites) {
                favoritesSheet
            }
            .sheet(isPresented: $viewModel.showNeeds) {
                needsSheet
            }
            .sheet(isPresented: $viewModel.showExportShare) {
                if let url = viewModel.exportShareURL {
                    ProfileActivityView(activityItems: [url])
                }
            }
            .sheet(isPresented: $viewModel.showShareApp) {
                ProfileActivityView(activityItems: viewModel.shareAppItems)
            }
            .alert(NSLocalizedString("Log Out", comment: ""), isPresented: $viewModel.showSignOutAlert) {
                Button(NSLocalizedString("Log Out", comment: ""), role: .destructive) {
                    viewModel.signOut()
                }
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("Are you sure you want to log out?", comment: ""))
            }
            .alert(
                NSLocalizedString("Mark all washed?", comment: ""),
                isPresented: $viewModel.showMarkAllWashedAlert
            ) {
                Button(NSLocalizedString("Mark all washed", comment: "")) {
                    Task { await viewModel.markAllWashed() }
                }
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString(
                    "This clears the need-to-wash mark on every piece in laundry.",
                    comment: "Confirm mark all laundry washed"
                ))
            }
            .alert(
                NSLocalizedString("Export", comment: ""),
                isPresented: Binding(
                    get: { viewModel.exportErrorMessage != nil },
                    set: { if !$0 { viewModel.exportErrorMessage = nil } }
                )
            ) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) {
                    viewModel.exportErrorMessage = nil
                }
            } message: {
                Text(viewModel.exportErrorMessage ?? "")
            }
            .refreshable { await viewModel.load() }
        }
    }

    // MARK: - Sections

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

            disclosureValueButton(
                title: NSLocalizedString("Favorites", comment: ""),
                value: "\(viewModel.favoritesCount)",
                systemImage: "heart"
            ) {
                viewModel.showFavorites = true
            }

            disclosureValueButton(
                title: NSLocalizedString("Needs", comment: "Laundry / needs wash"),
                value: "\(viewModel.laundryCount)",
                systemImage: "washer"
            ) {
                viewModel.showNeeds = true
            }
        } header: {
            Text(NSLocalizedString("Profile", comment: ""))
        }
    }

    private var preferencesSection: some View {
        Section {
            Button {
                viewModel.showLanguage = true
            } label: {
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
                get: { viewModel.dailyOutfitReminderEnabled },
                set: { viewModel.dailyOutfitReminderEnabled = $0 }
            )) {
                Label(NSLocalizedString("Notifications", comment: ""), systemImage: "bell")
            }

            if viewModel.dailyOutfitReminderEnabled {
                Picker(
                    NSLocalizedString("Reminder time", comment: ""),
                    selection: Binding(
                        get: { viewModel.dailyOutfitReminderHour },
                        set: { viewModel.dailyOutfitReminderHour = $0 }
                    )
                ) {
                    ForEach([7, 8, 9, 10, 12, 18], id: \.self) { hour in
                        let period = hour >= 12 ? "PM" : "AM"
                        let display = hour % 12 == 0 ? 12 : hour % 12
                        Text("\(display):00 \(period)").tag(hour)
                    }
                }
            }

            Picker(
                selection: Binding(
                    get: { viewModel.usesCelsius },
                    set: { viewModel.usesCelsius = $0 }
                )
            ) {
                Text(NSLocalizedString("Celsius (°C)", comment: "")).tag(true)
                Text(NSLocalizedString("Fahrenheit (°F)", comment: "")).tag(false)
            } label: {
                Label(NSLocalizedString("Weather degree", comment: ""), systemImage: "thermometer.medium")
            }

            Picker(
                selection: Binding(
                    get: { viewModel.appearanceMode },
                    set: { viewModel.appearanceMode = $0 }
                )
            ) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            } label: {
                Label(NSLocalizedString("Theme", comment: ""), systemImage: "circle.lefthalf.filled")
            }
        } header: {
            Text(NSLocalizedString("Preferences", comment: ""))
        } footer: {
            Text(NSLocalizedString(
                "Notifications nudge you to check today’s outfit, events, or laundry.",
                comment: "Preferences footer"
            ))
        }
    }

    private var legalSection: some View {
        Section {
            disclosureButton(
                title: NSLocalizedString("Privacy Policy", comment: ""),
                systemImage: "lock.shield"
            ) {
                viewModel.showPrivacy = true
            }
            disclosureButton(
                title: NSLocalizedString("Terms of Use", comment: ""),
                systemImage: "doc.text"
            ) {
                viewModel.showTerms = true
            }
            disclosureButton(
                title: NSLocalizedString("Export my data", comment: ""),
                systemImage: "square.and.arrow.up.on.square"
            ) {
                Task { await viewModel.exportMyData() }
            }
        } header: {
            Text(NSLocalizedString("Legal", comment: ""))
        }
    }

    private var aboutSection: some View {
        Section {
            disclosureButton(
                title: NSLocalizedString("Rate us", comment: ""),
                systemImage: "star"
            ) {
                requestReview()
            }
            disclosureButton(
                title: NSLocalizedString("About Us", comment: ""),
                systemImage: "info.circle"
            ) {
                viewModel.showAbout = true
            }
            disclosureButton(
                title: NSLocalizedString("Share", comment: ""),
                systemImage: "square.and.arrow.up"
            ) {
                viewModel.showShareApp = true
            }
        } header: {
            Text(NSLocalizedString("About", comment: ""))
        } footer: {
            Text(
                String(
                    format: NSLocalizedString("Version %@", comment: "App version footer"),
                    viewModel.appVersionLabel
                )
            )
            .font(.caption2)
        }
    }

    private var logOutSection: some View {
        Section {
            Button(role: .destructive) {
                viewModel.showSignOutAlert = true
            } label: {
                Text(NSLocalizedString("Log Out", comment: ""))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Rows

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

    private func disclosureValueButton(
        title: String,
        value: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Copy

    private var privacyPolicyText: String {
        "Nook stores your account and wardrobe securely in your cloud project. Photos you add are processed on this device to remove backgrounds and suggest clothing details, then saved to your account storage. Anonymous usage events help improve the app. Location is used only while Nook is open to show local weather for outfit ideas — never for ads."
    }

    private var termsOfUseText: String {
        "Nook: Private wardrobe is provided for personal, non-commercial use. You are responsible for the photos and content you add. Do not upload images you do not have rights to. Outfit suggestions are informational and may be imperfect. We may update these terms; continued use means you accept the current version. Nook is not a marketplace or public social network."
    }

    private var aboutUsText: String {
        "Nook: Private wardrobe helps you manage your closet and choose modest, practical outfits. Add clothes from photos, organize what you own, and get ideas that match the weather — without a public social feed."
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

    private var favoritesSheet: some View {
        NavigationStack {
            List {
                if viewModel.favoriteItems.isEmpty {
                    Text(NSLocalizedString(
                        "No favorites yet. Heart pieces in your wardrobe to see them here.",
                        comment: "Empty favorites"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.favoriteItems) { item in
                        HStack(spacing: 12) {
                            ProfileLaundryThumb(item: item, storage: viewModel.imageStorage)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.body)
                                    .lineLimit(1)
                                Text(item.category.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("Favorites", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Close", comment: "")) {
                        viewModel.showFavorites = false
                    }
                }
            }
        }
    }

    private var needsSheet: some View {
        NavigationStack {
            List {
                if viewModel.laundryItems.isEmpty {
                    Text(NSLocalizedString(
                        "Nothing needs a wash. Mark pieces from the calendar when they do.",
                        comment: "Empty needs"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.laundryItems) { item in
                        HStack(spacing: 12) {
                            ProfileLaundryThumb(item: item, storage: viewModel.imageStorage)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.body)
                                    .lineLimit(1)
                                Text(item.category.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button {
                                Task { await viewModel.markWashed(item) }
                            } label: {
                                Text(NSLocalizedString("Washed", comment: ""))
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(AppColors.olive)
                        }
                        .padding(.vertical, 2)
                    }

                    Button {
                        viewModel.showMarkAllWashedAlert = true
                    } label: {
                        Label(
                            NSLocalizedString("Mark all washed", comment: ""),
                            systemImage: "checkmark.circle"
                        )
                    }
                    .tint(AppColors.olive)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("Needs", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Close", comment: "")) {
                        viewModel.showNeeds = false
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

    private func infoSheet(title: String, bodyText: String, dismiss: @escaping () -> Void) -> some View {
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
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Share sheet

private struct ProfileActivityView: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct ProfileLaundryThumb: View {
    let item: WardrobeItem
    let storage: ImageStorage
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.secondarySystemFill)
                    .overlay {
                        Image(systemName: "tshirt")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: item.id) {
            let path = item.transparentImagePath ?? item.originalImagePath
            guard !path.isEmpty else { return }
            image = UIImage(data: (try? await storage.loadImageData(at: path)) ?? Data())
        }
    }
}
