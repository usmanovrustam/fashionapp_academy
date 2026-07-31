import SwiftUI

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasOutfit: Bool

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 4) {
            Text(Self.dayFormatter.string(from: date))
                .font(.system(.body, design: .rounded).weight(isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: 36, height: 36)
                .background {
                    if isSelected {
                        Circle().fill(AppColors.primaryGradient)
                    } else {
                        Circle().fill(Color.clear)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(Color.purple.opacity(isToday && !isSelected ? 1 : 0), lineWidth: 2)
                )

            Circle()
                .fill(Color.purple)
                .frame(width: 5, height: 5)
                .opacity(hasOutfit ? 1 : 0)
        }
    }
}

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var currentMonth: Date = Date()
    @Published var selectedDate: Date = Date()
    @Published var items: [WardrobeItem] = []
    @Published var isLoading = false

    private let wardrobeRepository: WardrobeRepository
    let imageStorage: ImageStorage
    private let calendar = Calendar.current

    init(container: AppContainer) {
        self.wardrobeRepository = container.wardrobeRepository
        self.imageStorage = container.imageStorage
    }

    var daysInMonth: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: currentMonth),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leading = Array(repeating: Date?.none, count: firstWeekday - 1)
        let days: [Date?] = range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)
        }
        return leading + days
    }

    func items(on date: Date) -> [WardrobeItem] {
        items.filter { item in
            guard let planned = item.plannedDate else { return false }
            return calendar.isDate(planned, inSameDayAs: date)
        }
    }

    func hasItem(on date: Date) -> Bool {
        !items(on: date).isEmpty
    }

    func shiftMonth(_ value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newMonth
        }
    }

    func load() async {
        isLoading = true
        items = (try? await wardrobeRepository.fetchAll()) ?? []
        isLoading = false
    }

    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }
}

struct CalendarFeatureView: View {
    private let container: AppContainer
    @StateObject private var viewModel: CalendarViewModel
    @State private var showScanner = false

    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    init(container: AppContainer) {
        self.container = container
        _viewModel = StateObject(wrappedValue: CalendarViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SoftBackground()

                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        monthHeader
                        calendarGrid
                        plannedSection
                    }
                    .padding()
                }
            }
            .navigationTitle(NSLocalizedString("Calendar", comment: ""))
            .sheet(isPresented: $showScanner) {
                ScannerFeatureView(container: container, plannedDate: viewModel.selectedDate)
            }
            .task { await viewModel.load() }
            .onChange(of: showScanner) { _, isShowing in
                if !isShowing {
                    Task { await viewModel.load() }
                }
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { viewModel.shiftMonth(-1) } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .foregroundStyle(AppColors.primaryGradient)
                    .font(.title2)
            }
            Spacer()
            Text(viewModel.monthTitle)
                .font(.title3.weight(.semibold))
            Spacer()
            Button { viewModel.shiftMonth(1) } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .foregroundStyle(AppColors.primaryGradient)
                    .font(.title2)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
    }

    private var calendarGrid: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(viewModel.daysInMonth.enumerated()), id: \.offset) { _, date in
                    if let date {
                        Button {
                            viewModel.selectedDate = date
                        } label: {
                            DayCell(
                                date: date,
                                isSelected: Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate),
                                isToday: Calendar.current.isDateInToday(date),
                                hasOutfit: viewModel.hasItem(on: date)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
    }

    private var plannedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Planned Looks")
                    .font(AppTypography.headline)
                Spacer()
                Button {
                    showScanner = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppColors.primaryGradient)
                        .clipShape(Capsule())
                }
            }

            let planned = viewModel.items(on: viewModel.selectedDate)
            if planned.isEmpty {
                Text("No looks planned for this day.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(planned) { item in
                            StoredWardrobeCardCompact(item: item, storage: viewModel.imageStorage)
                        }
                    }
                }
            }
        }
    }
}

private struct StoredWardrobeCardCompact: View {
    let item: WardrobeItem
    let storage: ImageStorage
    @State private var image: UIImage?

    var body: some View {
        WardrobeItemCard(name: item.name, image: image, width: 140, height: 180)
            .task {
                let path = item.transparentImagePath ?? item.originalImagePath
                image = UIImage(data: (try? await storage.loadImageData(at: path)) ?? Data())
            }
    }
}
