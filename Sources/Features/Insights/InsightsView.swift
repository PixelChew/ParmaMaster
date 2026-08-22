import MapKit
import SwiftData
import SwiftUI
import UIKit

struct InsightsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(InsightsStore.self) private var insightsStore
    @Environment(\.modelContext) private var modelContext
    @State private var showingInteractiveMap = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    BrandedHeading(title: "Insights")
                        .padding(.top, 16)

                    if let snapshot = insightsStore.snapshot {
                        if snapshot.insights.parmasLogged == 0 {
                            EmptyStateView(
                                title: "No parmas on the map yet",
                                systemImage: "map",
                                message: "Log a parma and its venue will appear here.",
                                actionTitle: "Log a Parma",
                                action: { router.log() }
                            )
                            .frame(minHeight: 320)
                        } else {
                            InsightsMapCard(pins: snapshot.pins) {
                                showingInteractiveMap = true
                            }
                            headlineStatistics(snapshot.insights)
                            extremeSection(snapshot.insights)
                            perfectScoresSection(snapshot.insights)
                            componentAverages(snapshot.insights)
                        }
                    } else {
                        MapPlaceholder()
                            .clipShape(.rect(cornerRadius: BrandStyle.cardRadius))
                            .overlay(RoundedRectangle(cornerRadius: BrandStyle.cardRadius).stroke(Color.primary.opacity(0.08)))
                        ProgressView("Loading insights…")
                            .frame(maxWidth: .infinity, minHeight: 160)
                    }
                }
                .padding(.horizontal, BrandStyle.pagePadding)
                .padding(.bottom, 80)
            }
            .brandPageBackground()
        }
        .task {
            await insightsStore.refresh()
            await insightsStore.preloadMapImage()
        }
        .sheet(isPresented: $showingInteractiveMap) {
            InteractiveVenueMapSheet(pins: insightsStore.snapshot?.pins ?? [], onSelectEntry: present(entryID:))
        }
    }

    private func headlineStatistics(_ insights: ParmaInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("At a glance").font(BrandStyle.displayFont(29, relativeTo: .title))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatisticCard(
                    value: "\(insights.parmasLogged)",
                    label: "Parmas logged",
                    systemImage: "fork.knife",
                    subtitle: ratingsSubmittedSubtitle(insights)
                )
                StatisticCard(
                    value: insights.averageNormalisedScore.map { $0.tenPointEquivalent.insightScoreString } ?? "—",
                    label: "Average rating",
                    systemImage: "chart.bar"
                )
                StatisticCard(
                    value: insights.highestNormalisedScore.map { $0.tenPointEquivalent.insightScoreString } ?? "—",
                    label: "Highest rating",
                    systemImage: "arrow.up.right"
                )
                StatisticCard(
                    value: insights.lowestNormalisedScore.map { $0.tenPointEquivalent.insightScoreString } ?? "—",
                    label: "Lowest rating",
                    systemImage: "arrow.down.right"
                )
                Button {
                    router.showAreasList()
                } label: {
                    StatisticCard(
                        value: "\(insights.areasVisited)",
                        label: "Areas visited",
                        systemImage: "mappin.and.ellipse"
                    )
                }
                .buttonStyle(BrandScaleButtonStyle())
                .accessibilityHint("Shows areas list")
                StatisticCard(
                    value: "\(insights.parmasLoggedThisYear)",
                    label: "Parmas logged this year",
                    systemImage: "calendar"
                )
            }
        }
    }

    private func ratingsSubmittedSubtitle(_ insights: ParmaInsights) -> String {
        let count = insights.ratingsSubmitted
        return "\(count) rating\(count == 1 ? "" : "s") submitted"
    }

    private func extremeSection(_ insights: ParmaInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Standouts").font(BrandStyle.displayFont(29, relativeTo: .title))
            VenueInsightGroup(
                title: "Highest rated",
                records: Array(insights.highestEntries.prefix(InsightsTuning.maxDisplayedStandouts)),
                action: present
            )
            VenueInsightGroup(
                title: "Lowest rated",
                records: Array(insights.lowestEntries.prefix(InsightsTuning.maxDisplayedStandouts)),
                action: present
            )
        }
    }

    private func perfectScoresSection(_ insights: ParmaInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Perfect scores").font(BrandStyle.displayFont(29, relativeTo: .title))
                Spacer()
                Text("\(insights.perfectEntries.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("\(insights.perfectEntries.count) perfect scores")
            }
            if insights.perfectEntries.isEmpty {
                ContentUnavailableView("No perfect scores yet", systemImage: "star", description: Text("The 10/10 hunt continues."))
                    .frame(maxWidth: .infinity)
                    .brandCard()
            } else {
                VenueInsightGroup(
                    title: nil,
                    records: Array(insights.perfectEntries.prefix(InsightsTuning.maxDisplayedPerfectScores)),
                    action: present
                )
            }
        }
    }

    private func componentAverages(_ insights: ParmaInsights) -> some View {
        Group {
            if !insights.componentAverages.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Component averages").font(BrandStyle.displayFont(29, relativeTo: .title))
                    VStack(spacing: 10) {
                        ForEach(RatingCategory.allCases) { category in
                            HStack {
                                Text(category.rawValue)
                                Spacer()
                                Text(insights.componentAverages[category].map { $0.tenPointEquivalent.insightScoreString } ?? "No data")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .brandCard()
                }
            }
        }
    }

    private func present(_ record: InsightsEntryRecord) {
        present(entryID: record.id)
    }

    private func present(entryID: UUID) {
        let id = entryID
        var descriptor = FetchDescriptor<ParmaEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let entry = try? modelContext.fetch(descriptor).first {
            router.presentDetails(entry)
        }
    }
}

private struct StatisticCard: View {
    let value: String
    let label: String
    let systemImage: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2.weight(.medium))
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(BrandStyle.displayFont(34, relativeTo: .title))
                .monospacedDigit()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .brandCard()
        .accessibilityElement(children: .combine)
    }
}

struct VenueInsightGroup: View {
    let title: String?
    let records: [InsightsEntryRecord]
    let action: (InsightsEntryRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.headline) }
            ForEach(records) { record in
                Button { action(record) } label: {
                    InsightEntryRow(record: record)
                }
                .buttonStyle(BrandScaleButtonStyle())
                .accessibilityHint("Opens Parma details")
                if record.id != records.last?.id { Divider() }
            }
        }
        .brandCard()
    }
}

struct InsightEntryRow: View {
    let record: InsightsEntryRecord

    var body: some View {
        HStack(spacing: 12) {
            StoredPhotoView(filename: record.photoFilename, useThumbnail: true)
                .frame(width: 86, height: 68)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.venueName).font(.headline).foregroundStyle(.primary).lineLimit(2)
                Text(record.currentRatingDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            ScoreDisplay(
                score: record.rating.total,
                maximum: record.rating.maximum,
                mode: record.rating.overallDisplayMode,
                size: 24
            )
            .fixedSize()
        }
    }
}

// MARK: - Map support

/// Kept in this established target source file so Insights does not depend on
/// Xcode discovering a newly added Swift file before these symbols are usable.
enum InsightsMapSnapshotter {
    static func image(
        pins: [VenuePin],
        region: MKCoordinateRegion,
        size: CGSize,
        scale: CGFloat,
        colorScheme: ColorScheme,
        accent: UIColor
    ) async -> UIImage? {
        guard size.width > 1, size.height > 1 else { return nil }

        var red: CGFloat = 1
        var green: CGFloat = 0.4
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        accent.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let isDark = colorScheme == .dark
        let capturedPins = pins
        let center = region.center
        let span = region.span
        let renderTask = Task.detached(priority: .utility) {
            await render(
                pins: capturedPins,
                centerLatitude: center.latitude,
                centerLongitude: center.longitude,
                latitudeDelta: span.latitudeDelta,
                longitudeDelta: span.longitudeDelta,
                size: size,
                scale: scale,
                isDark: isDark,
                accent: (red, green, blue, alpha)
            )
        }
        return await withTaskCancellationHandler {
            await renderTask.value
        } onCancel: {
            renderTask.cancel()
        }
    }

    nonisolated private static func render(
        pins: [VenuePin],
        centerLatitude: Double,
        centerLongitude: Double,
        latitudeDelta: Double,
        longitudeDelta: Double,
        size: CGSize,
        scale: CGFloat,
        isDark: Bool,
        accent: (CGFloat, CGFloat, CGFloat, CGFloat)
    ) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
        options.size = size
        options.scale = scale
        options.traitCollection = await MainActor.run {
            UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)
        }
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.pointOfInterestFilter = .excludingAll
        configuration.showsTraffic = false
        options.preferredConfiguration = configuration

        let snapshot: MKMapSnapshotter.Snapshot
        do {
            snapshot = try await MKMapSnapshotter(options: options).start()
        } catch {
            return nil
        }
        guard !Task.isCancelled else { return nil }

        let pinsToDraw = Array(pins.prefix(InsightsTuning.snapshotPinLimit))
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let accentColor = UIColor(red: accent.0, green: accent.1, blue: accent.2, alpha: accent.3)
        return renderer.image { _ in
            snapshot.image.draw(in: CGRect(origin: .zero, size: size))
            for pin in pinsToDraw {
                let point = snapshot.point(for: pin.coordinate)
                guard point.x >= -10, point.y >= -10,
                      point.x <= size.width + 10, point.y <= size.height + 10 else { continue }
                let rect = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
                accentColor.setFill()
                UIBezierPath(ovalIn: rect).fill()
                UIColor.white.setStroke()
                let ring = UIBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
                ring.lineWidth = 1.5
                ring.stroke()
            }
        }
    }
}

struct InsightsMapCard: View {
    let pins: [VenuePin]
    let onOpenInteractive: () -> Void

    @Environment(InsightsStore.self) private var insightsStore
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var renderWidth = InsightsTuning.preloadedMapWidth

    var body: some View {
        Button(action: onOpenInteractive) {
            ZStack(alignment: .bottomTrailing) {
                MapPlaceholder()
                if let image = insightsStore.mapImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: InsightsTuning.mapCardHeight)
                        .clipped()
                }
                Text("Open map")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
            }
            .frame(height: InsightsTuning.mapCardHeight)
            .clipShape(.rect(cornerRadius: BrandStyle.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: BrandStyle.cardRadius).stroke(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Parma venues map")
        .accessibilityHint("Opens an interactive map")
        .onGeometryChange(for: CGFloat.self) { proxy in
            max(proxy.size.width, 1)
        } action: { width in
            renderWidth = width
        }
        .task(id: "\(colorScheme)-\(displayScale)-\(settings.accentHex)-\(renderWidth.rounded())-\(pins.count)") {
            await insightsStore.preloadMapImage(
                size: CGSize(width: renderWidth, height: InsightsTuning.mapCardHeight),
                colorScheme: colorScheme,
                displayScale: displayScale,
                accent: UIColor(settings.accentColor)
            )
        }
    }
}

struct InteractiveVenueMapSheet: View {
    let pins: [VenuePin]
    let onSelectEntry: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            InteractiveVenueMapView(
                pins: pins,
                region: ParmaInsightsCalculator.mapRegion(for: pins),
                onSelectEntry: { entryID in
                    dismiss()
                    onSelectEntry(entryID)
                }
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Venues")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct InteractiveVenueMapView: UIViewRepresentable {
    let pins: [VenuePin]
    let region: MKCoordinateRegion
    let onSelectEntry: (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectEntry: onSelectEntry, pinCount: pins.count)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.pointOfInterestFilter = .excludingAll
        configuration.showsTraffic = false
        mapView.preferredConfiguration = configuration
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.showsUserLocation = false
        mapView.delegate = context.coordinator
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.markerReuseID)
        mapView.setRegion(region, animated: false)
        mapView.addAnnotations(Self.annotations(from: pins))
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onSelectEntry = onSelectEntry
        context.coordinator.pinCount = pins.count
        let incoming = Set(pins.map(\.id))
        let existing = Set(mapView.annotations.compactMap { ($0 as? VenuePointAnnotation)?.pinID })
        guard incoming != existing else { return }
        let ours = mapView.annotations.filter { $0 is VenuePointAnnotation }
        mapView.removeAnnotations(ours)
        mapView.addAnnotations(Self.annotations(from: pins))
        mapView.setRegion(region, animated: false)
    }

    private static func annotations(from pins: [VenuePin]) -> [VenuePointAnnotation] {
        pins.map { pin in
            let annotation = VenuePointAnnotation(pinID: pin.id, entryID: pin.entryID)
            annotation.coordinate = pin.coordinate
            annotation.title = pin.scoreText
            annotation.subtitle = pin.title
            return annotation
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        static let markerReuseID = "ParmaVenueMarker"
        var onSelectEntry: (UUID) -> Void
        var pinCount: Int

        init(onSelectEntry: @escaping (UUID) -> Void, pinCount: Int) {
            self.onSelectEntry = onSelectEntry
            self.pinCount = pinCount
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if annotation is MKClusterAnnotation { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.markerReuseID,
                for: annotation
            ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: Self.markerReuseID)
            view.annotation = annotation
            view.clusteringIdentifier = "parma-venue"
            view.markerTintColor = .tintColor
            view.glyphImage = UIImage(systemName: "fork.knife")
            view.displayPriority = .defaultHigh
            view.titleVisibility = pinCount > InsightsTuning.densePinThreshold ? .hidden : .visible
            view.subtitleVisibility = .hidden
            view.canShowCallout = true
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
                mapView.deselectAnnotation(cluster, animated: false)
                return
            }
            guard let pin = view.annotation as? VenuePointAnnotation else { return }
            onSelectEntry(pin.entryID)
        }
    }
}

final class VenuePointAnnotation: MKPointAnnotation, @unchecked Sendable {
    let pinID: UUID
    let entryID: UUID

    init(pinID: UUID, entryID: UUID) {
        self.pinID = pinID
        self.entryID = entryID
        super.init()
    }
}

struct MapPlaceholder: View {
    var body: some View {
        Color(.secondarySystemBackground)
            .frame(height: InsightsTuning.mapCardHeight)
            .overlay {
                Image(systemName: "map")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityHidden(true)
    }
}
