import SwiftUI
import CloudKit
import UIKit
import AuthenticationServices

// Add this struct before the ProfileView struct
struct WeatherData: Codable {
    let main: MainWeather
    let weather: [Weather]
    
    struct MainWeather: Codable {
        let temp: Double
        let feels_like: Double
        let humidity: Int
    }
    
    struct Weather: Codable {
        let main: String
        let description: String
        let icon: String
    }
}

struct ProfileView: View {
    @Binding var showClearAlert: Bool
    @Binding var showResetOnboardingAlert: Bool
    var clearAllData: () -> Void
    var resetOnboarding: () -> Void

    @State private var userProfileName: String = ""
    @State private var userProfileLocation: String = ""
    @State private var isLoading = true
    @State private var iCloudAvailable = true
    @State private var showSettingsSheet = false
    @State private var appleName: String? = nil
    @State private var isAppleSignedIn = false
    @State private var signInErrorMessage: String? = nil
    let profileImage: Image = Image(systemName: "person.crop.circle.fill")

    @State private var showLanguageSheet = false
    @State private var showPrivacyPolicy = false
    @State private var showAboutUs = false
    @State private var showShareSheet = false
    @State private var showLogoutAlert = false
    @State private var showTemperatureSheet = false
    @AppStorage("selectedTemperatureUnit") private var selectedTemperatureUnit = "Celsius"
    @State private var currentTemperature: Double = 20.0 // Example temperature in Celsius

    @State private var profileImageScale: CGFloat = 0.8
    @AppStorage("selectedLanguage") private var selectedLanguage: String = Locale.current.language.languageCode?.identifier ?? "en"

    @State private var isEditingProfile = false
    @State private var showingImagePicker = false
    @State private var profileUIImage: UIImage?
    @State private var tempUserName: String = ""
    @State private var tempUserLocation: String = ""

    @State private var weatherData: WeatherData?
    @State private var isLoadingWeather = false
    @State private var weatherError: String?

    @StateObject private var calendar = CalendarManager()

    private let temperatureUnits = ["Celsius", "Fahrenheit"]

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.95, green: 0.95, blue: 1.0),
                        Color(red: 1.0, green: 0.95, blue: 0.98)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Profile header
                        profileHeader
                        
                        // Stats section
                        statsSection
                        
                        // Settings section
                        settingsSection
                        
                        // Browser card section
                        browserCardSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $isEditingProfile) {
                editProfileSheet
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $profileUIImage)
            }
            .sheet(isPresented: $showLanguageSheet) {
                languageSelectionSheet
            }
            .sheet(isPresented: $showSettingsSheet) {
                iCloudSettingsSheet
            }
            .sheet(isPresented: $showPrivacyPolicy) {
                privacyPolicySheet
            }
            .sheet(isPresented: $showAboutUs) {
                aboutUsSheet
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityView(activityItems: [URL(string: "https://yourapp.com")!])
            }
            .sheet(isPresented: $showTemperatureSheet) {
                temperatureSettingsSheet
            }
            .alert("Are you sure you want to log out?", isPresented: $showLogoutAlert) {
                Button("Log Out", role: .destructive) {
                    // Add your logout logic here
                }
                Button("Cancel", role: .cancel) {}
            }
            .task {
                // Here you would typically fetch the current temperature from a weather API
                // For now, we're using a static value
                currentTemperature = 20.0
            }
        }
        .onAppear {
            checkiCloudStatus()
            if let savedName = UserDefaults.standard.string(forKey: "appleUserName") {
                print("onAppear loaded Apple name from UserDefaults: \(savedName)")
                self.appleName = savedName
                self.isAppleSignedIn = true
            }
        }
    }
    
    private var profileHeader: some View {
        VStack(spacing: 20) {
            // Profile image
            ZStack {
                if let image = profileUIImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.purple, .pink]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                        )
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 120, height: 120)
                        .overlay(
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.purple.opacity(0.8))
                        )
                }
                
                Button(action: { showingImagePicker = true }) {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.purple)
                        )
                }
                .offset(x: 40, y: 40)
            }
            
            // User info
            VStack(spacing: 8) {
                Text(userProfileName.isEmpty ? "Add Your Name" : userProfileName)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if !userProfileLocation.isEmpty {
                    HStack {
                        Image(systemName: "location.fill")
                            .font(.caption)
                        Text(userProfileLocation)
                            .font(.subheadline)
                    }
                    .foregroundColor(.secondary)
                }
            }
            
            Button(action: { isEditingProfile = true }) {
                Text("Edit Profile")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.purple, .pink]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
    
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Style Stats")
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack(spacing: 16) {
                StatCard(
                    title: "Outfits",
                    value: "24",
                    icon: "tshirt.fill",
                    color: .purple
                )
                
                StatCard(
                    title: "Favorites",
                    value: "12",
                    icon: "heart.fill",
                    color: .pink
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "bell.fill",
                    title: "Notifications",
                    subtitle: "",
                    color: .purple
                )
                
                Divider()
                    .padding(.leading, 44)
                
                SettingsRow(
                    icon: "globe",
                    title: "Language",
                    subtitle: selectedLanguage,
                    color: .pink
                )
                .onTapGesture {
                    showLanguageSheet = true
                }
                
                Divider()
                    .padding(.leading, 44)
                
                SettingsRow(
                    icon: "thermometer",
                    title: "Temperature Unit",
                    subtitle: formatTemperature(currentTemperature),
                    color: .orange
                )
                .onTapGesture {
                    showTemperatureSheet = true
                }
                
                Divider()
                    .padding(.leading, 44)
                
                SettingsRow(
                    icon: "lock.shield",
                    title: "Privacy Policy",
                    subtitle: "",
                    color: .blue
                )
                .onTapGesture {
                    showPrivacyPolicy = true
                }
                
                Divider()
                    .padding(.leading, 44)
                
                SettingsRow(
                    icon: "questionmark.circle.fill",
                    title: "Help & Support",
                    subtitle: "",
                    color: .purple
                )
                .onTapGesture {
                    showAboutUs = true
                }
                
                Divider()
                    .padding(.leading, 44)
                
                SettingsRow(
                    icon: "arrow.up.right.square",
                    title: "Share App",
                    subtitle: "",
                    color: .green
                )
                .onTapGesture {
                    showShareSheet = true
                }
                
                Divider()
                    .padding(.leading, 44)
                
                SettingsRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    title: "Log Out",
                    subtitle: "",
                    color: .red
                )
                .onTapGesture {
                    showLogoutAlert = true
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
    
    private var editProfileSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Profile Information")) {
                    TextField("Name", text: $tempUserName)
                    TextField("Location", text: $tempUserLocation)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isEditingProfile = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        userProfileName = tempUserName
                        userProfileLocation = tempUserLocation
                        isEditingProfile = false
                    }
                }
            }
            .onAppear {
                tempUserName = userProfileName
                tempUserLocation = userProfileLocation
            }
        }
    }

    private func checkiCloudStatus() {
        CKContainer.default().accountStatus { status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    self.iCloudAvailable = true
                case .noAccount, .restricted, .couldNotDetermine:
                    self.iCloudAvailable = false
                @unknown default:
                    self.iCloudAvailable = false
                }
            }
        }
    }

    private func fetchUserName() {
        let container = CKContainer.default()
        container.fetchUserRecordID { recordID, error in
            guard let recordID = recordID, error == nil else {
                DispatchQueue.main.async {
                    self.userProfileName = ""
                    self.isLoading = false
                }
                return
            }
            container.discoverUserIdentity(withUserRecordID: recordID) { identity, error in
                DispatchQueue.main.async {
                    if let name = identity?.nameComponents?.formatted() {
                        self.userProfileName = name
                    } else {
                        self.userProfileName = ""
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

    private var languageSelectionSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Select Language")
                    .font(.title2)
                    .fontWeight(.bold)
                
                VStack(spacing: 12) {
                    LanguageTile(languageCode: "en", languageName: "English", flag: "🇬🇧", selectedLanguage: $selectedLanguage) {
                        showLanguageSheet = false
                    }
                    LanguageTile(languageCode: "it", languageName: "Italiano", flag: "🇮🇹", selectedLanguage: $selectedLanguage) {
                        showLanguageSheet = false
                    }
                }
                .padding(.top, 8)
                
                Button("Close") {
                    showLanguageSheet = false
                }
                .padding(.top, 16)
            }
            .padding()
        }
    }
    
    private var iCloudSettingsSheet: some View {
        VStack(spacing: 24) {
            Image(systemName: "icloud.slash")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.red)
            
            Text("iCloud Required")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("You must be signed in to iCloud to use your profile. Please sign in to iCloud in Settings.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: openSettings) {
                Text("Open Settings")
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
    
    private var privacyPolicySheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Privacy Policy")
                    .font(.title2)
                    .fontWeight(.bold)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Your Privacy Matters")
                            .font(.headline)
                        
                        Text("We take your privacy seriously. This app collects and stores your outfit data in your personal iCloud account. We do not share your data with third parties.")
                            .font(.body)
                        
                        Text("Data Collection")
                            .font(.headline)
                            .padding(.top)
                        
                        Text("• Outfit images and details\n• Style preferences\n• Calendar entries")
                            .font(.body)
                        
                        Text("Data Storage")
                            .font(.headline)
                            .padding(.top)
                        
                        Text("All your data is stored securely in your personal iCloud account. You can delete your data at any time through the app settings.")
                            .font(.body)
                    }
                    .padding()
                }
                
                Button("Close") {
                    showPrivacyPolicy = false
                }
                .padding(.top, 32)
            }
            .padding()
        }
    }
    
    private var aboutUsSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("About Us")
                    .font(.title2)
                    .fontWeight(.bold)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Fashion App")
                            .font(.headline)
                        
                        Text("Version 1.0")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("Our Mission")
                            .font(.headline)
                            .padding(.top)
                        
                        Text("We're dedicated to helping you organize and plan your outfits with style. Our app makes it easy to manage your wardrobe and create perfect outfits for any occasion.")
                            .font(.body)
                        
                        Text("Features")
                            .font(.headline)
                            .padding(.top)
                        
                        Text("• Outfit organization\n• Calendar planning\n• Style suggestions\n• Cloud sync")
                            .font(.body)
                    }
                    .padding()
                }
                
                Button("Close") {
                    showAboutUs = false
                }
                .padding(.top, 32)
            }
            .padding()
        }
    }
    
    private var temperatureSettingsSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Temperature Unit")
                    .font(.title2)
                    .fontWeight(.bold)
                
                // Add temperature preview
                VStack(spacing: 8) {
                    Text("Current Temperature")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text(formatTemperature(currentTemperature))
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.primary)
                }
                .padding(.vertical)
                
                VStack(spacing: 12) {
                    ForEach(["Celsius", "Fahrenheit"], id: \.self) { unit in
                        Button(action: {
                            selectedTemperatureUnit = unit
                            showTemperatureSheet = false
                        }) {
                            HStack {
                                Text(unit)
                                    .font(.headline)
                                Spacer()
                                if selectedTemperatureUnit == unit {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                        }
                    }
                }
                .padding(.top, 8)
                
                Button("Close") {
                    showTemperatureSheet = false
                }
                .padding(.top, 16)
            }
            .padding()
        }
    }
    
    private func convertTemperature(_ fahrenheit: Double) -> Double {
        return (fahrenheit - 32) * 5/9
    }
    
    private func formatTemperature(_ temperature: Double) -> String {
        if selectedTemperatureUnit == "Celsius" {
            return String(format: "%.1f°C", temperature)
        } else {
            let fahrenheit = (temperature * 9/5) + 32
            return String(format: "%.1f°F", fahrenheit)
        }
    }
    
    private func fetchWeatherData() {
        isLoadingWeather = true
        weatherError = nil
        
        // Replace with your actual API key and location
        let apiKey = "YOUR_API_KEY"
        let location = "London" // You can make this dynamic based on user's location
        
        guard let url = URL(string: "https://api.openweathermap.org/data/2.5/weather?q=\(location)&appid=\(apiKey)&units=imperial") else {
            weatherError = "Invalid URL"
            isLoadingWeather = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isLoadingWeather = false
                
                if let error = error {
                    weatherError = error.localizedDescription
                    return
                }
                
                guard let data = data else {
                    weatherError = "No data received"
                    return
                }
                
                do {
                    let decoder = JSONDecoder()
                    self.weatherData = try decoder.decode(WeatherData.self, from: data)
                } catch {
                    weatherError = "Failed to decode weather data"
                }
            }
        }.resume()
    }
    
    private var browserCardSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                // Weather Card
                BrowserCard(
                    title: "Today's Weather",
                    icon: weatherData?.weather.first?.icon ?? "sun.max.fill",
                    color: .orange,
                    temperature: weatherData.map { formatTemperature($0.main.temp) } ?? "Loading...",
                    subtitle: weatherData?.weather.first?.description.capitalized ?? "Fetching weather...",
                    isLoading: isLoadingWeather
                )
                
                // Outfit Suggestions Card
                BrowserCard(
                    title: "Outfit Suggestions",
                    icon: "tshirt.fill",
                    color: .blue,
                    temperature: weatherData.map { formatTemperature($0.main.feels_like) } ?? "Loading...",
                    subtitle: "Based on current weather",
                    isLoading: isLoadingWeather
                )
                
                // Style Trends Card
                BrowserCard(
                    title: "Style Trends",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .purple,
                    temperature: "Trending",
                    subtitle: "Popular this season",
                    isLoading: false
                )
                
                // Humidity Card
                BrowserCard(
                    title: "Humidity",
                    icon: "humidity.fill",
                    color: .cyan,
                    temperature: "\(weatherData?.main.humidity ?? 0)%",
                    subtitle: "Current humidity",
                    isLoading: isLoadingWeather
                )
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .task {
            fetchWeatherData()
        }
    }

    private var calendarSection: some View {
        VStack(spacing: 16) {
            // Month navigation
            HStack {
                Button(action: { calendar.moveToPreviousMonth() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Text(calendar.formatMonthYear())
                    .font(.headline)
                
                Spacer()
                
                Button(action: { calendar.moveToNextMonth() }) {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal)
            
            // Weekday headers
            HStack {
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            
            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(calendar.datesInMonth, id: \.id) { item in
                    if let date = item.date {
                        DayCell(
                            date: date,
                            isSelected: calendar.isDateSelected(date),
                            hasOutfit: calendar.isDateInRange(date)
                        )
                        .onTapGesture {
                            calendar.selectDate(date)
                        }
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            .padding(.horizontal)
        }
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
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: {
            selectedLanguage = languageCode
            onSelect()
        }) {
            HStack {
                Text(flag)
                    .font(.title)
                Text(languageName)
                    .font(.headline)
                Spacer()
                if selectedLanguage == languageCode {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedLanguage == languageCode ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding()
        .contentShape(Rectangle())
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) private var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.editedImage] as? UIImage {
                parent.image = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

struct BrowserCard: View {
    let title: String
    let icon: String
    let color: Color
    let temperature: String
    let subtitle: String
    let isLoading: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text(temperature)
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 160)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView(showClearAlert: .constant(false), showResetOnboardingAlert: .constant(false), clearAllData: {}, resetOnboarding: {})
    }
}

// Update the CalendarManager class
class CalendarManager: ObservableObject {
    @Published var selectedDate: Date
    @Published var selectedDateRange: ClosedRange<Date>?
    @Published var datesInMonth: [(id: Int, date: Date?)]
    @Published var currentMonth: Date
    
    init() {
        self.selectedDate = Date()
        self.currentMonth = Date()
        self.datesInMonth = []
        updateDatesInMonth()
    }
    
    func updateDatesInMonth() {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: currentMonth)!
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let offsetDays = firstWeekday - calendar.firstWeekday
        
        var dates: [(id: Int, date: Date?)] = []
        var currentId = 0
        
        // Add empty cells for offset
        for _ in 0..<offsetDays {
            dates.append((id: currentId, date: nil))
            currentId += 1
        }
        
        // Add dates for the month
        var currentDate = interval.start
        while currentDate < interval.end {
            dates.append((id: currentId, date: currentDate))
            currentId += 1
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        // Pad the remaining days to complete the last week
        while dates.count % 7 != 0 {
            dates.append((id: currentId, date: nil))
            currentId += 1
        }
        
        self.datesInMonth = dates
    }
    
    func isDateSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }
    
    func isDateInRange(_ date: Date) -> Bool {
        guard let range = selectedDateRange else { return false }
        return range.contains(date)
    }
    
    func selectDate(_ date: Date) {
        selectedDate = date
        if selectedDateRange == nil {
            selectedDateRange = date...date
        } else {
            let calendar = Calendar.current
            if let startDate = selectedDateRange?.lowerBound {
                if date < startDate {
                    selectedDateRange = date...startDate
                } else {
                    selectedDateRange = startDate...date
                }
            }
        }
    }
    
    func moveToNextMonth() {
        if let newMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = newMonth
            updateDatesInMonth()
        }
    }
    
    func moveToPreviousMonth() {
        if let newMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = newMonth
            updateDatesInMonth()
        }
    }
    
    func formatMonthYear() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }
}
