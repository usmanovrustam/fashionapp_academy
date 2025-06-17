import SwiftUI

struct CalendarView: View {
    @StateObject private var manager = OutfitCloudKitManager.shared
    @State private var selectedDate = Date()
    @State private var showingDatePicker = false
    @State private var showingAddOutfit = false
    @State private var selectedOutfit: Outfit?
    @State private var showingOutfitDetail = false
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    private let weekDays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

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
                        // Month selector
                        monthSelector
                        
                        // Calendar grid
                        calendarGrid
                        
                        // Selected date outfits
                        selectedDateOutfits
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Calendar")
            .sheet(isPresented: $showingDatePicker) {
                datePickerSheet
            }
            .sheet(isPresented: $showingAddOutfit) {
                AddOutfitView(selectedDate: selectedDate)
            }
            .sheet(isPresented: $showingOutfitDetail) {
                if let outfit = selectedOutfit {
                    OutfitDetailView(outfit: outfit)
                }
            }
        }
    }
    
    private var monthSelector: some View {
        HStack {
            Button(action: { moveMonth(by: -1) }) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(.purple)
            }
            
            Spacer()
            
            Text(dateFormatter.string(from: selectedDate))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: { moveMonth(by: 1) }) {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundColor(.purple)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
    
    private var calendarGrid: some View {
        VStack(spacing: 8) {
            // Week day headers
                HStack {
                ForEach(weekDays, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar days
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(daysInMonth(), id: \.self) { date in
                    if let date = date {
                        DayCell(
                            date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            hasOutfit: hasOutfit(for: date)
                        )
                        .onTapGesture {
                            selectedDate = date
                        }
            } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
    
    private var selectedDateOutfits: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Outfits for \(selectedDate.formatted(date: .long, time: .omitted))")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: { showingAddOutfit = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.purple)
                }
            }
            
            if let outfits = outfitsForSelectedDate(), !outfits.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(outfits) { outfit in
                            OutfitCard(outfit: outfit)
                                .frame(width: 160)
                                .onTapGesture {
                                    selectedOutfit = outfit
                                    showingOutfitDetail = true
                                }
                        }
                    }
                }
            } else {
                emptyStateView
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
                        }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.purple.opacity(0.8))
            
            Text("No outfits planned")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Tap + to add an outfit for this day")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { showingAddOutfit = true }) {
                Text("Add Outfit")
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
        .frame(maxWidth: .infinity)
    }
    
    private var datePickerSheet: some View {
        NavigationView {
            DatePicker(
                "Select Date",
                selection: $selectedDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingDatePicker = false
                    }
                }
            }
        }
    }
    
    private func moveMonth(by value: Int) {
        if let newDate = calendar.date(byAdding: .month, value: value, to: selectedDate) {
            selectedDate = newDate
        }
    }

    private func daysInMonth() -> [Date?] {
        let interval = calendar.dateInterval(of: .month, for: selectedDate)!
        let firstDay = interval.start
        
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let offsetDays = firstWeekday - 1
        
        let daysInMonth = calendar.range(of: .day, in: .month, for: selectedDate)!.count
        
        var days: [Date?] = Array(repeating: nil, count: offsetDays)
        
        for day in 1...daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }
        
        // Pad the array to complete the last week
        while days.count % 7 != 0 {
            days.append(nil)
    }
        
        return days
    }
    
    private func hasOutfit(for date: Date) -> Bool {
        return manager.outfits.contains { outfit in
            if let plannedDate = outfit.plannedDate {
                return calendar.isDate(plannedDate, inSameDayAs: date)
            }
            return false
        }
    }
    
    private func outfitsForSelectedDate() -> [Outfit]? {
        let outfits = manager.outfits.filter { outfit in
            if let plannedDate = outfit.plannedDate {
                return calendar.isDate(plannedDate, inSameDayAs: selectedDate)
            }
            return false
        }
        return outfits.isEmpty ? nil : outfits
    }
}

#Preview {
    CalendarView()
} 