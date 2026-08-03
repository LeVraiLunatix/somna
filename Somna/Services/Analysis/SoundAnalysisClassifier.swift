import Foundation
import OSLog
import SoundAnalysis

/// Classification via Apple's built-in sound classifier.
///
/// Somna ships no model of its own. `SNClassifySoundRequest(.version1)` covers
/// several hundred classes — snoring, coughing, speech, doors, rain, animals —
/// runs on the Neural Engine, and never leaves the device. Training a worse
/// classifier to own it would have been vanity.
///
/// It runs on **files**, in the morning, far faster than real time. Nothing here
/// touches the night itself.
actor SoundAnalysisClassifier: SoundClassifying {

    /// Cached because building a request just to read its class list is wasteful,
    /// and the list cannot change while the app is running.
    private var cachedIdentifiers: [String]?

    func availableIdentifiers() async -> [String] {
        if let cachedIdentifiers { return cachedIdentifiers }

        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            let identifiers = request.knownClassifications
            cachedIdentifiers = identifiers

            // Checked against what Somna relies on, so a label that disappeared
            // in an OS update is discovered here rather than inferred from a
            // night that mysteriously found no snoring.
            let missing = ClassificationMapping.missingExpectedPatterns(in: identifiers)
            if !missing.isEmpty {
                Log.analysis.error("Classifier is missing expected classes: \(missing.joined(separator: ", "), privacy: .public)")
            }
            return identifiers
        } catch {
            Log.analysis.error("Sound classifier could not be created")
            return []
        }
    }

    func classify(fileURL: URL, offset: TimeInterval) async throws -> [SoundClassification] {
        let analyzer: SNAudioFileAnalyzer
        let request: SNClassifySoundRequest

        do {
            analyzer = try SNAudioFileAnalyzer(url: fileURL)
            request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        } catch {
            Log.analysis.error("Could not open segment for analysis")
            throw AnalysisError.classifierUnavailable
        }

        // Overlapping windows so a sound straddling a boundary is not halved and
        // scored twice as weakly.
        request.overlapFactor = 0.5

        let collector = ClassificationCollector(offset: offset)

        do {
            try analyzer.add(request, withObserver: collector)
        } catch {
            throw AnalysisError.classifierUnavailable
        }

        await withCheckedContinuation { continuation in
            analyzer.analyze { _ in
                continuation.resume()
            }
        }

        return collector.results
    }
}

/// Gathers results from `SNAudioFileAnalyzer`.
///
/// A class because `SNResultsObserving` is an Objective-C protocol. Its callbacks
/// arrive serially on one queue, which is what makes the unchecked conformance
/// defensible: there is no concurrent access to defend against, and the results
/// are read only after `analyze` has completed.
private final class ClassificationCollector: NSObject, SNResultsObserving, @unchecked Sendable {

    private(set) var results: [SoundClassification] = []
    private let offset: TimeInterval

    /// Below this, results are not worth carrying: the refiner and the
    /// confidence thresholds would discard them anyway, and a busy night can
    /// otherwise produce tens of thousands of them.
    private let retentionFloor = 0.25

    init(offset: TimeInterval) {
        self.offset = offset
        super.init()
    }

    func request(_ request: any SNRequest, didProduce result: any SNResult) {
        guard let classification = result as? SNClassificationResult else { return }

        // Only the top class per window. Keeping the runners-up would let the
        // same instant appear as three different events on one timeline.
        guard let best = classification.classifications.first,
              best.confidence >= retentionFloor
        else { return }

        if ClassificationMapping.type(for: best.identifier) == .unknown {
            ClassificationMapping.noteUnmapped(best.identifier, confidence: best.confidence)
        }

        results.append(SoundClassification(
            identifier: best.identifier,
            confidence: best.confidence,
            start: offset + classification.timeRange.start.seconds,
            duration: classification.timeRange.duration.seconds
        ))
    }

    func request(_ request: any SNRequest, didFailWithError error: any Error) {
        // A segment that fails to analyse is skipped, never fatal: one unreadable
        // ten-minute file must not cost the other seven and a half hours.
        Log.analysis.error("Segment analysis failed; skipping it")
    }

    func requestDidComplete(_ request: any SNRequest) {}
}

/// A classifier with scripted answers, for previews and tests.
struct StubSoundClassifier: SoundClassifying {

    let scripted: [SoundClassification]

    init(_ scripted: [SoundClassification] = []) {
        self.scripted = scripted
    }

    func classify(fileURL: URL, offset: TimeInterval) async throws -> [SoundClassification] {
        scripted
    }

    func availableIdentifiers() async -> [String] {
        ["snoring", "coughing", "speech", "breathing", "door", "rain"]
    }
}
