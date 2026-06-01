import XCTest
@testable import Macstral

@MainActor
final class AudioNotesStoreTests: XCTestCase {

    private var store: AudioNotesStore!
    private var tempDirectoryURL: URL!
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        fileURL = tempDirectoryURL.appendingPathComponent("audio_notes.json")
        store = AudioNotesStore(fileURL: fileURL)
    }

    override func tearDown() {
        store = nil
        if let tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
        }
        fileURL = nil
        tempDirectoryURL = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testEmptyOnInit() {
        XCTAssertTrue(store.notes.isEmpty)
    }

    // MARK: - Add + Persist Round-Trip

    func testAddAppendsNote() {
        let note = makeNote(title: "Meeting recap")
        store.add(note)
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.notes.first?.title, "Meeting recap")
    }

    func testAddPersistsToDisK() {
        let note = makeNote(title: "Persisted note", transcript: "Some transcript")
        store.add(note)

        let reloaded = AudioNotesStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.notes.count, 1)
        XCTAssertEqual(reloaded.notes.first?.id, note.id)
        XCTAssertEqual(reloaded.notes.first?.title, "Persisted note")
        XCTAssertEqual(reloaded.notes.first?.transcript, "Some transcript")
    }

    func testAddMultipleNotesPersistAll() {
        let first = makeNote(title: "First")
        let second = makeNote(title: "Second")
        let third = makeNote(title: "Third")
        store.add(first)
        store.add(second)
        store.add(third)

        let reloaded = AudioNotesStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.notes.count, 3)
        XCTAssertEqual(Set(reloaded.notes.map(\.title)), ["First", "Second", "Third"])
    }

    // MARK: - Update

    func testUpdateReplacesNoteById() {
        var note = makeNote(title: "Original")
        store.add(note)
        note.title = "Updated"
        note.notes = "# Summary\n\nKey points here."
        store.update(note)

        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.notes.first?.title, "Updated")
        XCTAssertEqual(store.notes.first?.notes, "# Summary\n\nKey points here.")
    }

    func testUpdatePersistsChanges() {
        var note = makeNote(title: "Before update")
        store.add(note)
        note.title = "After update"
        store.update(note)

        let reloaded = AudioNotesStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.notes.first?.title, "After update")
    }

    func testUpdateIsNoopForUnknownId() {
        let known = makeNote(title: "Known")
        store.add(known)
        let unknown = makeNote(title: "Unknown — should not appear")
        store.update(unknown)

        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.notes.first?.title, "Known")
    }

    // MARK: - Remove

    func testRemoveDeletesNoteById() {
        let note = makeNote(title: "To delete")
        store.add(note)
        store.remove(note)
        XCTAssertTrue(store.notes.isEmpty)
    }

    func testRemovePersistsDeletion() {
        let note = makeNote(title: "Will be removed")
        store.add(note)
        store.remove(note)

        let reloaded = AudioNotesStore(fileURL: fileURL)
        XCTAssertTrue(reloaded.notes.isEmpty)
    }

    func testRemoveOnlyDeletesTargetNote() {
        let keep = makeNote(title: "Keep")
        let del = makeNote(title: "Delete")
        store.add(keep)
        store.add(del)
        store.remove(del)

        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.notes.first?.title, "Keep")
    }

    // MARK: - Clear

    func testClearEmptiesAllNotes() {
        store.add(makeNote(title: "A"))
        store.add(makeNote(title: "B"))
        store.clear()
        XCTAssertTrue(store.notes.isEmpty)
    }

    func testClearPersistsEmptyState() {
        store.add(makeNote(title: "A"))
        store.clear()

        let reloaded = AudioNotesStore(fileURL: fileURL)
        XCTAssertTrue(reloaded.notes.isEmpty)
    }

    // MARK: - Search / matches

    func testMatchesEmptyQueryReturnsTrue() {
        let note = makeNote(title: "Anything")
        XCTAssertTrue(store.matches(note, query: ""))
        XCTAssertTrue(store.matches(note, query: "   "))
    }

    func testMatchesFindsInTitle() {
        let note = makeNote(title: "Team standup meeting")
        XCTAssertTrue(store.matches(note, query: "standup"))
        XCTAssertFalse(store.matches(note, query: "retrospective"))
    }

    func testMatchesFindsInTranscript() {
        let note = makeNote(title: "Untitled", transcript: "We discussed the quarterly budget review.")
        XCTAssertTrue(store.matches(note, query: "quarterly"))
        XCTAssertFalse(store.matches(note, query: "sprint"))
    }

    func testMatchesFindsInNotes() {
        var note = makeNote(title: "Untitled")
        note = AudioNote(id: note.id, title: note.title, date: note.date, transcript: note.transcript, notes: "Action items: deploy by Friday.", durationSeconds: note.durationSeconds)
        XCTAssertTrue(store.matches(note, query: "deploy"))
        XCTAssertFalse(store.matches(note, query: "rollback"))
    }

    func testMatchesIsCaseInsensitive() {
        let note = makeNote(title: "Design Review", transcript: "Discussed the UI mockups")
        XCTAssertTrue(store.matches(note, query: "DESIGN"))
        XCTAssertTrue(store.matches(note, query: "mockups"))
    }

    // MARK: - Decoder forward-compat

    func testDecoderFallsBackToDefaultsForMissingOptionalFields() throws {
        let fixedID = UUID()
        let legacyJSON = """
        [
          {
            "durationSeconds": 42.5,
            "id": "\(fixedID.uuidString)",
            "date": "2026-01-15T10:00:00Z",
            "transcript": "Legacy transcript without title or notes"
          }
        ]
        """
        try legacyJSON.data(using: .utf8)?.write(to: fileURL)

        let reloaded = AudioNotesStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.notes.count, 1)
        let loaded = try XCTUnwrap(reloaded.notes.first)
        XCTAssertEqual(loaded.id, fixedID)
        XCTAssertEqual(loaded.title, "Untitled")
        XCTAssertEqual(loaded.notes, "")
        XCTAssertEqual(loaded.transcript, "Legacy transcript without title or notes")
        XCTAssertEqual(loaded.durationSeconds, 42.5)
    }

    // MARK: - Helpers

    private func makeNote(
        title: String = "Test Note",
        transcript: String = "Test transcript content.",
        notes: String = "",
        durationSeconds: Double = 30.0
    ) -> AudioNote {
        AudioNote(
            title: title,
            transcript: transcript,
            notes: notes,
            durationSeconds: durationSeconds
        )
    }
}
