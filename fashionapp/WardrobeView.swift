import SwiftUI
import CloudKit

struct WardrobeView: View {
    @StateObject private var manager = OutfitCloudKitManager.shared
    @State private var hasAppeared = false
    @State private var isSettingUpSchema = false
    @State private var isRefreshing = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]

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
                        if manager.isLoading && !hasAppeared {
                            loadingView
                        } else if let error = manager.error {
                            errorView(error)
                        } else if manager.outfits.isEmpty {
                            emptyStateView
                        } else {
                            outfitGrid
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
                .refreshable {
                    await refreshOutfits()
                }
            }
            .navigationTitle("Wardrobe")
        }
        .onAppear {
            if !hasAppeared {
                print("WardrobeView initial load - fetching outfits...")
                manager.fetchOutfits()
                hasAppeared = true
            } else {
                print("WardrobeView reappeared - using cached outfits (\(manager.outfits.count))")
            }
            
            // Debug state after appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("🔄 Post-appear state check:")
                print("  - isLoading: \(manager.isLoading)")
                print("  - outfits.count: \(manager.outfits.count)")
                print("  - Should show grid: \(!manager.outfits.isEmpty && !manager.isLoading)")
            }
        }
    }
    
    private var outfitGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(manager.outfits) { outfit in
                OutfitCard(outfit: outfit)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: manager.outfits.count)
    }
    
    private func refreshOutfits() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        manager.fetchOutfits()
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        isRefreshing = false
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            // Animated loading rings
            ZStack {
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.purple.opacity(0.6),
                                    Color.pink.opacity(0.6)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 60 + CGFloat(index * 20),
                               height: 60 + CGFloat(index * 20))
                        .rotationEffect(.degrees(manager.isLoading ? 360 : 0))
                        .animation(
                            Animation.linear(duration: 1.5)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.2),
                            value: manager.isLoading
                        )
                }
            }
            
            Text("Loading your wardrobe...")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.purple.opacity(0.8))
        }
    }
    
    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Error Loading Wardrobe")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(error.localizedDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: {
                manager.fetchOutfits()
            }) {
                Text("Try Again")
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
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 25) {
            // Decorative circles
            ZStack {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.purple.opacity(0.1),
                                    Color.pink.opacity(0.1)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100 + CGFloat(index * 50),
                               height: 100 + CGFloat(index * 50))
                        .offset(x: CGFloat(index * 20),
                               y: CGFloat(index * -10))
                }
            }
            
            Image(systemName: "tshirt.fill")
                .font(.system(size: 60))
                .foregroundColor(.purple.opacity(0.8))
            
            Text("Your Wardrobe is Empty")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add your first outfit to get started")
                .font(.body)
                .foregroundColor(.secondary)
            
            NavigationLink(destination: AddOutfitView()) {
                Text("Add Outfit")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.purple, .pink]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
            }
        }
    }
} 