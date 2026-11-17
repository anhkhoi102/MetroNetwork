import Testing
@testable import MetroCore

@Suite("RouteManager")
struct RouteManagerTests {

    @Test func createLineAssignsFirstFreeColourAndBumpsRevision() throws {
        var state = makeState(stations: 4)
        let id = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false, in: &state)
        let line = try #require(state.line(id))
        #expect(line.stations == ids(1, 2, 3))
        #expect(line.colorIndex == 0)
        #expect(state.revision > 0)          // the line, and its first train (headways changed)
        let second = try RouteManager.createLine(stations: ids(3, 4), colorIndex: nil, isLoop: false, in: &state)
        #expect(state.line(second)?.colorIndex == 1)
    }

    @Test func createLineRejectsInvalidSequences() {
        var state = makeState(stations: 4)
        #expect(throws: RouteError.notEnoughStations) {
            try RouteManager.createLine(stations: ids(1), colorIndex: nil, isLoop: false, in: &state)
        }
        #expect(throws: RouteError.duplicateStation(StationID(1))) {
            try RouteManager.createLine(stations: ids(1, 2, 1), colorIndex: nil, isLoop: false, in: &state)
        }
        #expect(throws: RouteError.unknownStation(StationID(99))) {
            try RouteManager.createLine(stations: ids(1, 99), colorIndex: nil, isLoop: false, in: &state)
        }
        #expect(throws: RouteError.loopTooShort) {
            try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: true, in: &state)
        }
        #expect(state.lines.isEmpty)
        #expect(state.revision == 0)
    }

    @Test func lineSlotsAreLimited() throws {
        var config = GameConfiguration.standard
        config.maxLines = 2
        var state = makeState(stations: 4, config: config)
        try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        try RouteManager.createLine(stations: ids(2, 3), colorIndex: nil, isLoop: false, in: &state)
        #expect(throws: RouteError.noLineAvailable) {
            try RouteManager.createLine(stations: ids(3, 4), colorIndex: nil, isLoop: false, in: &state)
        }
    }

    @Test func extendAtBothEnds() throws {
        var state = makeState(stations: 5)
        let id = try RouteManager.createLine(stations: ids(2, 3), colorIndex: nil, isLoop: false, in: &state)
        try RouteManager.extendLine(id, end: .end, with: StationID(4), in: &state)
        try RouteManager.extendLine(id, end: .start, with: StationID(1), in: &state)
        #expect(state.line(id)?.stations == ids(1, 2, 3, 4))
        #expect(throws: RouteError.stationAlreadyOnLine(StationID(3))) {
            try RouteManager.extendLine(id, end: .end, with: StationID(3), in: &state)
        }
    }

    @Test func extendingOntoOppositeTerminalClosesLoop() throws {
        var state = makeState(stations: 4)
        let id = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false, in: &state)
        try RouteManager.extendLine(id, end: .end, with: StationID(1), in: &state)
        let line = try #require(state.line(id))
        #expect(line.isLoop)
        #expect(line.segments.count == 3)
        #expect(throws: RouteError.lineIsLoop) {
            try RouteManager.extendLine(id, end: .end, with: StationID(4), in: &state)
        }
    }

    @Test func twoStationLineCannotLoopOntoItself() throws {
        var state = makeState(stations: 3)
        let id = try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        #expect(throws: RouteError.stationAlreadyOnLine(StationID(1))) {
            try RouteManager.extendLine(id, end: .end, with: StationID(1), in: &state)
        }
    }

    @Test func loopsCanBeDisabled() throws {
        var config = GameConfiguration.standard
        config.allowLoops = false
        var state = makeState(stations: 4, config: config)
        let id = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false, in: &state)
        #expect(throws: RouteError.loopsNotAllowed) {
            try RouteManager.extendLine(id, end: .end, with: StationID(1), in: &state)
        }
    }

    @Test func insertStationIntoSegments() throws {
        var state = makeState(stations: 5)
        let id = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false, in: &state)
        try RouteManager.insertStation(StationID(4), into: id, segment: 0, in: &state)
        #expect(state.line(id)?.stations == ids(1, 4, 2, 3))
        #expect(throws: RouteError.invalidSegment(3)) {
            try RouteManager.insertStation(StationID(5), into: id, segment: 3, in: &state)
        }
        #expect(throws: RouteError.stationAlreadyOnLine(StationID(2))) {
            try RouteManager.insertStation(StationID(2), into: id, segment: 0, in: &state)
        }
    }

    @Test func insertIntoLoopClosingSegment() throws {
        var state = makeState(stations: 5)
        let id = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: true, in: &state)
        try RouteManager.insertStation(StationID(4), into: id, segment: 2, in: &state)
        let line = try #require(state.line(id))
        #expect(line.stations == ids(1, 2, 3, 4))
        #expect(line.isLoop)
        #expect(line.segments.last.map { [$0.0, $0.1] } == ids(4, 1))
    }

    @Test func removingStationsShrinksThenDeletesLine() throws {
        var state = makeState(stations: 4)
        let id = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false, in: &state)
        #expect(try RouteManager.removeStation(StationID(2), from: id, in: &state) == .lineChanged(id))
        #expect(state.line(id)?.stations == ids(1, 3))
        #expect(try RouteManager.removeStation(StationID(1), from: id, in: &state) == .lineDeleted(id))
        #expect(state.lines.isEmpty)
    }

    @Test func removingFromSmallLoopOpensIt() throws {
        var state = makeState(stations: 4)
        let id = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: true, in: &state)
        _ = try RouteManager.removeStation(StationID(3), from: id, in: &state)
        let line = try #require(state.line(id))
        #expect(!line.isLoop)
        #expect(line.stations == ids(1, 2))
    }

    @Test func recolourSwapsWithLineUsingThatColour() throws {
        var state = makeState(stations: 4)
        let a = try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        let b = try RouteManager.createLine(stations: ids(3, 4), colorIndex: nil, isLoop: false, in: &state)
        try RouteManager.setColor(a, colorIndex: 1, in: &state)
        #expect(state.line(a)?.colorIndex == 1)
        #expect(state.line(b)?.colorIndex == 0)
        try RouteManager.setColor(a, colorIndex: 5, in: &state)
        #expect(state.line(a)?.colorIndex == 5)
        #expect(throws: RouteError.invalidColor(42)) { try RouteManager.setColor(a, colorIndex: 42, in: &state) }
    }

    @Test func setStationsReplacesOrDeletes() throws {
        var state = makeState(stations: 4)
        let id = try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        #expect(try RouteManager.setStations(id, stations: ids(1, 2, 3, 4), isLoop: true, in: &state) == .lineChanged(id))
        #expect(state.line(id)?.isLoop == true)
        #expect(throws: RouteError.noChange) {
            try RouteManager.setStations(id, stations: ids(1, 2, 3, 4), isLoop: true, in: &state)
        }
        #expect(try RouteManager.setStations(id, stations: ids(4), isLoop: false, in: &state) == .lineDeleted(id))
    }

    @Test func openLoopAndDelete() throws {
        var state = makeState(stations: 3)
        let id = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: true, in: &state)
        try RouteManager.openLoop(id, in: &state)
        #expect(state.line(id)?.isLoop == false)
        #expect(throws: RouteError.lineIsNotLoop) { try RouteManager.openLoop(id, in: &state) }
        try RouteManager.deleteLine(id, in: &state)
        #expect(throws: RouteError.unknownLine(id)) { try RouteManager.deleteLine(id, in: &state) }
    }

    @Test func engineLeavesStateUntouchedOnFailure() {
        let engine = GameEngine(state: makeState(stations: 3))
        let before = engine.state
        let result = engine.apply(.createLine(stations: ids(1, 1), colorIndex: nil, isLoop: false))
        #expect(result == .failure(.duplicateStation(StationID(1))))
        #expect(engine.state == before)
        #expect(engine.drainEvents().isEmpty)

        let ok = engine.apply(.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false))
        guard case .success(.lineCreated(let id)) = ok else {
            Issue.record("expected success, got \(ok)")
            return
        }
        #expect(engine.drainEvents() == [.lineCreated(id)])
    }
}
