import SwiftUI

struct BrowseView: View {
    @StateObject private var weatherManager = WeatherManager()
    @Environment(\.scenePhase) private var scenePhase

    // Placeholder outfit data
    @State private var outfits: [OutfitCard] = [
        OutfitCard(image: Image("outfit_placeholder"), title: "Weekend Casual", temperature: "18°C", tag: "Outdoor"),
        OutfitCard(image: Image("outfit_placeholder"), title: "Office Smart", temperature: "21°C", tag: "Indoor"),
        OutfitCard(image: Image("outfit_placeholder"), title: "Evening Chic", temperature: "16°C", tag: "Outdoor")
    ]
    @State private var topCardIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(NSLocalizedString("Wardrobe AI", comment: ""))
                    .font(.title3.bold())
                    .foregroundColor(.primary)
                Spacer()
                Button(action: {}) {
                    Image(systemName: "bell")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            // Weather Card
            Group {
                if let current = weatherManager.currentWeather {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("Current Location", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(weatherManager.locationName)
                                .font(.headline)
                                .foregroundColor(Color.blue)
                            Text("\(Int(current.temperature.value))°C")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(Color.blue)
                            Text(current.condition.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: current.symbolName)
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal)
                    .padding(.top, 16)
                } else if weatherManager.isLoading {
                    HStack {
                        ProgressView()
                        Text(NSLocalizedString("Loading weather...", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 24)
                }
            }
            // Swipeable Outfit Card Stack
            Spacer(minLength: 16)
            ZStack {
                ForEach(Array(outfits.enumerated()), id: \.0) { (index, outfit) in
                    if index >= topCardIndex {
                        SwipeableCardView(
                            outfit: outfit,
                            onRemove: { direction in
                                withAnimation(.spring()) {
                                    topCardIndex += 1
                                }
                            }
                        )
                        .offset(x: CGFloat(index - topCardIndex) * 4, y: CGFloat(index - topCardIndex) * 4)
                        .zIndex(Double(outfits.count - index))
                    }
                }
            }
            .frame(height: 350)
            .padding(.horizontal, 16)
            .padding(.top, 24)
            // Instruction
            Text(NSLocalizedString("Swipe to see more outfits", comment: ""))
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.top, 16)
            Spacer()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            Task { await weatherManager.requestWeather() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await weatherManager.requestWeather() }
            }
        }
    }
}

struct SwipeableCardView: View {
    let outfit: OutfitCard
    var onRemove: (SwipeDirection) -> Void
    @State private var offset: CGSize = .zero
    @GestureState private var isDragging = false
    private let threshold: CGFloat = 100

    var body: some View {
        VStack(spacing: 16) {
            outfit.image
                .resizable()
                .aspectRatio(1, contentMode: .fill)
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(radius: 8, y: 4)
            Text(NSLocalizedString(outfit.title, comment: ""))
                .font(.title3.bold())
                .foregroundColor(.primary)
            HStack(spacing: 8) {
                Label(outfit.temperature, systemImage: "thermometer")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
                    .foregroundColor(.blue)
                Text(NSLocalizedString(outfit.tag, comment: ""))
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(Capsule())
                    .foregroundColor(.gray)
            }
            HStack(spacing: 40) {
                Button(action: { swipe(.left) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.red.opacity(0.7))
                }
                Button(action: { swipe(.right) }) {
                    Image(systemName: "heart.circle")
                        .font(.system(size: 44))
                        .foregroundColor(.blue)
                        .overlay(Circle().stroke(Color.blue, lineWidth: 2).frame(width: 56, height: 56))
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
        .offset(x: offset.width, y: offset.height)
        .rotationEffect(.degrees(Double(offset.width / 20)))
        .gesture(
            DragGesture()
                .updating($isDragging) { value, state, _ in
                    state = true
                }
                .onChanged { value in
                    offset = value.translation
                }
                .onEnded { value in
                    if value.translation.width > threshold {
                        swipe(.right)
                    } else if value.translation.width < -threshold {
                        swipe(.left)
                    } else {
                        withAnimation(.spring()) {
                            offset = .zero
                        }
                    }
                }
        )
        .animation(.spring(), value: offset)
    }

    private func swipe(_ direction: SwipeDirection) {
        withAnimation(.spring()) {
            offset = CGSize(width: direction == .right ? 1000 : -1000, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onRemove(direction)
        }
    }
}

enum SwipeDirection {
    case left, right
}

struct OutfitCard {
    let image: Image
    let title: String
    let temperature: String
    let tag: String
} 