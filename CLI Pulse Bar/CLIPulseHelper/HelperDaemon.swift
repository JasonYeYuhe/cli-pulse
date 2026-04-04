#if os(macOS)
import Foundation
import AppKit
import CLIPulseCore
import os

/// Core daemon that collects local data and syncs to Supabase.
/// Runs on a background DispatchSourceTimer every N seconds.
final class HelperDaemon {
    private let logger = Logger(subsystem: "yyh.CLI-Pulse.helper", category: "daemon")
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.clipulse.helper.daemon", qos: .utility)
    private let apiClient = HelperAPIClient()
    private var isRunning = false
    /// Protected by `syncLock` to prevent concurrent sync cycles.
    private var isSyncing = false
    private let syncLock = NSLock()
    private var suspendCount = 0

    /// Default sync interval (seconds). Can be overridden via shared UserDefaults.
    private var syncInterval: Int {
        let defaults = UserDefaults(suiteName: HelperIPC.suiteName)
        let stored = defaults?.integer(forKey: HelperIPC.syncIntervalKey) ?? 0
        return stored >= 60 ? stored : 120
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        logger.info("Daemon starting, interval=\(self.syncInterval)s")

        // Initial sync immediately
        Task { await collectAndSync() }

        // Set up repeating timer
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + .seconds(syncInterval), repeating: .seconds(syncInterval))
        source.setEventHandler { [weak self] in
            Task { [weak self] in await self?.collectAndSync() }
        }
        source.resume()
        timer = source

        // Sleep/wake handling
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func stop() {
        // Resume before cancel to avoid crash on suspended source
        if suspendCount > 0 {
            timer?.resume()
            suspendCount = 0
        }
        timer?.cancel()
        timer = nil
        isRunning = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        logger.info("Daemon stopped")
    }

    // MARK: - Sleep/Wake

    @objc private func willSleep() {
        guard suspendCount == 0 else { return }
        suspendCount += 1
        timer?.suspend()
        logger.info("System sleeping — paused timer")
    }

    @objc private func didWake() {
        guard suspendCount > 0 else { return }
        suspendCount -= 1
        timer?.resume()
        logger.info("System woke — resumed timer + immediate sync")
        Task { [weak self] in await self?.collectAndSync() }
    }

    // MARK: - Collection + Sync (fully async)

    private func collectAndSync() async {
        // Thread-safe check-and-set to prevent concurrent sync cycles
        syncLock.lock()
        guard !isSyncing else {
            syncLock.unlock()
            logger.debug("Sync already in progress — skipping")
            return
        }
        isSyncing = true
        syncLock.unlock()
        defer { syncLock.lock(); isSyncing = false; syncLock.unlock() }

        guard let config = HelperConfig.load() else {
            logger.warning("No helper config found — waiting for pairing")
            return
        }

        logger.info("Starting collection cycle")

        // Step 1: Device metrics
        let device = DeviceMetrics.collect()
        logger.debug("Device: cpu=\(device.cpuUsage)%, mem=\(device.memoryUsage)%")

        // Step 2: Sessions via LocalScanner
        let scanResult = LocalScanner.shared.scan()
        logger.debug("Scanned \(scanResult.sessions.count) sessions")

        // Step 3: Alerts
        let alerts = AlertGenerator.generate(
            device: device,
            sessions: scanResult.sessions
        )

        // Step 4: Provider quotas via collectors
        let providerTiers = await collectProviderQuotas(sessions: scanResult.sessions)

        // Step 5-6: Sync to Supabase
        let sessionDicts = scanResult.sessions.map { sessionToDict($0) }
        let providerRemaining: [String: Int] = providerTiers.compactMapValues { dict in
            (dict as? [String: Any])?["remaining"] as? Int
        }

        do {
            // Heartbeat
            try await apiClient.heartbeat(
                config: config,
                cpuUsage: device.cpuUsage,
                memoryUsage: device.memoryUsage,
                activeSessionCount: scanResult.activeSessionCount
            )

            // Sync
            let result = try await apiClient.sync(
                config: config,
                sessions: sessionDicts,
                alerts: alerts,
                providerRemaining: providerRemaining,
                providerTiers: providerTiers
            )
            logger.info("Synced \(result.sessionsSynced) sessions, \(result.alertsSynced) alerts")

            // Update status
            HelperIPC.writeStatus(HelperIPC.Status(
                state: .running, lastSync: Date(), helperVersion: "1.0.0"
            ))
            HelperIPC.postSyncNotification()

        } catch {
            logger.error("Sync failed: \(error.localizedDescription)")
            HelperIPC.writeStatus(HelperIPC.Status(
                state: .error, lastSync: nil, error: error.localizedDescription, helperVersion: "1.0.0"
            ))
        }
    }

    // MARK: - Provider Quota Collection

    /// Run the same collectors the main app uses, producing tier data for Supabase.
    private func collectProviderQuotas(sessions: [SessionRecord]) async -> [String: Any] {
        let activeProviders = Set(sessions.map(\.provider))
        var result: [String: Any] = [:]

        // Read provider configs from shared app group (written by main app)
        var configs: [ProviderConfig] = ProviderConfig.defaults()
        if let defaults = UserDefaults(suiteName: HelperIPC.suiteName),
           let data = defaults.data(forKey: HelperIPC.providerConfigsKey),
           let saved = try? JSONDecoder().decode([ProviderConfig].self, from: data) {
            configs = saved
            // Hydrate secrets from Keychain
            for i in configs.indices {
                configs[i].loadSecrets()
            }
        }

        for collector in CollectorRegistry.collectors {
            let providerName = collector.kind.rawValue
            guard activeProviders.contains(providerName) else { continue }

            let config = configs.first(where: { $0.kind == collector.kind }) ?? ProviderConfig(kind: collector.kind)
            guard collector.isAvailable(config: config) else { continue }

            do {
                let collectorResult = try await collector.collect(config: config)
                let usage = collectorResult.usage

                var tierData: [String: Any] = [
                    "quota": usage.quota ?? 100,
                    "remaining": usage.remaining ?? 100,
                ]
                if let planType = usage.plan_type { tierData["plan_type"] = planType }
                if let resetTime = usage.reset_time { tierData["reset_time"] = resetTime }

                let tiers: [[String: Any]] = usage.tiers.map { tier in
                    var d: [String: Any] = [
                        "name": tier.name,
                        "quota": tier.quota,
                        "remaining": tier.remaining,
                    ]
                    if let rt = tier.reset_time { d["reset_time"] = rt }
                    return d
                }
                tierData["tiers"] = tiers

                result[providerName] = tierData
                logger.debug("Collected \(providerName): \(usage.tiers.count) tiers")
            } catch {
                logger.warning("Collector failed for \(providerName): \(error.localizedDescription)")
            }
        }

        return result
    }

    // MARK: - Helpers

    private func sessionToDict(_ session: SessionRecord) -> [String: Any] {
        [
            "id": session.id,
            "name": session.name,
            "provider": session.provider,
            "project": session.project,
            "status": session.status,
            "total_usage": session.total_usage,
            "exact_cost": session.estimated_cost,
            "requests": session.requests,
            "error_count": session.error_count,
            "collection_confidence": session.collection_confidence ?? "medium",
            "started_at": session.started_at,
            "last_active_at": session.last_active_at,
        ]
    }
}
#endif
