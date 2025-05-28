import SwiftUI

struct WardrobeView: View {
    @StateObject private var manager = OutfitCloudKitManager()
    let columns = [GridItem(.adaptive(minimum: 140), spacing: 16)]
    var onAddOutfit: (() -> Void)? = nil

    var body: some View {
        NavigationView {
            Group {
                if manager.isLoading {
                    ProgressView("Loading Outfits...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = manager.error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                        Text("Failed to load outfits")
                            .font(.headline)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") { manager.fetchOutfits() }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if manager.outfits.isEmpty {
                    VStack(spacing: 24) {
                        Image(systemName: "tshirt.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .foregroundColor(.accentColor)
                            .opacity(0.7)
                        Text("Your wardrobe is empty!")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Start building your wardrobe by adding your first outfit.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button(action: { onAddOutfit?() }) {
                            Label("Add Outfit", systemImage: "plus.circle.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(manager.outfits) { outfit in
                                VStack(spacing: 8) {
                                    if let image = outfit.image {
                                        Image(uiImage: image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 120, height: 120)
                                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                            .shadow(radius: 4)
                                    } else {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(Color.secondary.opacity(0.1))
                                            .frame(width: 120, height: 120)
                                            .overlay(
                                                Image(systemName: "photo")
                                                    .font(.system(size: 32))
                                                    .foregroundColor(.secondary)
                                            )
                                    }
                                    Text(outfit.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .padding(8)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Wardrobe")
            .onAppear { manager.fetchOutfits() }
        }
    }
} 