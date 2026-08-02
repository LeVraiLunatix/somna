import Foundation
import SwiftData
import OSLog

/// Version 1 of the persistent schema.
///
/// Versioned from the first release even though there is nothing to migrate yet.
/// Retrofitting a `VersionedSchema` onto an unversioned store is painful, and
/// beta testers will be carrying real nights they do not want to lose.
enum SomnaSchemaV1: VersionedSchema {

    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            SDNightSession.self,
            SDNightEvent.self,
            SDAudioSegment.self,
            SDCalibrationProfile.self,
        ]
    }
}

/// Migration plan.
///
/// Empty by design: with a single schema there is nothing to stage. It exists so
/// that adding V2 is a matter of appending to two arrays rather than restructuring
/// how the container is built.
enum SomnaMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [SomnaSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

/// Builds the `ModelContainer`.
enum ModelContainerFactory {

    /// - Parameter inMemory: used by tests and previews so no suite ever touches
    ///   a real user's nights.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SomnaSchemaV1.self)

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true,
            // Explicit rather than implicit: Somna is local-first, and a stray
            // CloudKit database here would silently start syncing sleep data.
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: SomnaMigrationPlan.self,
                configurations: configuration
            )
        } catch {
            Log.persistence.error("Model container failed to open: \(error.localizedDescription, privacy: .public)")
            throw SomnaError.persistenceUnavailable(underlying: String(describing: type(of: error)))
        }
    }
}
