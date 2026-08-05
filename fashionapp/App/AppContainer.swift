import Combine
import Foundation
import SwiftUI

/// Composition root — Firebase Auth / Firestore / Storage / Analytics only.
/// Wardrobe storage uses Firestore (not CloudKit / iCloud).
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
        _ = FirebaseBootstrap.configureIfPossible()

        let settings = UserDefaultsAppSettings()
        let authService = FirebaseAuthService()
        let analytics: AnalyticsTracking = FirebaseAnalyticsTracker()

        AuthSession.shared.userID = authService.currentUser?.id
        if let uid = authService.currentUser?.id {
            analytics.setUserID(uid)
        }

        // Real Firebase backends — replace former CloudKit wardrobe store.
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

        // On-device multi-task CoreML model (category / attributes / embedding).
        // Falls back to the heuristic detector + extractor when the compiled
        // model isn't bundled in the target yet.
        let fashionModel = CoreMLFashionModel()
        let detector: ClothingDetector = fashionModel.map(CoreMLClothingDetector.init)
            ?? HeuristicClothingDetector()
        let metadataExtractor: ClothingMetadataExtractor = fashionModel.map(CoreMLClothingMetadataExtractor.init)
            ?? ColorAwareMetadataExtractor()
        let pipeline = DefaultClothingScanPipeline(
            detector: detector,
            segmenter: U2NetClothingSegmenter(),
            backgroundRemover: MaskBackgroundRemover(),
            metadataExtractor: metadataExtractor
        )
        let imageSearch: WardrobeImageSearching? = fashionModel.map {
            CoreMLWardrobeImageSearch(model: $0, imageStorage: imageStorage)
        }

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
            self?.objectWillChange.send()
        }

        analytics.track(.appOpen, parameters: [
            "firebase_configured": FirebaseConfig.isConfigured ? "true" : "false",
            "firebase_project": FirebaseConfig.projectID ?? "missing"
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
