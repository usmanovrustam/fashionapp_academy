import WidgetKit
import SwiftUI

@main
struct NookWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayOutfitWidget()
        WardrobeGlanceWidget()
    }
}
