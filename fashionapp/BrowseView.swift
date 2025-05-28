import SwiftUI

struct BrowseView: View {
    var body: some View {
        VStack {
            Text("Browse")
                .font(.title)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
} 