import XCTest
@testable import FreeBook

final class RemoteTTSSynthesisCoordinatorTests: XCTestCase {
    private actor Probe {
        var active = 0
        var maximumActive = 0
        var calls = 0
        var order: [String] = []

        func begin(_ name: String) {
            active += 1
            calls += 1
            maximumActive = max(maximumActive, active)
            order.append(name)
        }

        func end() {
            active -= 1
        }
    }

    func testSerializesDifferentSynthesisJobs() async throws {
        let coordinator = RemoteTTSSynthesisCoordinator()
        let probe = Probe()

        async let first = coordinator.synthesize(key: "first", priority: .prefetch) {
            await probe.begin("first")
            try await Task.sleep(nanoseconds: 80_000_000)
            await probe.end()
            return Data([1])
        }
        async let second = coordinator.synthesize(key: "second", priority: .prefetch) {
            await probe.begin("second")
            try await Task.sleep(nanoseconds: 30_000_000)
            await probe.end()
            return Data([2])
        }
        async let third = coordinator.synthesize(key: "third", priority: .prefetch) {
            await probe.begin("third")
            try await Task.sleep(nanoseconds: 30_000_000)
            await probe.end()
            return Data([3])
        }

        _ = try await [first, second, third]
        let maximumActive = await probe.maximumActive
        XCTAssertEqual(maximumActive, 1)
    }

    func testDeduplicatesMatchingKeys() async throws {
        let coordinator = RemoteTTSSynthesisCoordinator()
        let probe = Probe()

        let first = Task {
            try await coordinator.synthesize(key: "same", priority: .prefetch) {
                await probe.begin("original")
                try await Task.sleep(nanoseconds: 80_000_000)
                await probe.end()
                return Data([7])
            }
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        let duplicate = Task {
            try await coordinator.synthesize(key: "same", priority: .current) {
                await probe.begin("duplicate")
                await probe.end()
                return Data([8])
            }
        }

        let values = try await [first.value, duplicate.value]
        let calls = await probe.calls
        XCTAssertEqual(values, [Data([7]), Data([7])])
        XCTAssertEqual(calls, 1)
    }

    func testCurrentPriorityJumpsAheadOfQueuedPrefetch() async throws {
        let coordinator = RemoteTTSSynthesisCoordinator()
        let probe = Probe()

        let blocker = Task {
            try await coordinator.synthesize(key: "blocker", priority: .prefetch) {
                await probe.begin("blocker")
                try await Task.sleep(nanoseconds: 100_000_000)
                await probe.end()
                return Data()
            }
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        let future = Task {
            try await coordinator.synthesize(key: "future", priority: .prefetch) {
                await probe.begin("future")
                await probe.end()
                return Data()
            }
        }
        let current = Task {
            try await coordinator.synthesize(key: "current", priority: .current) {
                await probe.begin("current")
                await probe.end()
                return Data()
            }
        }

        _ = try await (blocker.value, future.value, current.value)
        let order = await probe.order
        XCTAssertEqual(order, ["blocker", "current", "future"])
    }

    func testEnergyPredictionDistinguishesBackgroundRemoteLoad() {
        XCTAssertEqual(
            RemoteTTSSynthesisCoordinator.energyPrediction(
                applicationState: "background",
                requestsPerMinute: 16,
                busyPercent: 20,
                thermalState: .nominal
            ),
            "background_remote_load_likely"
        )
        XCTAssertEqual(
            RemoteTTSSynthesisCoordinator.energyPrediction(
                applicationState: "foreground",
                requestsPerMinute: 5,
                busyPercent: 15,
                thermalState: .nominal
            ),
            "remote_load_low"
        )
        XCTAssertEqual(
            RemoteTTSSynthesisCoordinator.energyPrediction(
                applicationState: "background",
                requestsPerMinute: 5,
                busyPercent: 15,
                thermalState: .serious
            ),
            "thermal_pressure_confirmed"
        )
    }

    func testFirstEnqueueWithLoggingEnabledDoesNotTriggerExclusiveAccessTrap() async throws {
        let previousLoggingState = AppLogger.shared.isLoggingEnabled
        AppLogger.shared.isLoggingEnabled = true
        defer { AppLogger.shared.isLoggingEnabled = previousLoggingState }

        let coordinator = RemoteTTSSynthesisCoordinator()
        let result = try await coordinator.synthesize(
            key: "logging-enabled",
            engine: "test",
            textLength: 12,
            priority: .current
        ) {
            Data([1, 2, 3])
        }

        XCTAssertEqual(result, Data([1, 2, 3]))
    }
}
