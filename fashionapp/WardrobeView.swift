import SwiftUI

struct WardrobeView: View {
    @StateObject private var manager = OutfitCloudKitManager()
    let columns = [GridItem(.adaptive(minimum: 140), spacing: 16)]

    var body: some View {
        NavigationView {
            Group {
                if manager.isLoading {
                    ProgressView(NSLocalizedString("Loading Outfits...", comment: ""))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = manager.error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                        Text(NSLocalizedString("Failed to load outfits", comment: ""))
                            .font(.headline)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button(NSLocalizedString("Retry", comment: "")) { manager.fetchOutfits() }
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
                        Text(NSLocalizedString("Your wardrobe is empty!", comment: ""))
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(NSLocalizedString("Start building your wardrobe by adding your first outfit.", comment: ""))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
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
            .navigationTitle(NSLocalizedString("Wardrobe", comment: ""))
            .onAppear { manager.fetchOutfits() }
        }
    }
} 