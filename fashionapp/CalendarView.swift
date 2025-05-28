import SwiftUI

struct CalendarView: View {
    var body: some View {
        VStack {
            Text("Calendar")
                .font(.title)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
} 