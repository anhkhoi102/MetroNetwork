import Testing
@testable import MetroCore

@Suite("RouteEditor (drag editing)")
struct RouteEditorTests {

    @Test func drawNewLineThroughStations() throws {
        let state = makeState(stations: 4)
        var editor = try RouteEditor.newLine(from: StationID(1), in: state).get()
        editor.hover(nil)
        editor.hover(StationID(2))
        editor.hover(nil)
        editor.hover(StationID(3))
        #expect(editor.stations == ids(1, 2, 3))
        #expect(editor.tailAnchor == StationID(3))
        #expect(editor.commitCommand() == .createLine(stations: ids(1, 2, 3), colorIndex: 0, isLoop: false))
    }

    @Test func singleStationDragCommitsNothing() throws {
        let state = makeState(stations: 2)
        var editor = try RouteEditor.newLine(from: StationID(1), in: state).get()
        editor.hover(nil)
        editor.hover(StationID(1))
        #expect(editor.commitCommand() == nil)
    }

    @Test func draggingBackUndoesLastStop() throws {
        let state = makeState(stations: 4)
        var editor = try RouteEditor.newLine(from: StationID(1), in: state).get()
        editor.hover(StationID(2))
        editor.hover(StationID(3))
        editor.hover(StationID(2))
        #expect(editor.stations == ids(1, 2))
        editor.hover(StationID(4))
        #expect(editor.stations == ids(1, 2, 4))
    }

    @Test func closeAndReopenLoopWhileDrawing() throws {
        let state = makeState(stations: 4)
        var editor = try RouteEditor.newLine(from: StationID(1), in: state).get()
        editor.hover(StationID(2))
        editor.hover(StationID(3))
        editor.hover(StationID(1))
        #expect(editor.isLoop)
        #expect(editor.tailAnchor == nil)
        editor.hover(StationID(4))          // ignored while closed
        #expect(editor.stations == ids(1, 2, 3))
        editor.hover(StationID(3))          // back to the last stop: reopen
        #expect(!editor.isLoop)
        #expect(editor.commitCommand() == .createLine(stations: ids(1, 2, 3), colorIndex: 0, isLoop: false))
    }

    @Test func newLineFailsWithoutFreeSlot() throws {
        var config = GameConfiguration.standard
        config.maxLines = 1
        var state = makeState(stations: 3, config: config)
        try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        #expect(throws: RouteError.noLineAvailable) { try RouteEditor.newLine(from: StationID(3), in: state).get() }
    }

    @Test func extendFromStartKeepsLineOrder() throws {
        var state = makeState(stations: 5)
        let id = try RouteManager.createLine(stations: ids(2, 3), colorIndex: nil, isLoop: false, in: &state)
        var editor = try RouteEditor.extend(id, from: .start, in: state).get()
        editor.hover(StationID(1))
        #expect(editor.stations == ids(1, 2, 3))
        #expect(editor.commitCommand() == .setStations(id, stations: ids(1, 2, 3), isLoop: false))
    }

    @Test func extendThenRetractPastOriginalShortensLine() throws {
        var state = makeState(stations: 5)
        let id = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false, in: &state)
        var editor = try RouteEditor.extend(id, from: .end, in: state).get()
        editor.hover(StationID(2))           // back along the line: drop station 3
        #expect(editor.stations == ids(1, 2))
        #expect(editor.commitCommand() == .setStations(id, stations: ids(1, 2), isLoop: false))

        // Applying it through the engine works.
        let engine = GameEngine(state: state)
        _ = engine.apply(try #require(editor.commitCommand()))
        #expect(engine.state.line(id)?.stations == ids(1, 2))
    }

    @Test func extendWithoutChangeCommitsNothing() throws {
        var state = makeState(stations: 3)
        let id = try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        var editor = try RouteEditor.extend(id, from: .end, in: state).get()
        editor.hover(nil)
        editor.hover(StationID(2))
        #expect(editor.commitCommand() == nil)
    }

    @Test func cannotExtendLoop() throws {
        var state = makeState(stations: 3)
        let id = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: true, in: &state)
        #expect(throws: RouteError.lineIsLoop) { try RouteEditor.extend(id, from: .end, in: state).get() }
    }

    @Test func insertDragOntoNewStation() throws {
        var state = makeState(stations: 4)
        let id = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false, in: &state)
        var editor = try RouteEditor.insert(into: id, segment: 1, in: state).get()
        editor.hover(StationID(1))            // already on the line: no candidate
        #expect(editor.commitCommand() == nil)
        editor.hover(StationID(4))
        #expect(editor.stations == ids(1, 2, 4, 3))
        #expect(editor.commitCommand() == .insertStation(id, station: StationID(4), segment: 1))
        editor.hover(nil)                     // released over empty map: nothing
        #expect(editor.commitCommand() == nil)
    }

    @Test func insertKeepsLoopFlagInDraft() throws {
        var state = makeState(stations: 4)
        let id = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: true, in: &state)
        var editor = try RouteEditor.insert(into: id, segment: 2, in: state).get()
        editor.hover(StationID(4))
        #expect(editor.draftLine.isLoop)
        #expect(editor.draftLine.stations == ids(1, 2, 3, 4))
    }
}
