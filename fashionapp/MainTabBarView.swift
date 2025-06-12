import SwiftUI
import CloudKit
import PhotosUI

struct MainTabBarView: View {
    @State private var selectedTab = 0
    @State private var showClearAlert = false
    @State private var showResetOnboardingAlert = false

    var body: some View {
        TabView(selection: $selectedTab) {
            BrowseView()
                .tabItem {
                    Image(systemName: "safari")
                    Text(NSLocalizedString("Discover", comment: ""))
                }
                .tag(0)
            AddOutfitView()
                .tabItem {
                    Image(systemName: "plus.circle")
                    Text(NSLocalizedString("Add", comment: ""))
                }
                .tag(1)
            WardrobeView()
                .tabItem {
                    Image(systemName: "tshirt.fill")
                    Text(NSLocalizedString("Wardrobe", comment: ""))
                }
                .tag(2)
            CalendarView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text(NSLocalizedString("Calendar", comment: ""))
                }
                .tag(3)
            ProfileView(
                showClearAlert: $showClearAlert,
                showResetOnboardingAlert: $showResetOnboardingAlert,
                clearAllData: clearAllData,
                resetOnboarding: resetOnboarding
            )
            .tabItem {
                Image(systemName: "person")
                Text(NSLocalizedString("Profile", comment: ""))
            }
            .tag(4)
        }
        .alert(NSLocalizedString("Clear All Data?", comment: ""), isPresented: $showClearAlert) {
            Button(NSLocalizedString("Delete", comment: ""), role: .destructive) { clearAllData() }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("This will remove all app data. This action cannot be undone.", comment: ""))
        }
        .alert(NSLocalizedString("Reset Onboarding?", comment: ""), isPresented: $showResetOnboardingAlert) {
            Button(NSLocalizedString("Reset", comment: ""), role: .destructive) { resetOnboarding() }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("You will see the onboarding screens again on next launch.", comment: ""))
        }
    }

    private func clearAllData() {
        if let appDomain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: appDomain)
        }
        let privateDB = CKContainer.default().privateCloudDatabase
        let query = CKQuery(recordType: "_defaultZone", predicate: NSPredicate(value: true))
        privateDB.perform(query, inZoneWith: nil) { records, error in
            guard let records = records, error == nil else { return }
            let ops = records.map { CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [$0.recordID]) }
            ops.forEach { privateDB.add($0) }
        }
    }

    private func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: "didFinishOnboarding")
    }
} 