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
    @AppStorage("selectedLanguage") private var selectedLanguage: String = Locale.current.languageCode ?? "en"

    var body: some Scene {
        WindowGroup {
            RootView(selectedLanguage: selectedLanguage)
                .preferredColorScheme(.light)
        }
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
                        Text(NSLocalizedString("iCloud Required", comment: ""))
                            .font(.title2)
                            .fontWeight(.bold)
                        if let error = error {
                            Text(error.localizedDescription)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Text(NSLocalizedString("You must be signed in to iCloud to use your profile. Please sign in to iCloud in Settings.", comment: ""))
                                .foregroundColor(.secondary)
                        }
                        Button(NSLocalizedString("Retry", comment: "")) {
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
