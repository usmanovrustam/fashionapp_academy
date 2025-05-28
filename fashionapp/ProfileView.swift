import SwiftUI

struct ProfileView: View {
    @Binding var showClearAlert: Bool
    @Binding var showResetOnboardingAlert: Bool
    var clearAllData: () -> Void
    var resetOnboarding: () -> Void

    var body: some View {
        VStack {
            VStack {
                Text("Profile")
                    .font(.title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            Spacer()
            VStack(spacing: 12) {
                Button(role: .destructive) {
                    showClearAlert = true
                } label: {
                    Text("Clear All Data")
                        .foregroundColor(.red)
                }
                Button {
                    showResetOnboardingAlert = true
                } label: {
                    Text("Reset Onboarding")
                        .foregroundColor(.blue)
                }
            }
            .padding(.bottom, 32)
        }
    }
} 