import Foundation
import Observation
import SwiftData
import SwiftUI
import UIKit

actor InsightsComputer {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func makeSnapshot() throws -> InsightsSnapshot {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        var descriptor = FetchDescriptor<ParmaEntry>(
            sortBy: [SortDescriptor(\ParmaEntry.currentRatingDate, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\ParmaEntry.venue, \ParmaEntry.revisions]
        let entries = try context.fetch(descriptor)
        let records = ParmaInsightsCalculator.records(from: entries)
        let insights = ParmaInsightsCalculator.calculate(records)
        let pins = ParmaInsightsCalculator.venuePins(from: records)
        return InsightsSnapshot(
            cacheKey: ParmaInsightsCalculator.cacheKey(for: records),
            insights: insights,
            pins: pins,
            mapCacheSignature: ParmaInsightsCalculator.mapCacheSignature(for: pins),
            areas: AreaAggregator.areas(from: records)
        )
    }
}

@MainActor
@Observable
final class InsightsStore {
    private(set) var snapshot: InsightsSnapshot?
    private(set) var mapImage: UIImage?
    private(set) var isLoading = false

    @ObservationIgnored private var computer: InsightsComputer?
    @ObservationIgnored private var isStale = true
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var refreshTask: Task<InsightsSnapshot, Error>?
    @ObservationIgnored private var refreshTaskToken: Int?
    @ObservationIgnored private var mapImageKey: String?
    @ObservationIgnored private var mapRenderKey: String?
    @ObservationIgnored private var mapRenderTask: Task<UIImage?, Never>?

    func configure(container: ModelContainer) {
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        refreshTaskToken = nil
        mapRenderTask?.cancel()
        mapRenderTask = nil
        mapRenderKey = nil
        mapImageKey = nil
        mapImage = nil
        snapshot = nil
        isStale = true
        computer = InsightsComputer(modelContainer: container)
    }

    func invalidate() {
        isStale = true
        Task { [weak self] in
            guard let self else { return }
            await refresh(force: true)
            await preloadMapImage()
        }
    }

    func refresh(force: Bool = false) async {
        guard let computer else { return }
        if !force, !isStale, snapshot != nil { return }

        let token: Int
        let task: Task<InsightsSnapshot, Error>
        if !force, let pending = refreshTask, let pendingToken = refreshTaskToken {
            token = pendingToken
            task = pending
        } else {
            generation += 1
            token = generation
            refreshTask?.cancel()
            mapRenderTask?.cancel()
            mapRenderTask = nil
            mapRenderKey = nil
            task = Task { try await computer.makeSnapshot() }
            refreshTask = task
            refreshTaskToken = token
        }
        isLoading = snapshot == nil
        do {
            let result = try await task.value
            guard token == generation else { return }
            snapshot = result
            isStale = false
        } catch {
            if !(error is CancellationError) {
                AppLog.data.error("Insights snapshot failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if refreshTaskToken == token {
            refreshTask = nil
            refreshTaskToken = nil
        }
        if token == generation {
            isLoading = false
        }
    }

    /// Builds the static Insights map off the main thread so the tab can show
    /// it immediately when selected. Safe to call again; identical keys no-op.
    func preloadMapImage(
        size: CGSize = CGSize(
            width: InsightsTuning.preloadedMapWidth,
            height: InsightsTuning.mapCardHeight
        ),
        colorScheme: ColorScheme? = nil,
        displayScale: CGFloat? = nil,
        accent: UIColor? = nil
    ) async {
        guard let snapshot, !snapshot.pins.isEmpty else {
            mapRenderTask?.cancel()
            mapRenderTask = nil
            mapRenderKey = nil
            mapImage = nil
            mapImageKey = nil
            return
        }
        let scheme = colorScheme ?? resolvedColorScheme()
        let scale = max(displayScale ?? UITraitCollection.current.displayScale, 1)
        let renderSize = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        let accentColor = accent ?? UIColor(Color.accentColor)
        let accentComponents = accentColor.rgbaComponents
        let key = [
            snapshot.mapCacheSignature.description,
            scheme == .dark ? "dark" : "light",
            String(describing: scale),
            String(format: "%.0fx%.0f", renderSize.width, renderSize.height),
            accentComponents.map { String(format: "%.4f", $0) }.joined(separator: ",")
        ].joined(separator: "|")
        if key == mapImageKey, mapImage != nil { return }

        let token = generation
        if key == mapRenderKey, let mapRenderTask {
            let image = await mapRenderTask.value
            guard token == generation, key == mapRenderKey else { return }
            if let image {
                mapImage = image
                mapImageKey = key
            }
            return
        }

        mapRenderTask?.cancel()
        let region = ParmaInsightsCalculator.mapRegion(for: snapshot.pins)
        let task = Task {
            await InsightsMapSnapshotter.image(
                pins: snapshot.pins,
                region: region,
                size: renderSize,
                scale: scale,
                colorScheme: scheme,
                accent: accentColor
            )
        }
        mapRenderTask = task
        mapRenderKey = key
        let image = await task.value
        guard token == generation, key == mapRenderKey else { return }
        mapRenderTask = nil
        mapRenderKey = nil
        if let image {
            mapImage = image
            mapImageKey = key
        }
    }

    private func resolvedColorScheme() -> ColorScheme {
        UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
    }
}

private extension UIColor {
    var rgbaComponents: [CGFloat] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return [0, 0, 0, 0]
        }
        return [red, green, blue, alpha]
    }
}
