import WidgetKit
import SwiftUI

@main
struct CLIPulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageOverviewWidget()
        ProviderUsageWidget()
        #if os(iOS)
        if #available(iOSApplicationExtension 17.0, *) {
            UsageLockScreenWidget()
        }
        #endif
        #if os(watchOS)
        if #available(watchOSApplicationExtension 10.0, *) {
            WatchComplicationWidget()
        }
        #endif
    }
}
