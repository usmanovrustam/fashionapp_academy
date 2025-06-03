import Foundation
import WeatherKit
import CoreLocation
import SwiftUI

@MainActor
class WeatherManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentWeather: CurrentWeather?
    @Published var dailyForecast: [WeatherDay] = []
    @Published var locationName: String = ""
    @Published var isLoading = false
    @Published var error: Error?

    private let weatherService = WeatherService()
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var locationTimeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestWeather() async {
        isLoading = true
        error = nil
        do {
            let location = try await getLocation()
            let weather = try await weatherService.weather(for: location)
            self.currentWeather = weather.currentWeather
            self.dailyForecast = weather.dailyForecast.forecast.prefix(7).map { day in
                WeatherDay(
                    date: day.date,
                    symbolName: day.symbolName,
                    high: day.highTemperature,
                    low: day.lowTemperature
                )
            }
            self.locationName = await getLocationName(for: location)
        } catch {
            self.error = error
        }
        isLoading = false
    }

    private func getLocation() async throws -> CLLocation {
        if let loc = locationManager.location {
            return loc
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            locationManager.requestWhenInUseAuthorization()
            locationManager.requestLocation()
            // Timeout: always resume after 10 seconds if nothing happens
            locationTimeoutTask = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if let continuation = self.locationContinuation {
                    continuation.resume(throwing: NSError(domain: "WeatherManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Location request timed out"]))
                    self.locationContinuation = nil
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.first {
            locationContinuation?.resume(returning: loc)
            locationContinuation = nil
            locationTimeoutTask?.cancel()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
        locationTimeoutTask?.cancel()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            locationContinuation?.resume(throwing: NSError(domain: "WeatherManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Location permission denied"]))
            locationContinuation = nil
            locationTimeoutTask?.cancel()
        }
    }

    private func getLocationName(for location: CLLocation) async -> String {
        let geocoder = CLGeocoder()
        if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
            return placemark.locality ?? placemark.name ?? ""
        }
        return ""
    }
}

struct WeatherDay: Identifiable {
    let id = UUID()
    let date: Date
    let symbolName: String
    let high: Measurement<UnitTemperature>
    let low: Measurement<UnitTemperature>
} 