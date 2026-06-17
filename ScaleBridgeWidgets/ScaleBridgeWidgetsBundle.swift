import WidgetKit
import SwiftUI

@main
struct ScaleBridgeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ScaleBridgeWeightWidget()
        ScaleBridgeOverviewWidget()
        ScaleBridgeChartWidget()
        ScaleBridgeLargeChartWidget()
        ScaleBridgeLockCircleWidget()
        ScaleBridgeLockRectWidget()
        ScaleBridgeWidgetsControl()
        ScaleBridgeWidgetsLiveActivity()
    }
}
