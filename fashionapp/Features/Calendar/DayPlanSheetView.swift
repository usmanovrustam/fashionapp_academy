import SwiftUI
import UIKit

/// Create or edit a day plan (wear / event / trip / laundry / donate).
struct DayPlanSheetView: View {
    enum Step: Equatable {
        case chooseKind
        case knownOutfit
        case eventDetails
        case travelDetails
        case laundry
        case donate
    }

    let date: Date
    let wardrobeItems: [WardrobeItem]
    let imageStorage: ImageStorage
    let existingEvent: CalendarEvent?
    /// Used to require dress vs separates for known outfits.
    let userGender: UserGender?
    /// When set, skip the kind list (e.g. “Select Another” outfit).
    let initialStep: Step?
    let onSave: (CalendarEvent, PackingList?, [WardrobeItem]) -> Void
    let onCancel: () -> Void
    /// Opens wardrobe Scan when the closet is empty.
    let onScanWardrobe: (() -> Void)?

    @State private var step: Step
    @State private var planID: UUID
    @State private var packingListID: UUID?
    @State private var selectedItemIDs: Set<UUID>
    @State private var wearSlots: OutfitSlotAssignment
    @State private var preferDressLook: Bool
    @State private var pickingSlot: OutfitWearSlot?
    @State private var eventType: DayEventType
    @State private var customEventNote: String
    @State private var destination: String
    @State private var tripEndDate: Date
    @State private var travelPlace: GeocodedPlace?
    @State private var travelAnalysis: TravelPackingAdvisor.Result?
    @State private var packingTips: [String]
    @State private var suggestedIDs: Set<UUID>
    @State private var weatherSummary: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private let weatherClient = OpenMeteoWeatherClient()
    private let calendar = Calendar.current
    private var isEditing: Bool { existingEvent != nil }
    private var allowsDress: Bool { userGender != .man }

    init(
        date: Date,
        wardrobeItems: [WardrobeItem],
        imageStorage: ImageStorage,
        existingEvent: CalendarEvent? = nil,
        userGender: UserGender? = nil,
        initialStep: Step? = nil,
        onSave: @escaping (CalendarEvent, PackingList?, [WardrobeItem]) -> Void,
        onCancel: @escaping () -> Void,
        onScanWardrobe: (() -> Void)? = nil
    ) {
        self.date = date
        self.wardrobeItems = wardrobeItems
        self.imageStorage = imageStorage
        self.existingEvent = existingEvent
        self.userGender = userGender
        self.initialStep = initialStep
        self.onSave = onSave
        self.onCancel = onCancel
        self.onScanWardrobe = onScanWardrobe

        let calendar = Calendar.current
        let defaultEnd = calendar.date(byAdding: .day, value: 3, to: date) ?? date

        if let existing = existingEvent {
            let linked = wardrobeItems.filter { existing.wardrobeItemIDs.contains($0.id) }
            let slots = OutfitSlotAssignment.from(items: linked)
            _step = State(initialValue: Self.step(for: existing.kind))
            _planID = State(initialValue: existing.id)
            _packingListID = State(initialValue: existing.packingListID)
            _selectedItemIDs = State(initialValue: Set(existing.wardrobeItemIDs))
            _wearSlots = State(initialValue: slots)
            _preferDressLook = State(initialValue: slots.isDressLook)
            _eventType = State(initialValue: DayEventType(rawValue: existing.eventType ?? "") ?? .work)
            _customEventNote = State(initialValue: existing.notes ?? existing.dressCode ?? "")
            _destination = State(initialValue: existing.location ?? "")
            _tripEndDate = State(initialValue: existing.endDate)
            _suggestedIDs = State(initialValue: Set(existing.suggestedItemIDs.isEmpty ? existing.wardrobeItemIDs : existing.suggestedItemIDs))
            _packingTips = State(initialValue: (existing.notes ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty })
            _weatherSummary = State(initialValue: existing.weatherSummary)
            if let location = existing.location, !location.isEmpty {
                _travelPlace = State(initialValue: GeocodedPlace(name: location, latitude: 0, longitude: 0))
            } else {
                _travelPlace = State(initialValue: nil)
            }
        } else {
            _step = State(initialValue: initialStep ?? .chooseKind)
            _planID = State(initialValue: UUID())
            _packingListID = State(initialValue: nil)
            _selectedItemIDs = State(initialValue: [])
            _wearSlots = State(initialValue: OutfitSlotAssignment())
            _preferDressLook = State(initialValue: false)
            _eventType = State(initialValue: .work)
            _customEventNote = State(initialValue: "")
            _destination = State(initialValue: "")
            _tripEndDate = State(initialValue: defaultEnd)
            _travelPlace = State(initialValue: nil)
            _travelAnalysis = State(initialValue: nil)
            _packingTips = State(initialValue: [])
            _suggestedIDs = State(initialValue: [])
            _weatherSummary = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .chooseKind:
                    kindList
                case .knownOutfit:
                    knownOutfitForm
                case .eventDetails:
                    eventForm
                case .travelDetails:
                    travelForm
                case .laundry:
                    itemPickerForm(
                        title: NSLocalizedString("Mark what needs a wash", comment: ""),
                        emptyMessage: NSLocalizedString("Nothing left to mark — everything is already in laundry.", comment: ""),
                        items: wardrobeItems.filter { !$0.isInLaundry || selectedItemIDs.contains($0.id) },
                        saveTitle: NSLocalizedString("Mark as need to wash", comment: ""),
                        onSave: saveLaundry
                    )
                case .donate:
                    itemPickerForm(
                        title: NSLocalizedString("Choose pieces to donate", comment: ""),
                        emptyMessage: NSLocalizedString("No pieces available to mark for donate right now.", comment: ""),
                        items: wardrobeItems.filter { !$0.isListedForDonate || selectedItemIDs.contains($0.id) },
                        saveTitle: NSLocalizedString("Mark for donate", comment: ""),
                        onSave: saveDonate
                    )
                }
            }
            .nookScreenBackground()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(backButtonTitle) {
                        handleBack()
                    }
                }
            }
            .alert(NSLocalizedString("Something went wrong", comment: ""), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(item: $pickingSlot) { slot in
                WearSlotPickerSheet(
                    slot: slot,
                    items: candidates(for: slot),
                    storage: imageStorage,
                    selectedID: wearSlots.item(for: slot)?.id,
                    onSelect: { item in
                        wearSlots.assign(item, to: slot)
                        if slot == .body { preferDressLook = true }
                        if slot == .top || slot == .bottom { preferDressLook = false }
                        pickingSlot = nil
                    },
                    onClear: {
                        wearSlots.clear(slot)
                        pickingSlot = nil
                    },
                    onClose: { pickingSlot = nil }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var navigationTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        let day = formatter.string(from: date)
        return isEditing ? String(format: NSLocalizedString("Edit · %@", comment: ""), day) : day
    }

    private var backButtonTitle: String {
        if step == .chooseKind || isEditing { return NSLocalizedString("Close", comment: "") }
        return NSLocalizedString("Back", comment: "")
    }

    private func handleBack() {
        if isEditing || step == .chooseKind || (initialStep != nil && step == initialStep) {
            onCancel()
            return
        }
        selectedItemIDs = []
        wearSlots = OutfitSlotAssignment()
        preferDressLook = false
        step = .chooseKind
    }

    private static func step(for kind: DayPlanKind) -> Step {
        switch kind {
        case .knownOutfit: return .knownOutfit
        case .event: return .eventDetails
        case .travel: return .travelDetails
        case .laundry: return .laundry
        case .donate: return .donate
        case .mood, .shopping, .note: return .chooseKind
        }
    }

    // MARK: - Kind picker

    private var kindList: some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                Text(NSLocalizedString("What do you have this day?", comment: ""))
                    .font(AppTypography.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, AppSpacing.sm)

                ForEach(DayPlanKind.dayOptions) { kind in
                    Button {
                        open(kind)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: kind.systemImage)
                                .font(.title3)
                                .foregroundStyle(AppColors.olive)
                                .frame(width: 36)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(kind.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                Text(kind.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .padding()
                        .liquidGlass(cornerRadius: AppRadius.medium)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    private func open(_ kind: DayPlanKind) {
        selectedItemIDs = []
        switch kind {
        case .knownOutfit: step = .knownOutfit
        case .event: step = .eventDetails
        case .travel: step = .travelDetails
        case .laundry: step = .laundry
        case .donate: step = .donate
        case .mood, .shopping, .note: break
        }
    }

    // MARK: - Known outfit (required wears)

    private var knownOutfitForm: some View {
        let available = wardrobeItems.filter { $0.isAvailableToWear || wearSlots.itemIDs.contains($0.id) }
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text(NSLocalizedString("Select the wears", comment: "Known outfit slot picker title"))
                        .font(AppTypography.headline)

                    Text(NSLocalizedString(
                        "A full look needs every wear filled before you can save it to this day.",
                        comment: "Known outfit requirement copy"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if available.isEmpty {
                        Text(NSLocalizedString("Your wardrobe is empty. Scan a piece first, then come back.", comment: ""))
                            .foregroundStyle(.secondary)
                        if let onScanWardrobe {
                            Button(action: onScanWardrobe) {
                                Label(NSLocalizedString("Scan a piece", comment: ""), systemImage: "camera.fill")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(AppColors.brand)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(AppColors.olive)
                                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                            }
                        }
                    } else {
                        if allowsDress {
                            Picker(
                                NSLocalizedString("Look type", comment: ""),
                                selection: $preferDressLook
                            ) {
                                Text(NSLocalizedString("Top + bottom", comment: "Separates look type")).tag(false)
                                Text(NSLocalizedString("Dress", comment: "Dress look type")).tag(true)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: preferDressLook) { _, useDress in
                                if useDress {
                                    wearSlots.top = nil
                                    wearSlots.bottom = nil
                                } else {
                                    wearSlots.body = nil
                                }
                            }
                        }

                        FullOutfitPreview(
                            slots: wearSlots,
                            storage: imageStorage,
                            onTapSlot: { slot in
                                pickingSlot = slot
                            },
                            highlightsMissing: true,
                            preferDressLayout: preferDressLook && allowsDress
                        )
                        .frame(height: preferDressLook && allowsDress ? 230 : 220)

                        OutfitWearChipRow(slots: wearSlots)

                        if !wearSlots.isComplete {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(wearSlots.missingWearMessages(for: userGender), id: \.self) { line in
                                    Label(line, systemImage: "circle.dotted")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .liquidGlass(cornerRadius: AppRadius.medium)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                        }
                    }
                }
                .padding()
                .padding(.bottom, 100)
            }

            saveBar(
                title: NSLocalizedString("Save to calendar", comment: ""),
                enabled: wearSlots.isComplete,
                action: saveKnownOutfit
            )
        }
    }

    private func candidates(for slot: OutfitWearSlot) -> [WardrobeItem] {
        wardrobeItems.filter { item in
            guard item.isAvailableToWear || wearSlots.item(for: slot)?.id == item.id else { return false }
            switch slot {
            case .top: return item.category == .top
            case .bottom: return item.category == .bottom
            case .body: return item.category == .dress && allowsDress
            case .shoes: return item.category == .shoes
            }
        }
    }

    // MARK: - Shared item picker

    private func itemPickerForm(
        title: String,
        emptyMessage: String,
        items: [WardrobeItem],
        saveTitle: String,
        showScanCTA: Bool = false,
        onSave: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(AppTypography.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

            if items.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text(emptyMessage)
                        .foregroundStyle(.secondary)
                    if showScanCTA, let onScanWardrobe {
                        Button(action: onScanWardrobe) {
                            Label(NSLocalizedString("Scan a piece", comment: ""), systemImage: "camera.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppColors.brand)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppColors.olive)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                        }
                    }
                }
                .padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(items) { item in
                            SelectableWardrobeCell(
                                item: item,
                                storage: imageStorage,
                                isSelected: selectedItemIDs.contains(item.id)
                            ) {
                                if selectedItemIDs.contains(item.id) {
                                    selectedItemIDs.remove(item.id)
                                } else {
                                    selectedItemIDs.insert(item.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 100)
                }
            }

            saveBar(title: saveTitle, enabled: !selectedItemIDs.isEmpty, action: onSave)
        }
    }

    private func saveKnownOutfit() {
        guard wearSlots.isComplete else { return }
        let ids = wearSlots.itemIDs
        let title = wearSlots.displayTitle

        let previousIDs = Set(existingEvent?.wardrobeItemIDs ?? [])
        var updatedItems = wardrobeItems.filter { ids.contains($0.id) || previousIDs.contains($0.id) }
        for index in updatedItems.indices {
            if ids.contains(updatedItems[index].id) {
                updatedItems[index].plannedDate = calendar.startOfDay(for: date)
            } else if calendar.isDate(updatedItems[index].plannedDate ?? .distantPast, inSameDayAs: date) {
                updatedItems[index].plannedDate = nil
            }
            updatedItems[index].updatedAt = Date()
        }

        let event = CalendarEvent(
            id: planID,
            title: title,
            startDate: calendar.startOfDay(for: date),
            endDate: calendar.startOfDay(for: date),
            isAllDay: true,
            kind: .knownOutfit,
            wardrobeItemIDs: ids
        )
        onSave(event, nil, updatedItems)
    }

    private func saveLaundry() {
        let ids = Array(selectedItemIDs)
        let previousIDs = Set(existingEvent?.wardrobeItemIDs ?? [])
        var updatedItems = wardrobeItems.filter { ids.contains($0.id) || previousIDs.contains($0.id) }
        for index in updatedItems.indices {
            updatedItems[index].isInLaundry = ids.contains(updatedItems[index].id)
            updatedItems[index].updatedAt = Date()
        }

        let event = CalendarEvent(
            id: planID,
            title: NSLocalizedString("Laundry", comment: ""),
            startDate: calendar.startOfDay(for: date),
            endDate: calendar.startOfDay(for: date),
            isAllDay: true,
            kind: .laundry,
            wardrobeItemIDs: ids,
            notes: String(format: NSLocalizedString("%d piece(s) marked as need to wash", comment: ""), ids.count)
        )
        onSave(event, nil, updatedItems)
    }

    private func saveDonate() {
        let ids = Array(selectedItemIDs)
        let now = Date()
        let previousIDs = Set(existingEvent?.wardrobeItemIDs ?? [])
        var updatedItems = wardrobeItems.filter { ids.contains($0.id) || previousIDs.contains($0.id) }
        for index in updatedItems.indices {
            let selected = ids.contains(updatedItems[index].id)
            updatedItems[index].isListedForDonate = selected
            updatedItems[index].listedForDonateAt = selected ? calendar.startOfDay(for: date) : nil
            if selected { updatedItems[index].isInLaundry = false }
            updatedItems[index].updatedAt = now
        }

        let event = CalendarEvent(
            id: planID,
            title: NSLocalizedString("Donate", comment: ""),
            startDate: calendar.startOfDay(for: date),
            endDate: calendar.startOfDay(for: date),
            isAllDay: true,
            kind: .donate,
            wardrobeItemIDs: ids,
            notes: String(format: NSLocalizedString("%d piece(s) marked for donate", comment: ""), ids.count)
        )
        onSave(event, nil, updatedItems)
    }

    // MARK: - Event

    private var eventForm: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text(NSLocalizedString("What type of event?", comment: ""))
                        .font(AppTypography.headline)

                    ForEach(DayEventType.allCases) { type in
                        Button {
                            eventType = type
                        } label: {
                            HStack {
                                Text(type.displayName)
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                if eventType == type {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppColors.olive)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                                    .fill(eventType == type ? AppColors.brand.opacity(0.45) : Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                                    .stroke(AppColors.olive.opacity(eventType == type ? 0.5 : 0.12), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    TextField(NSLocalizedString("Optional note (dress code, venue…)", comment: ""), text: $customEventNote, axis: .vertical)
                        .lineLimit(2...4)
                        .padding()
                        .liquidGlass(cornerRadius: AppRadius.medium)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                    let suggestions = EventOutfitAdvisor.suggest(from: wardrobeItems, eventType: eventType)
                    if suggestions.isEmpty {
                        if wardrobeItems.filter(\.isAvailableToWear).isEmpty, let onScanWardrobe {
                            Button(action: onScanWardrobe) {
                                Label(NSLocalizedString("Scan pieces for this event", comment: ""), systemImage: "camera.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppColors.olive)
                            }
                        }
                    } else {
                        Text(NSLocalizedString("Suggested from your wardrobe", comment: ""))
                            .font(AppTypography.headline)
                            .padding(.top, 8)
                        Text(NSLocalizedString("Optional — tap to include with this event.", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(suggestions) { item in
                                SelectableWardrobeCell(
                                    item: item,
                                    storage: imageStorage,
                                    isSelected: selectedItemIDs.contains(item.id)
                                ) {
                                    if selectedItemIDs.contains(item.id) {
                                        selectedItemIDs.remove(item.id)
                                    } else {
                                        selectedItemIDs.insert(item.id)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
                .padding(.bottom, 100)
            }

            saveBar(title: NSLocalizedString("Save to calendar", comment: ""), enabled: true) {
                saveEvent()
            }
        }
    }

    private func saveEvent() {
        let dress = customEventNote.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? eventType.suggestedDressCode
        let ids = Array(selectedItemIDs)
        let event = CalendarEvent(
            id: planID,
            title: eventType.displayName,
            startDate: calendar.startOfDay(for: date),
            endDate: calendar.startOfDay(for: date),
            dressCode: dress,
            isAllDay: true,
            kind: .event,
            eventType: eventType.rawValue,
            wardrobeItemIDs: ids,
            notes: customEventNote.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        onSave(event, nil, [])
    }

    // MARK: - Travel

    private var travelForm: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text(NSLocalizedString("Where are you going?", comment: ""))
                        .font(AppTypography.headline)

                    TextField(NSLocalizedString("City or place", comment: ""), text: $destination)
                        .textInputAutocapitalization(.words)
                        .padding()
                        .liquidGlass(cornerRadius: AppRadius.medium)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                    DatePicker(
                        NSLocalizedString("Trip ends", comment: ""),
                        selection: $tripEndDate,
                        in: date...,
                        displayedComponents: .date
                    )
                    .padding()
                    .liquidGlass(cornerRadius: AppRadius.medium)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                    Button {
                        Task { await analyzeTravel() }
                    } label: {
                        HStack {
                            if isWorking {
                                ProgressView().tint(AppColors.brand)
                            }
                            Text(isWorking ? NSLocalizedString("Checking weather…", comment: "") : NSLocalizedString("Analyze season & weather", comment: ""))
                                .font(.body.weight(.semibold))
                        }
                        .foregroundStyle(AppColors.brand)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppColors.olive)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    }
                    .disabled(destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)

                    if let place = travelPlace {
                        Text(place.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.olive)
                    }

                    if let summary = weatherSummary, travelAnalysis == nil {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    if let analysis = travelAnalysis {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(analysis.weatherSummary)
                                .font(.subheadline.weight(.semibold))
                            ForEach(analysis.packingTips, id: \.self) { tip in
                                Label(tip, systemImage: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        .padding()
                        .liquidGlass(cornerRadius: AppRadius.medium)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                        Text(NSLocalizedString("Suggested outfits to take", comment: ""))
                            .font(AppTypography.headline)
                            .padding(.top, 8)

                        if analysis.suggestedItems.isEmpty {
                            Text(NSLocalizedString("No strong wardrobe matches yet — add more pieces for better packing lists.", comment: ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(analysis.suggestedItems) { item in
                                    SelectableWardrobeCell(
                                        item: item,
                                        storage: imageStorage,
                                        isSelected: suggestedIDs.contains(item.id)
                                    ) {
                                        if suggestedIDs.contains(item.id) {
                                            suggestedIDs.remove(item.id)
                                        } else {
                                            suggestedIDs.insert(item.id)
                                        }
                                    }
                                }
                            }
                        }
                    } else if !suggestedIDs.isEmpty {
                        let selected = wardrobeItems.filter { suggestedIDs.contains($0.id) }
                        if !selected.isEmpty {
                            Text(NSLocalizedString("Packed pieces", comment: ""))
                                .font(AppTypography.headline)
                                .padding(.top, 8)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(selected) { item in
                                    SelectableWardrobeCell(
                                        item: item,
                                        storage: imageStorage,
                                        isSelected: suggestedIDs.contains(item.id)
                                    ) {
                                        if suggestedIDs.contains(item.id) {
                                            suggestedIDs.remove(item.id)
                                        } else {
                                            suggestedIDs.insert(item.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
                .padding(.bottom, 100)
            }

            saveBar(
                title: NSLocalizedString("Save to calendar", comment: ""),
                enabled: travelPlace != nil || !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                saveTravel()
            }
        }
    }

    @MainActor
    private func analyzeTravel() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let place = try await weatherClient.geocode(destination: destination)
            travelPlace = place

            let daySpan = max(
                1,
                calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: tripEndDate)).day ?? 1
            ) + 1
            let daysFromNow = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: Date()),
                to: calendar.startOfDay(for: tripEndDate)
            ).day ?? daySpan
            let forecastDays = min(16, max(daySpan, daysFromNow + 1, 3))

            let forecasts = try await weatherClient.fetchDestinationForecast(
                latitude: place.latitude,
                longitude: place.longitude,
                locationName: place.displayName,
                forecastDays: forecastDays
            )

            let analysis = TravelPackingAdvisor.analyze(
                wardrobe: wardrobeItems,
                forecasts: forecasts,
                tripStart: date,
                tripEnd: tripEndDate,
                destinationName: place.displayName
            )
            travelAnalysis = analysis
            packingTips = analysis.packingTips
            weatherSummary = analysis.weatherSummary
            suggestedIDs = Set(analysis.suggestedItems.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveTravel() {
        let placeName = travelPlace?.displayName
            ?? destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = Array(suggestedIDs)
        let listID = packingListID ?? UUID()
        packingListID = listID
        let packing = PackingList(
            id: listID,
            title: String(format: NSLocalizedString("Trip to %@", comment: ""), placeName),
            destination: placeName,
            startDate: calendar.startOfDay(for: date),
            endDate: calendar.startOfDay(for: tripEndDate),
            itemIDs: ids,
            createdAt: existingEvent == nil ? Date() : (existingEvent?.startDate ?? Date())
        )
        let event = CalendarEvent(
            id: planID,
            title: String(format: NSLocalizedString("Trip · %@", comment: ""), placeName),
            startDate: calendar.startOfDay(for: date),
            endDate: calendar.startOfDay(for: tripEndDate),
            location: placeName,
            isAllDay: true,
            kind: .travel,
            wardrobeItemIDs: ids,
            suggestedItemIDs: ids,
            weatherSummary: travelAnalysis?.weatherSummary ?? weatherSummary,
            notes: packingTips.isEmpty ? existingEvent?.notes : packingTips.joined(separator: "\n"),
            packingListID: listID
        )
        onSave(event, packing, [])
    }

    // MARK: - Save bar

    private func saveBar(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.brand)
                .frame(maxWidth: .infinity)
                .padding()
                .background(enabled ? AppColors.olive : AppColors.olive.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
        .disabled(!enabled)
        .padding()
        .background(Color.white.opacity(0.95))
    }
}

private struct WearSlotPickerSheet: View {
    let slot: OutfitWearSlot
    let items: [WardrobeItem]
    let storage: ImageStorage
    let selectedID: UUID?
    let onSelect: (WardrobeItem) -> Void
    let onClear: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        NSLocalizedString("No pieces for this wear", comment: ""),
                        systemImage: "tshirt",
                        description: Text(NSLocalizedString(
                            "Scan or add a matching wardrobe piece first.",
                            comment: ""
                        ))
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(items) { item in
                                SelectableWardrobeCell(
                                    item: item,
                                    storage: storage,
                                    isSelected: selectedID == item.id
                                ) {
                                    onSelect(item)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .nookScreenBackground()
            .navigationTitle(slot.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Close", comment: ""), action: onClose)
                }
                if selectedID != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(NSLocalizedString("Clear", comment: ""), action: onClear)
                    }
                }
            }
        }
    }
}

private struct SelectableWardrobeCell: View {
    let item: WardrobeItem
    let storage: ImageStorage
    let isSelected: Bool
    let onTap: () -> Void

    @State private var image: UIImage?

    var body: some View {
        Button(action: onTap) {
            GeometryReader { geo in
                ZStack(alignment: .topTrailing) {
                    WardrobeItemCard(
                        name: item.name,
                        image: image,
                        width: geo.size.width,
                        height: geo.size.height
                    )

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? AppColors.olive : .white)
                        .shadow(radius: 2)
                        .padding(10)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xLarge, style: .continuous)
                        .stroke(isSelected ? AppColors.olive : Color.clear, lineWidth: 3)
                )
            }
            .frame(height: 180)
        }
        .buttonStyle(.plain)
        .task {
            let path = item.transparentImagePath ?? item.originalImagePath
            image = UIImage(data: (try? await storage.loadImageData(at: path)) ?? Data())
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
