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
                    Text("Discover")
                }
                .tag(0)
            WardrobeView(onAddOutfit: { selectedTab = 2 })
                .tabItem {
                    Image(systemName: "tshirt")
                    Text("Wardrobe")
                }
                .tag(1)
            AddOutfitView()
                .tabItem {
                    Image(systemName: "plus.circle")
                    Text("Add Outfit")
                }
                .tag(2)
            CalendarView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Calendar")
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
                Text("Profile")
            }
            .tag(4)
        }
        .alert("Clear All Data?", isPresented: $showClearAlert) {
            Button("Delete", role: .destructive) { clearAllData() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove all app data. This action cannot be undone.")
        }
        .alert("Reset Onboarding?", isPresented: $showResetOnboardingAlert) {
            Button("Reset", role: .destructive) { resetOnboarding() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You will see the onboarding screens again on next launch.")
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