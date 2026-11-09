import CoreData
import Foundation

final class PersistenceController {
    enum Entity {
        static let likedTrack = "LikedTrack"
        static let history = "HistoryEntry"
        static let playlist = "Playlist"
        static let playlistItem = "PlaylistItem"
    }

    static let shared = PersistenceController()

    let container: NSPersistentContainer
    let isFallbackStore: Bool

    init(inMemory: Bool = false) {
        let model = Self.makeModel()
        let candidate = NSPersistentContainer(name: "Volna", managedObjectModel: model)

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            candidate.persistentStoreDescriptions = [description]
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let directory = support.appendingPathComponent("Volna", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("Volna.sqlite")
            let description = NSPersistentStoreDescription(url: url)
            description.type = NSSQLiteStoreType
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            candidate.persistentStoreDescriptions = [description]
        }

        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        candidate.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 12)

        if loadError != nil || candidate.persistentStoreCoordinator.persistentStores.isEmpty {
            let memory = NSPersistentContainer(name: "Volna", managedObjectModel: model)
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            memory.persistentStoreDescriptions = [description]
            let memorySemaphore = DispatchSemaphore(value: 0)
            memory.loadPersistentStores { _, _ in memorySemaphore.signal() }
            _ = memorySemaphore.wait(timeout: .now() + 5)
            container = memory
            isFallbackStore = true
        } else {
            container = candidate
            isFallbackStore = false
        }

        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.undoManager = nil
    }

    func saveViewContext() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            AppLog.debug("Core Data save failed: \(error.localizedDescription)")
        }
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let liked = NSEntityDescription()
        liked.name = Entity.likedTrack
        liked.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        liked.properties = [
            attribute("trackID", .stringAttributeType),
            attribute("payload", .binaryDataAttributeType),
            attribute("likedAt", .dateAttributeType)
        ]

        let history = NSEntityDescription()
        history.name = Entity.history
        history.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        history.properties = [
            attribute("entryID", .UUIDAttributeType),
            attribute("trackID", .stringAttributeType),
            attribute("payload", .binaryDataAttributeType),
            attribute("playedAt", .dateAttributeType)
        ]

        let playlist = NSEntityDescription()
        playlist.name = Entity.playlist
        playlist.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let item = NSEntityDescription()
        item.name = Entity.playlistItem
        item.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let itemsRelationship = NSRelationshipDescription()
        itemsRelationship.name = "items"
        itemsRelationship.destinationEntity = item
        itemsRelationship.minCount = 0
        itemsRelationship.maxCount = 0
        itemsRelationship.deleteRule = .cascadeDeleteRule
        itemsRelationship.isOptional = true

        let playlistRelationship = NSRelationshipDescription()
        playlistRelationship.name = "playlist"
        playlistRelationship.destinationEntity = playlist
        playlistRelationship.minCount = 0
        playlistRelationship.maxCount = 1
        playlistRelationship.deleteRule = .nullifyDeleteRule
        playlistRelationship.isOptional = true

        itemsRelationship.inverseRelationship = playlistRelationship
        playlistRelationship.inverseRelationship = itemsRelationship

        playlist.properties = [
            attribute("playlistID", .UUIDAttributeType),
            attribute("title", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            itemsRelationship
        ]

        item.properties = [
            attribute("itemID", .UUIDAttributeType),
            attribute("trackID", .stringAttributeType),
            attribute("payload", .binaryDataAttributeType),
            attribute("position", .integer64AttributeType),
            playlistRelationship
        ]

        model.entities = [liked, history, playlist, item]
        return model
    }

    private static func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }
}
