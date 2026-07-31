# Sylyo — AI Fashion Stylist

Personal AI stylist for iOS. Scan clothing, build a digital wardrobe, and get weather-aware outfit recommendations with an on-device styling assistant.

## Architecture

Clean, modular layers with dependency injection via `AppContainer`:

```text
App/                 Composition root, routing, tabs
DesignSystem/        Colors, spacing, reusable UI
Domain/              Entities, repository & service protocols, use cases
Data/                Local JSON persistence, image storage, CloudKit adapter
Infrastructure/      Vision pipeline, WeatherKit, auth, camera, AI engines
Features/            SwiftUI screens + view models (UI only)
```

Business logic stays out of views. Every service is protocol-backed and replaceable.

### Modules

| Module | Responsibility |
|---|---|
| Authentication | iCloud account status (non-blocking; local-first) |
| User Profile | Preferences, avatar, style settings |
| Wardrobe | CRUD for clothing items + statistics |
| Clothing Scanner | Detect → segment → remove BG → metadata → save |
| Outfit Recommendation | Weather + preferences + wardrobe scoring |
| Weather Service | WeatherKit + location + cache |
| Calendar Integration | Plan looks by day / local events store |
| AI Chat Assistant | Intent parsing over the wardrobe |
| Database | Codable local store (+ optional CloudKit sync) |
| Storage | File-based wardrobe images |
| Settings | Onboarding, language, units |

### Computer vision pipeline

`DefaultClothingScanPipeline` orchestrates:

1. `ClothingDetector`
2. `ClothingSegmenter` (U²-Net CoreML)
3. `BackgroundRemover`
4. `ClothingMetadataExtractor` (color / material / season / style heuristics)

Swap any stage without touching UI or use cases.

### Persistence

- **Primary:** on-device JSON + image files (`LocalWardrobeRepository`, `FileImageStorage`)
- **Optional sync:** `CloudKitWardrobeRepository` ready behind the same protocol

### Future-ready protocols

Virtual try-on, body-shape analysis, color season, trend detection, shopping suggestions, laundry tracking, image search, voice assistant, and smart mirror hooks live in `FutureCapabilityProtocols.swift`.

## UI

The original Sylyo look is preserved:

- Soft purple/pink gradients
- Glass material cards
- Discover swipe stack
- Dashed scanner photo frame
- Wardrobe grid + loading rings
- Calendar day cells
- Profile avatar ring + stat cards

## Requirements

- Xcode 16+
- iOS 17.6+
- Capabilities: Camera, Photos, Location, WeatherKit, CloudKit (optional sync)

## Run

1. Open `fashionapp.xcodeproj`
2. Select a development team for signing
3. Build & run on a device (camera + WeatherKit)

## Localization

English and Italian strings in `en.lproj` / `it.lproj`.
