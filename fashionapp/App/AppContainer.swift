import Combine
import Foundation
import SwiftUI

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
    let scanPipeline: ClothingScanPipeline
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
        _ = FirebaseBootstrap.configureIfPossible()

        let settings = UserDefaultsAppSettings()
        let authService = FirebaseAuthService()
        let analytics: AnalyticsTracking = FirebaseAnalyticsTracker()

        AuthSession.shared.userID = authService.currentUser?.id
        if let uid = authService.currentUser?.id {
            analytics.setUserID(uid)
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

        let pipeline = DefaultClothingScanPipeline(
            detector: HeuristicClothingDetector(),
            segmenter: U2NetClothingSegmenter(),
            backgroundRemover: MaskBackgroundRemover(),
            metadataExtractor: ColorAwareMetadataExtractor()
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
        self.scanPipeline = pipeline
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
        AuthSession.shared.userID = nil
        objectWillChange.send()
    }
}
