import Foundation
import Testing

@testable import WritelessCore

@Suite("Input device catalog")
struct InputDeviceCatalogTests {
    private let builtIn = InputDevice(uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone")
    private let airPods = InputDevice(uid: "80-4E-70-AA-BB-CC:input", name: "AirPods Pro")

    private var available: [InputDevice] { [builtIn, airPods] }

    @Test("No choice means the system input")
    func systemDefault() {
        #expect(
            InputDeviceCatalog.device(
                forUID: InputDeviceCatalog.systemDefaultUID, available: available, remembered: airPods
            ) == nil
        )
    }

    @Test("A connected choice resolves to itself")
    func connectedChoice() {
        #expect(
            InputDeviceCatalog.device(forUID: airPods.uid, available: available, remembered: nil) == airPods
        )
    }

    @Test("A device that is away keeps the choice rather than losing it")
    func absentChoice() {
        // Re-picking the row while the device is away keeps its name.
        #expect(
            InputDeviceCatalog.device(forUID: airPods.uid, available: [builtIn], remembered: airPods) == airPods
        )
        // Nothing remembers it and nothing offers it: back to the system input.
        #expect(
            InputDeviceCatalog.device(forUID: airPods.uid, available: [builtIn], remembered: nil) == nil
        )
    }

    @Test("A live name wins over the remembered one")
    func renamedDevice() {
        let renamed = InputDevice(uid: airPods.uid, name: "Roman's AirPods Pro")
        #expect(
            InputDeviceCatalog.device(forUID: airPods.uid, available: [renamed], remembered: airPods) == renamed
        )
    }

    @Test("Every connected device is listed, and only those")
    func entriesListWhatIsConnected() {
        let entries = InputDeviceCatalog.deviceEntries(selected: nil, available: available)
        #expect(entries.map(\.uid) == [builtIn.uid, airPods.uid])
        #expect(entries.map(\.title) == [builtIn.name, airPods.name])
        let allConnected = entries.allSatisfy(\.isAvailable)
        #expect(allConnected)
    }

    @Test("A choice that is away is still listed, so the selection is never blank")
    func entriesKeepTheAbsentChoice() {
        let entries = InputDeviceCatalog.deviceEntries(selected: airPods, available: [builtIn])
        #expect(entries.map(\.uid) == [builtIn.uid, airPods.uid])
        #expect(entries.last?.title == "AirPods Pro (not connected)")
        #expect(entries.last?.isAvailable == false)
    }

    @Test("A connected choice is listed once")
    func entriesDoNotDuplicate() {
        let entries = InputDeviceCatalog.deviceEntries(selected: airPods, available: available)
        let rowsForAirPods = entries.filter { $0.uid == airPods.uid }.count
        #expect(rowsForAirPods == 1)
        #expect(entries.count == 2)
    }

    @Test("A microphone listed twice under one name is offered once")
    func deduplicated() {
        // What a Continuity Camera actually looks like after it reconnects.
        let stale = InputDevice(uid: "6AE8344E-...-03", name: "therms phone Microphone")
        let live = InputDevice(uid: "D508DEF0-...-03", name: "therms phone Microphone")
        let devices = InputDeviceCatalog.deduplicated([stale, builtIn, live])
        #expect(devices == [stale, builtIn])
    }

    @Test("Meter segments light in proportion and clamp at both ends")
    func litSegments() {
        #expect(LevelMeter.litSegments(level: 0, count: 16) == 0)
        #expect(LevelMeter.litSegments(level: 0.5, count: 16) == 8)
        #expect(LevelMeter.litSegments(level: 1, count: 16) == 16)
        // Nothing downstream should have to range-check the result.
        #expect(LevelMeter.litSegments(level: 4, count: 16) == 16)
        #expect(LevelMeter.litSegments(level: -1, count: 16) == 0)
        #expect(LevelMeter.litSegments(level: 1, count: 0) == 0)
    }
}
