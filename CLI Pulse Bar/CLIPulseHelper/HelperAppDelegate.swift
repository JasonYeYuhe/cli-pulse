import AppKit
import CLIPulseCore
import os

final class HelperAppDelegate: NSObject, NSApplicationDelegate {
    private let daemon = HelperDaemon()
    private let logger = Logger(subsystem: "yyh.CLI-Pulse.helper", category: "lifecycle")

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("CLIPulseHelper launched")
        HelperIPC.writeStatus(HelperIPC.Status(state: .running, helperVersion: "1.0.0"))
        HelperIPC.postStartNotification()
        daemon.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("CLIPulseHelper terminating")
        daemon.stop()
        HelperIPC.writeStatus(HelperIPC.Status(state: .idle, helperVersion: "1.0.0"))
    }
}
