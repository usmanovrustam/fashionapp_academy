import SwiftUI

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let hasOutfit: Bool
    
    private let calendar = Calendar.current
    
    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    var body: some View {
        ZStack {
            // Background
            Circle()
                .fill(isSelected ? Color.purple.opacity(0.2) : Color.clear)
            
            // Content
            VStack(spacing: 4) {
                Text(dayNumber)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundColor(isSelected ? .purple : (isToday ? .purple : .primary))
                
                if hasOutfit {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(
            Circle()
                .stroke(isToday ? Color.purple : Color.clear, lineWidth: 1)
        )
    }
} 