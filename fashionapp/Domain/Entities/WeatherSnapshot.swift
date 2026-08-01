import Foundation

struct WeatherSnapshot: Codable, Equatable, Hashable {
    var temperatureCelsius: Double
    var apparentTemperatureCelsius: Double
    var humidity: Double
    var windSpeedKmh: Double
    var rainProbability: Double
    var uvIndex: Double
    var airQualityIndex: Double?
    var conditionSymbol: String
    var conditionDescription: String
    var locationName: String
    var fetchedAt: Date

    var temperatureBand: TemperatureBand {
        TemperatureBand.from(celsius: temperatureCelsius)
    }

    var isRainy: Bool { rainProbability >= 0.45 || conditionDescription.lowercased().contains("rain") }
    var isSnowy: Bool { conditionDescription.lowercased().contains("snow") }
}

struct DailyWeatherForecast: Identifiable, Codable, Equatable, Hashable {
    var id: Date { date }
    var date: Date
    var highCelsius: Double
    var lowCelsius: Double
    var symbolName: String
    var conditionDescription: String
}

/// What the user is planning on a calendar day.
enum DayPlanKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case knownOutfit
    case event
    case travel
    case mood
    case laundry
    case shopping
    case note

    var id: String { rawValue }

    /// Primary choices shown first when a day is tapped.
    static var primaryOptions: [DayPlanKind] { [.knownOutfit, .event, .travel] }

    /// Extra choices under “More options”.
    static var moreOptions: [DayPlanKind] { [.mood, .laundry, .shopping, .note] }

    var title: String {
        switch self {
        case .knownOutfit: return NSLocalizedString("I know what to wear", comment: "Day plan option")
        case .event: return NSLocalizedString("I have an event", comment: "Day plan option")
        case .travel: return NSLocalizedString("I'm going on a trip", comment: "Day plan option")
        case .mood: return NSLocalizedString("Plan by mood", comment: "Day plan option")
        case .laundry: return NSLocalizedString("Laundry day", comment: "Day plan option")
        case .shopping: return NSLocalizedString("Need to shop", comment: "Day plan option")
        case .note: return NSLocalizedString("Add a note", comment: "Day plan option")
        }
    }

    var subtitle: String {
        switch self {
        case .knownOutfit: return NSLocalizedString("Pick pieces from your wardrobe for this day.", comment: "")
        case .event: return NSLocalizedString("Tell us the occasion so Nook can dress for it.", comment: "")
        case .travel: return NSLocalizedString("Destination, season, and packing suggestions.", comment: "")
        case .mood: return NSLocalizedString("Capture how you want to feel in your clothes.", comment: "")
        case .laundry: return NSLocalizedString("Mark a day for washing or refreshing pieces.", comment: "")
        case .shopping: return NSLocalizedString("Note a gap before you buy something new.", comment: "")
        case .note: return NSLocalizedString("A private reminder for this day.", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .knownOutfit: return "tshirt.fill"
        case .event: return "calendar.badge.clock"
        case .travel: return "airplane"
        case .mood: return "heart.text.square"
        case .laundry: return "washer.fill"
        case .shopping: return "bag.fill"
        case .note: return "note.text"
        }
    }
}

/// Common event types when the user picks “I have an event”.
enum DayEventType: String, Codable, CaseIterable, Identifiable, Hashable {
    case wedding
    case work
    case dinner
    case party
    case interview
    case religious
    case family
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wedding: return NSLocalizedString("Wedding", comment: "Event type")
        case .work: return NSLocalizedString("Work / meeting", comment: "Event type")
        case .dinner: return NSLocalizedString("Dinner out", comment: "Event type")
        case .party: return NSLocalizedString("Party", comment: "Event type")
        case .interview: return NSLocalizedString("Interview", comment: "Event type")
        case .religious: return NSLocalizedString("Religious gathering", comment: "Event type")
        case .family: return NSLocalizedString("Family gathering", comment: "Event type")
        case .other: return NSLocalizedString("Other", comment: "Event type")
        }
    }

    var suggestedDressCode: String? {
        switch self {
        case .wedding: return "Formal / elegant"
        case .work, .interview: return "Smart / business"
        case .dinner: return "Smart casual"
        case .party: return "Evening out"
        case .religious, .family: return "Modest & polished"
        case .other: return nil
        }
    }
}

struct CalendarEvent: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var location: String?
    var dressCode: String?
    var isAllDay: Bool
    /// Day-plan kind. Defaults to `.event` when decoding older documents.
    var kind: DayPlanKind
    var eventType: String?
    var wardrobeItemIDs: [UUID]
    var suggestedItemIDs: [UUID]
    var weatherSummary: String?
    var notes: String?
    var packingListID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        location: String? = nil,
        dressCode: String? = nil,
        isAllDay: Bool = true,
        kind: DayPlanKind = .event,
        eventType: String? = nil,
        wardrobeItemIDs: [UUID] = [],
        suggestedItemIDs: [UUID] = [],
        weatherSummary: String? = nil,
        notes: String? = nil,
        packingListID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.dressCode = dressCode
        self.isAllDay = isAllDay
        self.kind = kind
        self.eventType = eventType
        self.wardrobeItemIDs = wardrobeItemIDs
        self.suggestedItemIDs = suggestedItemIDs
        self.weatherSummary = weatherSummary
        self.notes = notes
        self.packingListID = packingListID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        dressCode = try container.decodeIfPresent(String.self, forKey: .dressCode)
        isAllDay = try container.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? true
        kind = try container.decodeIfPresent(DayPlanKind.self, forKey: .kind) ?? .event
        eventType = try container.decodeIfPresent(String.self, forKey: .eventType)
        wardrobeItemIDs = try container.decodeIfPresent([UUID].self, forKey: .wardrobeItemIDs) ?? []
        suggestedItemIDs = try container.decodeIfPresent([UUID].self, forKey: .suggestedItemIDs) ?? []
        weatherSummary = try container.decodeIfPresent(String.self, forKey: .weatherSummary)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        packingListID = try container.decodeIfPresent(UUID.self, forKey: .packingListID)
    }
}

struct WardrobeStatistics: Codable, Equatable, Hashable {
    var totalItems: Int
    var favoritesCount: Int
    var wornThisWeek: Int
    var categoryCounts: [ClothingCategory: Int]
    var mostWornItemID: UUID?
    var leastWornItemID: UUID?
    var averageFormality: Double
}
