import SwiftUI
import AppKit
import CoreAudio
import Combine

@main
struct AudioSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "slider.horizontal.3",
                accessibilityDescription: "Audio Switcher"
            )
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover.contentSize = NSSize(width: 400, height: 560)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: AudioPopoverView())

        AudioDeviceManager.shared.startListeningForChanges()
        AudioDeviceManager.shared.refreshAll()
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
            stopEventMonitor()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            startEventMonitor()
        }
    }

    private func startEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
            self.stopEventMonitor()
        }
    }

    private func stopEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

struct AudioPopoverView: View {
    @ObservedObject private var audio = AudioDeviceManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                presets

                DeviceSectionCard(
                    title: "Output",
                    icon: "speaker.wave.2.fill"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(audio.outputDevices) { device in
                            OutputDeviceTile(device: device)
                        }
                    }
                }

                DeviceSectionCard(
                    title: "Input",
                    icon: "mic.fill"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(audio.inputDevices) { device in
                            InputDeviceTile(device: device)
                        }
                    }
                }

                HStack {
                    Button("Refresh") {
                        audio.refreshAll()
                    }
                    .buttonStyle(.bordered)

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    if let error = audio.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 400, height: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Audio Switcher")
                .font(.title3.weight(.semibold))
            Text("Switch default input and output devices quickly from the menu bar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quick presets")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Auto-detected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if audio.quickPresets.isEmpty {
                Text("No presets available yet. Connect an audio device and it will appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlexiblePresetRows(presets: audio.quickPresets) { preset in
                    audio.applyPreset(preset)
                }
            }
        }
    }
}

struct FlexiblePresetRows: View {
    let presets: [QuickPreset]
    let action: (QuickPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chunkedPresets(), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row) { preset in
                        PresetChip(title: preset.title) {
                            action(preset)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func chunkedPresets() -> [[QuickPreset]] {
        stride(from: 0, to: presets.count, by: 2).map { index in
            Array(presets[index..<min(index + 2, presets.count)])
        }
    }
}

struct DeviceSectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
            }

            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

struct PresetChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}

struct OutputDeviceTile: View {
    let device: AudioDevice
    @ObservedObject private var audio = AudioDeviceManager.shared

    var isSelected: Bool {
        device.id == audio.defaultOutputDeviceID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                audio.setDefaultOutputDevice(device.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .imageScale(.large)
                        .foregroundStyle(isSelected ? .white : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(.body.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(.primary)
                        Text(device.transportLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isSelected {
                        Text("Active")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                }
                .padding(12)
                .background(tileBackground)
            }
            .buttonStyle(.plain)

            if isSelected {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Output volume")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text(audio.outputVolumeSupported ? "\(Int(audio.outputVolume * 100))%" : "Unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { audio.outputVolume },
                            set: { audio.setOutputVolume($0) }
                        ),
                        in: 0...1
                    )
                    .disabled(!audio.outputVolumeSupported)

                    if !audio.outputVolumeSupported {
                        Text("This output device does not expose software volume control.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isSelected)
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? Color.white.opacity(0.10) : Color.white.opacity(0.03))
    }
}

struct InputDeviceTile: View {
    let device: AudioDevice
    @ObservedObject private var audio = AudioDeviceManager.shared

    var isSelected: Bool {
        device.id == audio.defaultInputDeviceID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                audio.setDefaultInputDevice(device.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .imageScale(.large)
                        .foregroundStyle(isSelected ? .white : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(.body.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(.primary)
                        Text(device.transportLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isSelected {
                        Text("Active")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                }
                .padding(12)
                .background(tileBackground)
            }
            .buttonStyle(.plain)

            if isSelected {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Input level")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text(audio.inputGainSupported ? "\(Int(audio.inputGain * 100))%" : "Unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { audio.inputGain },
                            set: { audio.setInputGain($0) }
                        ),
                        in: 0...1
                    )
                    .disabled(!audio.inputGainSupported)

                    if !audio.inputGainSupported {
                        Text("This input device does not expose adjustable gain to macOS.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isSelected)
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? Color.white.opacity(0.10) : Color.white.opacity(0.03))
    }
}

struct QuickPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let outputDeviceID: AudioDeviceID?
    let inputDeviceID: AudioDeviceID?
}

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let hasInput: Bool
    let hasOutput: Bool
    let transportType: UInt32

    var transportLabel: String {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return "Built-in"
        case kAudioDeviceTransportTypeUSB:
            return "USB"
        case kAudioDeviceTransportTypeBluetooth:
            return "Bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE:
            return "Bluetooth LE"
        case kAudioDeviceTransportTypeHDMI:
            return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort:
            return "DisplayPort"
        case kAudioDeviceTransportTypeAirPlay:
            return "AirPlay"
        default:
            return "Other"
        }
    }
}

final class AudioDeviceManager: ObservableObject {
    static let shared = AudioDeviceManager()

    @Published var inputDevices: [AudioDevice] = []
    @Published var outputDevices: [AudioDevice] = []
    @Published var defaultInputDeviceID: AudioDeviceID = 0
    @Published var defaultOutputDeviceID: AudioDeviceID = 0
    @Published var outputVolume: Float = 0
    @Published var inputGain: Float = 0
    @Published var outputVolumeSupported: Bool = false
    @Published var inputGainSupported: Bool = false
    @Published var quickPresets: [QuickPreset] = []
    @Published var lastError: String?

    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
    private var listenersInstalled = false

    private init() {}

    func refreshAll() {
        DispatchQueue.global(qos: .userInitiated).async {
            let allDevices = self.fetchDevices()
            let inputs = allDevices
                .filter { $0.hasInput }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let outputs = allDevices
                .filter { $0.hasOutput }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            let defaultInput = self.fetchDefaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
            let defaultOutput = self.fetchDefaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
            let outputVolume = self.fetchVolume(deviceID: defaultOutput, scope: kAudioDevicePropertyScopeOutput)
            let inputGain = self.fetchVolume(deviceID: defaultInput, scope: kAudioDevicePropertyScopeInput)
            let presets = self.buildQuickPresets(inputs: inputs, outputs: outputs)

            DispatchQueue.main.async {
                self.inputDevices = inputs
                self.outputDevices = outputs
                self.defaultInputDeviceID = defaultInput
                self.defaultOutputDeviceID = defaultOutput
                self.outputVolume = outputVolume ?? 0
                self.inputGain = inputGain ?? 0
                self.outputVolumeSupported = outputVolume != nil
                self.inputGainSupported = inputGain != nil
                self.quickPresets = presets
                self.lastError = nil
            }
        }
    }

    func applyPreset(_ preset: QuickPreset) {
        if let outputID = preset.outputDeviceID {
            setDefaultOutputDevice(outputID)
        }
        if let inputID = preset.inputDeviceID {
            setDefaultInputDevice(inputID)
        }
    }

    func setDefaultInputDevice(_ deviceID: AudioDeviceID) {
        setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    func setDefaultOutputDevice(_ deviceID: AudioDeviceID) {
        setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    func setOutputVolume(_ value: Float) {
        let success = setVolume(
            deviceID: defaultOutputDeviceID,
            scope: kAudioDevicePropertyScopeOutput,
            value: value
        )

        DispatchQueue.main.async {
            if success {
                self.outputVolume = value
                self.outputVolumeSupported = true
                self.lastError = nil
            } else {
                self.outputVolumeSupported = false
                self.lastError = "Selected output device does not support software volume control."
                self.refreshAll()
            }
        }
    }

    func setInputGain(_ value: Float) {
        let success = setVolume(
            deviceID: defaultInputDeviceID,
            scope: kAudioDevicePropertyScopeInput,
            value: value
        )

        DispatchQueue.main.async {
            if success {
                self.inputGain = value
                self.inputGainSupported = true
                self.lastError = nil
            } else {
                self.inputGainSupported = false
                self.lastError = "Selected input device does not expose adjustable gain."
                self.refreshAll()
            }
        }
    }

    func startListeningForChanges() {
        guard !listenersInstalled else { return }
        listenersInstalled = true

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(systemObjectID, &devicesAddress, .main) { [weak self] _, _ in
            self?.refreshAll()
        }

        AudioObjectAddPropertyListenerBlock(systemObjectID, &defaultInputAddress, .main) { [weak self] _, _ in
            self?.refreshAll()
        }

        AudioObjectAddPropertyListenerBlock(systemObjectID, &defaultOutputAddress, .main) { [weak self] _, _ in
            self?.refreshAll()
        }
    }

    private func setDefaultDevice(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) {
        DispatchQueue.global(qos: .userInitiated).async {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var newDevice = deviceID
            let size = UInt32(MemoryLayout<AudioDeviceID>.size)

            let status = AudioObjectSetPropertyData(
                self.systemObjectID,
                &address,
                0,
                nil,
                size,
                &newDevice
            )

            DispatchQueue.main.async {
                if status == noErr {
                    self.lastError = nil
                    self.refreshAll()
                } else {
                    self.lastError = "Failed to switch device (OSStatus: \(status))"
                }
            }
        }
    }

    private func fetchDefaultDevice(selector: AudioObjectPropertySelector) -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            systemObjectID,
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        return status == noErr ? deviceID : 0
    }

    private func fetchDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = Array(repeating: AudioDeviceID(0), count: count)

        guard AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &dataSize, &ids) == noErr else {
            return []
        }

        return ids.compactMap { buildDevice(from: $0) }
    }

    private func buildDevice(from id: AudioDeviceID) -> AudioDevice? {
        let name = fetchDeviceName(id)
        let hasInput = deviceHasStreams(id: id, scope: kAudioObjectPropertyScopeInput)
        let hasOutput = deviceHasStreams(id: id, scope: kAudioObjectPropertyScopeOutput)
        let transport = fetchTransportType(id)

        guard !name.isEmpty, hasInput || hasOutput else { return nil }

        return AudioDevice(
            id: id,
            name: name,
            hasInput: hasInput,
            hasOutput: hasOutput,
            transportType: transport
        )
    }

    private func fetchDeviceName(_ id: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var cfName: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &cfName)
        return status == noErr ? (cfName as String) : "Unknown Device"
    }

    private func fetchTransportType(_ id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return status == noErr ? value : 0
    }

    private func deviceHasStreams(id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    private func fetchVolume(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Float? {
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            if let value = fetchScalar(
                deviceID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: scope,
                element: AudioObjectPropertyElement(element)
            ) {
                return value
            }
        }
        return nil
    }

    private func setVolume(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope, value: Float) -> Bool {
        var didSet = false

        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            if setScalar(
                deviceID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: scope,
                element: AudioObjectPropertyElement(element),
                value: value
            ) {
                didSet = true
            }
        }

        return didSet
    }

    private func fetchScalar(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Float? {
        guard deviceID != 0 else { return nil }

        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)

        guard status == noErr else { return nil }
        return min(max(Float(value), 0), 1)
    }

    private func setScalar(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        value: Float
    ) -> Bool {
        guard deviceID != 0 else { return false }

        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var scalar = min(max(Float32(value), 0), 1)
        let size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &scalar)
        return status == noErr
    }

    private func buildQuickPresets(inputs: [AudioDevice], outputs: [AudioDevice]) -> [QuickPreset] {
        var presets: [QuickPreset] = []
        var seenKeys = Set<String>()
        var seenTitles = Set<String>()

        let builtInInput = inputs.first { $0.transportType == kAudioDeviceTransportTypeBuiltIn }
        let builtInOutput = outputs.first { $0.transportType == kAudioDeviceTransportTypeBuiltIn }

        for output in outputs {
            if output.transportType == kAudioDeviceTransportTypeBuiltIn {
                continue
            }

            let matchedInput = bestMatchingInput(for: output, inputs: inputs) ?? builtInInput
            let title = cleanedPresetTitle(for: output.name)
            let key = "\(output.id)-\(matchedInput?.id ?? 0)"

            guard seenKeys.insert(key).inserted else { continue }
            guard seenTitles.insert(title.lowercased()).inserted else { continue }

            presets.append(
                QuickPreset(
                    id: key,
                    title: title,
                    outputDeviceID: output.id,
                    inputDeviceID: matchedInput?.id
                )
            )
        }

        if let builtInOutput, let builtInInput {
            let key = "builtin-\(builtInOutput.id)-\(builtInInput.id)"
            let title = "MacBook built-in"

            if seenKeys.insert(key).inserted, seenTitles.insert(title.lowercased()).inserted {
                presets.insert(
                    QuickPreset(
                        id: key,
                        title: title,
                        outputDeviceID: builtInOutput.id,
                        inputDeviceID: builtInInput.id
                    ),
                    at: 0
                )
            }
        }

        return presets.sorted { lhs, rhs in
            if lhs.title == "MacBook built-in" { return true }
            if rhs.title == "MacBook built-in" { return false }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func bestMatchingInput(for output: AudioDevice, inputs: [AudioDevice]) -> AudioDevice? {
        if let exact = inputs.first(where: { $0.name == output.name }) {
            return exact
        }

        let normalizedOutput = normalizeDeviceName(output.name)
        if let close = inputs.first(where: { normalizeDeviceName($0.name) == normalizedOutput }) {
            return close
        }

        if output.transportType == kAudioDeviceTransportTypeBuiltIn {
            return inputs.first { $0.transportType == kAudioDeviceTransportTypeBuiltIn }
        }

        return nil
    }

    private func cleanedPresetTitle(for deviceName: String) -> String {
        if deviceName.localizedCaseInsensitiveContains("MacBook Pro Speakers")
            || deviceName.localizedCaseInsensitiveContains("MacBook Air Speakers") {
            return "MacBook built-in"
        }

        if deviceName.localizedCaseInsensitiveContains("Scarlett") {
            return "Scarlett in/out"
        }

        return deviceName
            .replacingOccurrences(of: " Speakers", with: "")
            .replacingOccurrences(of: " Speaker", with: "")
            .replacingOccurrences(of: " Microphone", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeDeviceName(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: " speakers", with: "")
            .replacingOccurrences(of: " speaker", with: "")
            .replacingOccurrences(of: " microphone", with: "")
            .replacingOccurrences(of: " mic", with: "")
            .replacingOccurrences(of: " headphones", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
