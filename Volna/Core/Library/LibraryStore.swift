import CoreData
import Foundation
import SwiftUI

struct PlayedTrack: Identifiable, Hashable {
    let id: UUID
    let track: Track
    let playedAt: Date
}

struct PlaylistSummary: Identifiable, Hashable {
    let id: UUID
    let title: String
    let trackCount: Int
    let updatedAt: Date
    let artworkURLs: [URL]
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var likedTracks: [Track] = []
    @Published private(set) var history: [PlayedTrack] = []
    @Published private(set) var playlists: [PlaylistSummary] = []
    @Published private(set) var lastError: String?

    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }
    private var likedIDs: Set<String> = []
    private var playCounter = 0
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
        reload()
    }

    var isUsingFallbackStore: Bool {
        persistence.isFallbackStore
    }

    func reload() {
        reloadLikes()
        reloadHistory()
        reloadPlaylists()
    }

    func isLiked(_ track: Track) -> Bool {
        likedIDs.contains(track.id)
    }

    @discardableResult
    func toggleLike(_ track: Track) -> Bool {
        let request = NSFetchRequest<NSManagedObject>(entityName: PersistenceController.Entity.likedTrack)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "trackID == %@", track.id)

        do {
            if let existing = try context.fetch(request).first {
                context.delete(existing)
                likedIDs.remove(track.id)
                persistence.saveViewContext()
                reloadLikes()
                return false
            }

            guard let payload = try? encoder.encode(track) else { return isLiked(track) }
            let object = NSEntityDescription.insertNewObject(
                forEntityName: PersistenceController.Entity.likedTrack,
                into: context
            )
            object.setValue(track.id, forKey: "trackID")
            object.setValue(payload, forKey: "payload")
            object.setValue(Date(), forKey: "likedAt")
            likedIDs.insert(track.id)
            persistence.saveViewContext()
            reloadLikes()
            return true
        } catch {
            lastError = error.localizedDescription
            return isLiked(track)
        }
    }

    func recordPlay(_ track: Track) {
        let request = NSFetchRequest<NSManagedObject>(entityName: PersistenceController.Entity.history)
        request.sortDescriptors = [NSSortDescriptor(key: "playedAt", ascending: false)]
        request.fetchLimit = 1

        if let latest = try? context.fetch(request).first,
           latest.value(forKey: "trackID") as? String == track.id,
           let date = latest.value(forKey: "playedAt") as? Date,
           Date().timeIntervalSince(date) < 60 {
            return
        }

        guard let payload = try? encoder.encode(track) else { return }
        let object = NSEntityDescription.insertNewObject(
            forEntityName: PersistenceController.Entity.history,
            into: context
        )
        object.setValue(UUID(), forKey: "entryID")
        object.setValue(track.id, forKey: "trackID")
        object.setValue(payload, forKey: "payload")
        object.setValue(Date(), forKey: "playedAt")

        playCounter += 1
        if playCounter % 25 == 0 {
            pruneHistory()
        }
        persistence.saveViewContext()
        reloadHistory()
    }

    func clearHistory() {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: PersistenceController.Entity.history)
        let delete = NSBatchDeleteRequest(fetchRequest: request)
        delete.resultType = .resultTypeObjectIDs
        do {
            let result = try context.execute(delete) as? NSBatchDeleteResult
            if let ids = result?.result as? [NSManagedObjectID] {
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: [NSDeletedObjectsKey: ids],
                    into: [context]
                )
            }
            persistence.saveViewContext()
            reloadHistory()
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func createPlaylist(title: String) -> PlaylistSummary? {
        let value = title.trimmed
        guard !value.isEmpty else { return nil }

        let object = NSEntityDescription.insertNewObject(
            forEntityName: PersistenceController.Entity.playlist,
            into: context
        )
        let id = UUID()
        let now = Date()
        object.setValue(id, forKey: "playlistID")
        object.setValue(value, forKey: "title")
        object.setValue(now, forKey: "createdAt")
        object.setValue(now, forKey: "updatedAt")
        persistence.saveViewContext()
        reloadPlaylists()
        return playlists.first(where: { $0.id == id })
    }

    func deletePlaylist(id: UUID) {
        guard let playlist = fetchPlaylist(id: id) else { return }
        context.delete(playlist)
        persistence.saveViewContext()
        reloadPlaylists()
    }

    func renamePlaylist(id: UUID, title: String) {
        let value = title.trimmed
        guard !value.isEmpty, let playlist = fetchPlaylist(id: id) else { return }
        playlist.setValue(value, forKey: "title")
        playlist.setValue(Date(), forKey: "updatedAt")
        persistence.saveViewContext()
        reloadPlaylists()
    }

    func add(_ track: Track, to playlistID: UUID) {
        guard let playlist = fetchPlaylist(id: playlistID) else { return }
        let existing = playlistItems(for: playlist)
        guard !existing.contains(where: { $0.value(forKey: "trackID") as? String == track.id }) else {
            return
        }
        guard let payload = try? encoder.encode(track) else { return }

        let object = NSEntityDescription.insertNewObject(
            forEntityName: PersistenceController.Entity.playlistItem,
            into: context
        )
        let maxPosition = existing.compactMap { ($0.value(forKey: "position") as? NSNumber)?.int64Value }.max() ?? -1
        object.setValue(UUID(), forKey: "itemID")
        object.setValue(track.id, forKey: "trackID")
        object.setValue(payload, forKey: "payload")
        object.setValue(maxPosition + 1, forKey: "position")
        object.setValue(playlist, forKey: "playlist")
        playlist.setValue(Date(), forKey: "updatedAt")
        persistence.saveViewContext()
        reloadPlaylists()
    }

    func remove(trackID: String, from playlistID: UUID) {
        guard let playlist = fetchPlaylist(id: playlistID) else { return }
        if let item = playlistItems(for: playlist).first(where: { $0.value(forKey: "trackID") as? String == trackID }) {
            context.delete(item)
            playlist.setValue(Date(), forKey: "updatedAt")
            persistence.saveViewContext()
            reloadPlaylists()
        }
    }

    func tracks(in playlistID: UUID) -> [Track] {
        guard let playlist = fetchPlaylist(id: playlistID) else { return [] }
        return playlistItems(for: playlist)
            .sorted { (($0.value(forKey: "position") as? NSNumber)?.int64Value ?? 0) < (($1.value(forKey: "position") as? NSNumber)?.int64Value ?? 0) }
            .compactMap { decodeTrack($0.value(forKey: "payload") as? Data) }
    }

    func signals() -> TasteSignals {
        var result = TasteSignals.empty
        for track in likedTracks {
            result.likedArtists[track.artist.handleKey, default: 0] += 1
            result.likedGenres[track.genre.normalizedGenre, default: 0] += 1
            result.heardTrackIDs.insert(track.id)
        }
        for played in history {
            result.historyArtists[played.track.artist.handleKey, default: 0] += 1
            result.likedGenres[played.track.genre.normalizedGenre, default: 0] += 1
            result.heardTrackIDs.insert(played.track.id)
        }
        return result
    }

    private func reloadLikes() {
        let request = NSFetchRequest<NSManagedObject>(entityName: PersistenceController.Entity.likedTrack)
        request.sortDescriptors = [NSSortDescriptor(key: "likedAt", ascending: false)]
        let objects = (try? context.fetch(request)) ?? []
        likedTracks = objects.compactMap { decodeTrack($0.value(forKey: "payload") as? Data) }
        likedIDs = Set(likedTracks.map(\.id))
    }

    private func reloadHistory() {
        let request = NSFetchRequest<NSManagedObject>(entityName: PersistenceController.Entity.history)
        request.sortDescriptors = [NSSortDescriptor(key: "playedAt", ascending: false)]
        request.fetchLimit = 500
        let objects = (try? context.fetch(request)) ?? []
        history = objects.compactMap { object in
            guard let track = decodeTrack(object.value(forKey: "payload") as? Data) else { return nil }
            let id = object.value(forKey: "entryID") as? UUID ?? UUID()
            let date = object.value(forKey: "playedAt") as? Date ?? Date()
            return PlayedTrack(id: id, track: track, playedAt: date)
        }
    }

    private func reloadPlaylists() {
        let request = NSFetchRequest<NSManagedObject>(entityName: PersistenceController.Entity.playlist)
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        let objects = (try? context.fetch(request)) ?? []
        playlists = objects.compactMap { object in
            guard let id = object.value(forKey: "playlistID") as? UUID,
                  let title = object.value(forKey: "title") as? String else { return nil }
            let items = playlistItems(for: object)
            let tracks = items
                .sorted { (($0.value(forKey: "position") as? NSNumber)?.int64Value ?? 0) < (($1.value(forKey: "position") as? NSNumber)?.int64Value ?? 0) }
                .compactMap { decodeTrack($0.value(forKey: "payload") as? Data) }
            return PlaylistSummary(
                id: id,
                title: title,
                trackCount: tracks.count,
                updatedAt: object.value(forKey: "updatedAt") as? Date ?? Date(),
                artworkURLs: tracks.compactMap(\.artworkURL).prefix(4).map { $0 }
            )        }
    }

    private func fetchPlaylist(id: UUID) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: PersistenceController.Entity.playlist)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "playlistID == %@", id as NSUUID)
        return try? context.fetch(request).first
    }

    private func playlistItems(for playlist: NSManagedObject) -> [NSManagedObject] {
        if let set = playlist.value(forKey: "items") as? Set<NSManagedObject> {
            return Array(set)
        }
        if let set = playlist.value(forKey: "items") as? NSSet {
            return set.allObjects as? [NSManagedObject] ?? []
        }
        return []
    }

    private func pruneHistory() {
        let request = NSFetchRequest<NSManagedObject>(entityName: PersistenceController.Entity.history)
        request.sortDescriptors = [NSSortDescriptor(key: "playedAt", ascending: false)]
        guard let objects = try? context.fetch(request), objects.count > 1_000 else { return }
        for object in objects.dropFirst(1_000) {
            context.delete(object)
        }
    }

    private func decodeTrack(_ data: Data?) -> Track? {
        guard let data else { return nil }
        return try? decoder.decode(Track.self, from: data)
    }
}
