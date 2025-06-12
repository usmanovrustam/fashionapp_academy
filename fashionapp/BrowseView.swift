import SwiftUI

struct BrowseView: View {
    @StateObject private var manager = OutfitCloudKitManager.shared
    @State private var topIndex = 0
    @State private var dragOffset: CGSize = .zero
    @State private var selectedOutfit: Outfit?
    @State private var showOutfitDetail = false
    @State private var isLoading = true
    
    private let cardStackOffset: CGFloat = 12
    private let cardStackScale: CGFloat = 0.04
    private let maxVisibleCards = 3
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.95, green: 0.95, blue: 1.0),
                        Color(red: 1.0, green: 0.95, blue: 0.98)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    WeatherCard()
                        .padding(.horizontal)
                    ZStack {
                        if isLoading {
                            LoadingView()
                        } else if manager.outfits.isEmpty {
                            RefreshCardsView {
                                withAnimation {
                                    isLoading = true
                                    // Simulate loading
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        isLoading = false
                                        // manager.outfits = ... // reload your data here
                                    }
                                }
                            }
                        } else if topIndex < manager.outfits.count {
                            ForEach(Array(manager.outfits.enumerated()), id: \.element.id) { idx, outfit in
                                if idx >= topIndex && idx < topIndex + maxVisibleCards {
                                    TinderCardView(
                                        outfit: outfit,
                                        onNope: { swipeLeft() },
                                        onYeah: { swipeRight() }
                                    )
                                    .offset(y: CGFloat(idx - topIndex) * cardStackOffset)
                                    .scaleEffect(1 - CGFloat(idx - topIndex) * cardStackScale)
                                    .opacity(idx == topIndex ? 1 : 0.9)
                                    .zIndex(Double(manager.outfits.count - idx))
                                    .offset(idx == topIndex ? dragOffset : .zero)
                                    .rotationEffect(.degrees(idx == topIndex ? Double(dragOffset.width / 20) : 0))
                                    .gesture(
                                        idx == topIndex ?
                                        DragGesture()
                                            .onChanged { dragOffset = $0.translation }
                                            .onEnded { value in
                                                if abs(value.translation.width) > 100 {
                                                    if value.translation.width > 0 {
                                                        swipeRight()
                                                    } else {
                                                        swipeLeft()
                                                    }
                                                } else {
                                                    dragOffset = .zero
                                                }
                                            }
                                        : nil
                                    )
                                    .onTapGesture {
                                        if idx == topIndex {
                                            selectedOutfit = outfit
                                            showOutfitDetail = true
                                        }
                                    }
                                    .animation(.spring(), value: dragOffset)
                                }
                            }
                        } else {
                            RefreshCardsView {
                                withAnimation {
                                    topIndex = 0
                                }
                            }
                        }
                    }
                    .frame(height: 500)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Discover")
            .sheet(isPresented: $showOutfitDetail) {
                if let outfit = selectedOutfit {
                    OutfitDetailView(outfit: outfit)
                }
            }
            .onAppear {
                // Simulate loading
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    isLoading = false
                }
            }
        }
    }
    
    private func swipeLeft() {
        withAnimation {
            dragOffset = CGSize(width: -500, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation {
                topIndex += 1
                dragOffset = .zero
            }
        }
    }
    
    private func swipeRight() {
        withAnimation {
            dragOffset = CGSize(width: 500, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation {
                topIndex += 1
                dragOffset = .zero
            }
        }
    }
}

struct TinderCardView: View {
    let outfit: Outfit
    let onNope: () -> Void
    let onYeah: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            if let image = outfit.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(radius: 8, y: 4)
            }
            Text(outfit.name)
                .font(.title2).bold()
                .foregroundColor(.primary)
                .padding(.top, 8)
            Text("Perfect for any occasion")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 24) {
                Button(action: onNope) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Nope")
                    }
                    .font(.headline)
                    .foregroundColor(.purple)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.85))
                    .clipShape(Capsule())
                    .shadow(color: Color.purple.opacity(0.08), radius: 8, y: 2)
                }
                Button(action: onYeah) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Yeah")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.purple, Color.pink]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color.purple.opacity(0.15), radius: 8, y: 2)
                }
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.purple.opacity(0.10), radius: 24, x: 0, y: 12)
        )
        .padding(.horizontal, 8)
    }
}

struct WeatherCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Weather")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("Sunny, 72°F")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white)
            }
            
            Text("Perfect day for your favorite outfit!")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [.purple, .pink]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(
            color: Color.purple.opacity(0.3),
            radius: 15,
            x: 0,
            y: 8
        )
    }
}

struct OutfitDetailView: View {
    let outfit: Outfit
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    if let image = outfit.image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 400)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text(outfit.name)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Perfect for any occasion")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 32) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                .scaleEffect(2)
            Text("Loading outfits…")
                .font(.title2).bold()
                .foregroundColor(.purple)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cornerRadius(32)
        .padding(.horizontal, 24)
        .transition(.opacity.combined(with: .scale))
        .animation(.spring(), value: 1)
    }
}

struct RefreshCardsView: View {
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [Color.purple.opacity(0.15), Color.pink.opacity(0.12)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 120, height: 120)
                Image(systemName: "sparkles")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.purple)
            }
            Text("No more outfits!")
                .font(.title).bold()
                .foregroundColor(.primary)
            Text("Tap below to refresh and see more styles.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onRefresh) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 36)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.purple, Color.pink]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Color.purple.opacity(0.15), radius: 8, y: 2)
            }
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cornerRadius(32)
        .padding(.horizontal, 24)
        .transition(.opacity.combined(with: .scale))
        .animation(.spring(), value: 1)
    }
} 