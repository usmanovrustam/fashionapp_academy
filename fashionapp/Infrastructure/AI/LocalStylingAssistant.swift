import Foundation

/// Intent-parsing styling assistant that searches the local wardrobe.
/// Replace with an LLM-backed service later without changing the UI layer.
final class LocalStylingAssistant: StylingAssisting {
    private let recommender: OutfitRecommending

    init(recommender: OutfitRecommending) {
        self.recommender = recommender
    }

    func respond(
        to message: String,
        history: [ChatMessage],
        wardrobe: [WardrobeItem],
        context: RecommendationContext
    ) async throws -> StylingAssistantResponse {
        let intent = parseIntent(message)
        var filtered = wardrobe.filter { !$0.isInLaundry }

        if let color = intent.requiredColor {
            filtered = filtered.filter {
                ($0.dominantColor?.lowercased().contains(color) ?? false)
                    || $0.colorPalette.contains { $0.lowercased().contains(color) }
            }
        }

        if intent.wantsWarm {
            filtered = filtered.filter {
                $0.temperatureBands.contains(.cold)
                    || $0.temperatureBands.contains(.freezing)
                    || $0.category == .coat
                    || $0.category == .jacket
                    || $0.seasons.contains(.winter)
            }
        }

        if intent.avoidSneakers {
            filtered = filtered.filter {
                !($0.category == .shoes && ($0.subcategory?.lowercased().contains("sneaker") ?? true))
            }
        }

        if !intent.avoidCategories.isEmpty {
            filtered = filtered.filter { !intent.avoidCategories.contains($0.category) }
        }

        var adjusted = context
        if let occasion = intent.occasion {
            adjusted.preferredOccasions = [occasion]
        }

        let recommendations = try await recommender.recommend(
            from: filtered.isEmpty ? wardrobe : filtered,
            context: adjusted,
            limit: 3
        )

        let reply = buildReply(intent: intent, recommendations: recommendations, context: context, emptyFilter: filtered.isEmpty && intent.hasFilters)
        return StylingAssistantResponse(reply: reply, recommendations: recommendations)
    }

    private struct Intent {
        var occasion: OutfitOccasion?
        var requiredColor: String?
        var wantsWarm: Bool = false
        var avoidSneakers: Bool = false
        var avoidCategories: [ClothingCategory] = []
        var mentionsOutside: Bool = false
        var mentionsMeeting: Bool = false
        var mentionsDinner: Bool = false

        var hasFilters: Bool {
            requiredColor != nil || wantsWarm || avoidSneakers || !avoidCategories.isEmpty || occasion != nil
        }
    }

    private func parseIntent(_ message: String) -> Intent {
        let text = message.lowercased()
        var intent = Intent()

        if text.contains("meeting") || text.contains("office") || text.contains("work") {
            intent.occasion = .office
            intent.mentionsMeeting = true
        } else if text.contains("dinner") || text.contains("date") {
            intent.occasion = .date
            intent.mentionsDinner = true
        } else if text.contains("gym") || text.contains("workout") {
            intent.occasion = .gym
        } else if text.contains("travel") || text.contains("airport") {
            intent.occasion = .airport
        } else if text.contains("wedding") {
            intent.occasion = .weddingGuest
        } else if text.contains("today") || text.contains("wear") {
            intent.occasion = nil
        }

        if text.contains("outside") || text.contains("all day") {
            intent.mentionsOutside = true
        }
        if text.contains("warm") || text.contains("cold") || text.contains("cozy") {
            intent.wantsWarm = true
        }
        if text.contains("no sneaker") || text.contains("don't want sneaker") || text.contains("dont want sneaker") || text.contains("without sneaker") {
            intent.avoidSneakers = true
        }

        let colorKeywords = ["black", "white", "blue", "red", "green", "beige", "brown", "pink", "gray", "grey", "navy"]
        for color in colorKeywords where text.contains(color) {
            intent.requiredColor = color == "grey" ? "gray" : color
            break
        }

        return intent
    }

    private func buildReply(
        intent: Intent,
        recommendations: [OutfitRecommendation],
        context: RecommendationContext,
        emptyFilter: Bool
    ) -> String {
        if recommendations.isEmpty {
            return "You may need a few more items in your wardrobe for that request. Add some photos and try again."
        }

        var lines: [String] = []

        if emptyFilter {
            lines.append("I couldn't match every filter, so I widened the search.")
        }

        if let weather = context.weather {
            lines.append(
                "It's \(weather.conditionDescription.lowercased()) and about \(Int(weather.temperatureCelsius))°C in \(weather.locationName)."
            )
        }

        if intent.mentionsMeeting {
            lines.append("For your meeting, here are neat, comfortable options.")
        } else if intent.mentionsDinner {
            lines.append("For dinner, here are options from your wardrobe.")
        } else if intent.wantsWarm {
            lines.append("I prioritized warmer layers.")
        } else {
            lines.append("Here are outfit ideas from your wardrobe:")
        }

        for (index, rec) in recommendations.enumerated() {
            let names = rec.items.map(\.name).joined(separator: " + ")
            lines.append("\(index + 1). \(rec.occasion.displayName) — \(names) (\(Int(rec.confidence * 100))% match). \(rec.rationale)")
        }

        return lines.joined(separator: "\n\n")
    }
}
