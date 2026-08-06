import Combine
import Foundation
import SwiftUI
import FirebaseCrashlytics

/// Composition root — Firebase Auth / Firestore / Storage / Analytics.
@MainActor
final class AppContainer: ObservableObject {
    let settings: AppSettingsProviding
    let authService: FirebaseAuthService
    let analytics: AnalyticsTracking

    let imageStorage: ImageStorage
    let wardrobeRepository: WardrobeRepository
    let outfitRepository: OutfitRepository
    let profileRepository: UserProfileRepository
    let recommendationRepository: RecommendationRepository
    let weatherCacheRepository: WeatherCacheRepository
    let eventRepository: EventRepository
    let packingListRepository: PackingListRepository

    let locationProvider: LocationProviding
    let weatherProvider: WeatherProviding
    let notificationScheduler: NotificationScheduling
    let scanPipeline: ClothingScanPipeline
    let imageSearch: WardrobeImageSearching?
    let recommender: OutfitRecommending
    let stylingAssistant: StylingAssisting

    let scanAndSaveUseCase: ScanAndSaveClothingUseCase
    let dailyRecommendationsUseCase: GenerateDailyRecommendationsUseCase
    let askAssistantUseCase: AskStylingAssistantUseCase
    let statisticsUseCase: ComputeWardrobeStatisticsUseCase

    private var authObserver: AnyCancellable?

    var isSignedIn: Bool { authService.isSignedIn }
    var currentAuthUser: AuthUser? { authService.currentUser }
    var isFirebaseConfigured: Bool { FirebaseConfig.isConfigured && authService.isFirebaseConfigured }

    init() {
        // Prefer configure before Auth/Storage touch; never crash launch if ordering races.
        _ = FirebaseBootstrap.configureIfPossible()
        #if DEBUG
        assert(
            FirebaseBootstrap.isConfigured || !FirebaseConfig.isConfigured,
            "FirebaseApp.configure() should run before AppContainer when GoogleService-Info.plist is present."
        )
        #endif

        let settings = UserDefaultsAppSettings()
        let authService = FirebaseAuthService()
        let analytics: AnalyticsTracking = FirebaseAnalyticsTracker()

        AuthSession.shared.userID = authService.currentUser?.id
        if let uid = authService.currentUser?.id {
            analytics.setUserID(uid)
            Self.setCrashlyticsUserID(uid)
        }

        let imageStorage: ImageStorage = FirebaseImageStorage()
        let wardrobeRepository: WardrobeRepository = FirebaseWardrobeRepository()
        let outfitRepository: OutfitRepository = FirebaseOutfitRepository()
        let profileRepository: UserProfileRepository = FirebaseUserProfileRepository()
        let recommendationRepository: RecommendationRepository = FirebaseRecommendationRepository()
        let weatherCacheRepository: WeatherCacheRepository = FirebaseWeatherCacheRepository()
        let eventRepository: EventRepository = FirebaseEventRepository()
        let packingListRepository: PackingListRepository = FirebasePackingListRepository()

        let locationProvider = CoreLocationProvider()
        let weatherProvider = WeatherKitService(
            locationProvider: locationProvider,
            cache: weatherCacheRepository
        )
        let notificationScheduler: NotificationScheduling = LocalNotificationService()

        // On-device multi-task CoreML model for category + attributes + embedding.
        // Falls back to heuristics when the compiled model isn't bundled.
        // Segmentation/background removal is left unchanged.
        // Do not touch ClothesSegFormerParser.shared here — default provider is lazy on first scan.
        let fashionModel = CoreMLFashionModel()
        let detector: ClothingDetector
        let metadataExtractor: ClothingMetadataExtractor
        let imageSearch: WardrobeImageSearching?
        if let fashionModel {
            detector = CoreMLClothingDetector(model: fashionModel)
            metadataExtractor = CoreMLClothingMetadataExtractor(model: fashionModel)
            imageSearch = CoreMLWardrobeImageSearch(model: fashionModel, imageStorage: imageStorage)
        } else {
            detector = HeuristicClothingDetector()
            metadataExtractor = ColorAwareMetadataExtractor()
            imageSearch = nil
        }
        let pipeline = DefaultClothingScanPipeline(
            detector: detector,
            segmenter: U2NetClothingSegmenter(),
            backgroundRemover: MaskBackgroundRemover(),
            metadataExtractor: metadataExtractor
        )

        let recommender = RuleBasedOutfitRecommender()
        let assistant = LocalStylingAssistant(recommender: recommender)

        self.settings = settings
        self.authService = authService
        self.analytics = analytics
        self.imageStorage = imageStorage
        self.wardrobeRepository = wardrobeRepository
        self.outfitRepository = outfitRepository
        self.profileRepository = profileRepository
        self.recommendationRepository = recommendationRepository
        self.weatherCacheRepository = weatherCacheRepository
        self.eventRepository = eventRepository
        self.packingListRepository = packingListRepository
        self.locationProvider = locationProvider
        self.weatherProvider = weatherProvider
        self.notificationScheduler = notificationScheduler
        self.scanPipeline = pipeline
        self.imageSearch = imageSearch
        self.recommender = recommender
        self.stylingAssistant = assistant

        self.scanAndSaveUseCase = ScanAndSaveClothingUseCase(
            pipeline: pipeline,
            imageStorage: imageStorage,
            wardrobeRepository: wardrobeRepository
        )
        self.dailyRecommendationsUseCase = GenerateDailyRecommendationsUseCase(
            wardrobeRepository: wardrobeRepository,
            weatherProvider: weatherProvider,
            eventRepository: eventRepository,
            profileRepository: profileRepository,
            recommender: recommender,
            recommendationRepository: recommendationRepository
        )
        self.askAssistantUseCase = AskStylingAssistantUseCase(
            assistant: assistant,
            wardrobeRepository: wardrobeRepository,
            weatherProvider: weatherProvider,
            profileRepository: profileRepository,
            eventRepository: eventRepository
        )
        self.statisticsUseCase = ComputeWardrobeStatisticsUseCase()

        authObserver = authService.$currentUser.sink { [weak self] user in
            AuthSession.shared.userID = user?.id
            self?.analytics.setUserID(user?.id)
            Self.setCrashlyticsUserID(user?.id)
            self?.objectWillChange.send()
        }

        // Avoid reserved Analytics key prefixes (`firebase_`, `google_`, `ga_`).
        analytics.track(.appOpen, parameters: [
            "is_configured": FirebaseConfig.isConfigured ? "true" : "false",
            "project_id": FirebaseConfig.projectID ?? "missing"
        ])
    }

    func signOut() {
        analytics.track(.logout)
        try? authService.signOut()
        analytics.setUserID(nil)
        Self.setCrashlyticsUserID(nil)
        AuthSession.shared.userID = nil
        objectWillChange.send()
    }

    private static func setCrashlyticsUserID(_ userID: String?) {
        guard FirebaseBootstrap.isConfigured else { return }
        Crashlytics.crashlytics().setUserID(userID ?? "")
    }
}
