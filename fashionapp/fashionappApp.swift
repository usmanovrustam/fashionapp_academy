//
//  fashionappApp.swift
//  fashionapp
//
//  Created by Rustam Usmanov on 22/05/25.
//

import SwiftUI
import CloudKit

@main
struct fashionappApp: App {
    @StateObject private var authManager = iCloudAuthManager()
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    @AppStorage("selectedTheme") private var selectedTheme: String = "system"
    @AppStorage("selectedLanguage") private var selectedLanguage: String = Locale.current.languageCode ?? "en"

    var body: some Scene {
        WindowGroup {
            RootView(selectedLanguage: selectedLanguage)
                .onAppear {
                    applyTheme(selectedTheme)
                }
                .onChange(of: selectedTheme) { newValue in
                    applyTheme(newValue)
                }
        }
    }
}

private func applyTheme(_ theme: String) {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let window = windowScene.windows.first else { return }
    switch theme {
    case "light": window.overrideUserInterfaceStyle = .light
    case "dark": window.overrideUserInterfaceStyle = .dark
    default: window.overrideUserInterfaceStyle = .unspecified
    }
}

struct RootView: View {
    @StateObject private var authManager = iCloudAuthManager()
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    let selectedLanguage: String
    var body: some View {
        let locale = Locale(identifier: selectedLanguage)
        if !didFinishOnboarding {
            SplashView(didFinishOnboarding: $didFinishOnboarding)
                .environment(\.locale, locale)
        } else {
            Group {
                switch authManager.state {
                case .unknown, .checking:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground))
                case .available:
                    MainTabBarView()
                        .environment(\.locale, locale)
                case .unavailable(let error):
                    VStack(spacing: 16) {
                        Image(systemName: "icloud.slash")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .foregroundColor(.red)
                        Text("iCloud Required")
                            .font(.title2)
                            .fontWeight(.bold)
                        if let error = error {
                            Text(error.localizedDescription)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("Please sign in to iCloud to use this app.")
                                .foregroundColor(.secondary)
                        }
                        Button("Retry") {
                            authManager.checkiCloudStatus()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                }
            }
        }
    }
}
