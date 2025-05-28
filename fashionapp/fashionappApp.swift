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

    var body: some Scene {
        WindowGroup {
            if !didFinishOnboarding {
                SplashView(didFinishOnboarding: $didFinishOnboarding)
            } else {
                Group {
                    switch authManager.state {
                    case .unknown, .checking:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemBackground))
                    case .available:
                        MainTabBarView()
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
}
