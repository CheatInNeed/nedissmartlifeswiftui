// LampBar – lille macOS menu bar-app til Nedis SmartLife loftslampen.
// Kalder lamp.py via det lokale venv og parser JSON. Bygges med swiftc (se build.sh).

import SwiftUI
import ServiceManagement

// MARK: - Stier (lamp.py + venv installeres her af build.sh)

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let python = home.appendingPathComponent(".local/share/lamp/venv/bin/python3").path
    static let script = home.appendingPathComponent(".local/share/lamp/lamp.py").path
}

// MARK: - Model

struct LampState: Decodable {
    var on: Bool
    var mode: String?
    var brightness: Int?
    var colourtemp: Int?
    var rgb: [Int]?
}

// Kører lamp.py uden for main-tråden; returnerer rå stdout.
private func runLamp(_ args: [String]) throws -> Data {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: Paths.python)
    p.arguments = [Paths.script] + args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    try p.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return data
}

@MainActor
final class Lamp: ObservableObject {
    @Published var state = LampState(on: false, mode: nil, brightness: 0, colourtemp: 0, rgb: nil)
    @Published var error: String?
    @Published var busy = false

    private var brightnessTask: Task<Void, Never>?
    private var tempTask: Task<Void, Never>?
    private var colorTask: Task<Void, Never>?

    // Kør en kommando og opdatér state ud fra svaret (eller vis fejl).
    private func send(_ args: [String], refresh: Bool = false) async {
        busy = true; defer { busy = false }
        do {
            let data = try await Task.detached { try runLamp(args) }.value
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = obj["error"] as? String {
                error = msg; return
            }
            error = nil
            if refresh { await refreshNow() }
        } catch {
            self.error = "Kunne ikke køre lamp.py: \(error.localizedDescription)"
        }
    }

    func refresh() { Task { await refreshNow() } }

    private func refreshNow() async {
        do {
            let data = try await Task.detached { try runLamp(["status"]) }.value
            if let s = try? JSONDecoder().decode(LampState.self, from: data) {
                state = s; error = nil
            } else if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let msg = obj["error"] as? String {
                error = msg
            } else {
                error = "Uventet svar fra lampen"
            }
        } catch {
            self.error = "Lampen svarer ikke"
        }
    }

    func toggle() {
        state.on.toggle()
        let on = state.on
        Task { await send([on ? "on" : "off"]) }
    }

    // Debounce ~250 ms, så sliderne ikke sender en kommando pr. pixel.
    func setBrightness(_ pct: Int) {
        state.brightness = pct
        brightnessTask?.cancel()
        brightnessTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            await send(["brightness", String(pct)])
        }
    }

    func setTemp(_ pct: Int) {
        state.colourtemp = pct
        tempTask?.cancel()
        tempTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            await send(["temp", String(pct)])
        }
    }

    // Tilbage til hvid: `temp` skifter lampen til white-mode med den nuværende farvetemperatur.
    func setWhite() {
        tempTask?.cancel(); colorTask?.cancel()
        let t = state.colourtemp ?? 50
        colorTask = Task { await send(["temp", String(t)], refresh: true) }
    }

    func setColor(_ hex: String, debounce: Bool) {
        colorTask?.cancel()
        colorTask = Task {
            if debounce {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
            }
            await send(["color", hex], refresh: true)
        }
    }
}

// MARK: - Farvehjælpere

func hex(_ c: Color) -> String {
    let ns = NSColor(c).usingColorSpace(.sRGB) ?? .white
    return String(format: "#%02X%02X%02X",
                  Int(round(ns.redComponent * 255)),
                  Int(round(ns.greenComponent * 255)),
                  Int(round(ns.blueComponent * 255)))
}

// MARK: - UI

struct Content: View {
    @ObservedObject var lamp: Lamp
    @State private var color = Color.white
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)

    private let presets = ["#FF8800", "#FF2D2D", "#2D7BFF", "#2ECC71", "#FF3DBE", "#FFD54A"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Loftslampe").font(.headline)
                Spacer()
                if lamp.busy { ProgressView().controlSize(.small) }
                Toggle("", isOn: Binding(get: { lamp.state.on }, set: { _ in lamp.toggle() }))
                    .labelsHidden().toggleStyle(.switch)
            }

            if let err = lamp.error {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).lineLimit(2)
            }

            slider("sun.min", "sun.max",
                   value: Binding(get: { Double(lamp.state.brightness ?? 0) },
                                  set: { lamp.setBrightness(Int($0)) }))
            slider("thermometer.snowflake", "thermometer.sun",
                   value: Binding(get: { Double(lamp.state.colourtemp ?? 0) },
                                  set: { lamp.setTemp(Int($0)) }))

            HStack(spacing: 8) {
                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: color) { _, c in lamp.setColor(hex(c), debounce: true) }
                Circle().fill(.white).frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(.gray.opacity(0.5)))
                    .onTapGesture { lamp.setWhite() }
                ForEach(presets, id: \.self) { p in
                    Circle().fill(Color(hex: p)).frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(.white.opacity(0.25)))
                        .onTapGesture { lamp.setColor(p, debounce: false) }
                }
            }

            Divider()

            Toggle("Start ved login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox).font(.callout)
                .onChange(of: launchAtLogin) { _, on in
                    do { on ? try SMAppService.mainApp.register()
                            : try SMAppService.mainApp.unregister() }
                    catch { launchAtLogin = (SMAppService.mainApp.status == .enabled) }
                }

            Button("Afslut") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 260)
        .onAppear { lamp.refresh() }
    }

    private func slider(_ lo: String, _ hi: String, value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: lo).foregroundStyle(.secondary).frame(width: 16)
            Slider(value: value, in: 0...100)
            Image(systemName: hi).foregroundStyle(.secondary).frame(width: 16)
        }
    }
}

extension Color {
    init(hex: String) {
        let s = hex.dropFirst()
        let v = UInt64(s, radix: 16) ?? 0xFFFFFF
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

// MARK: - App

@main
struct LampBarApp: App {
    @StateObject private var lamp = Lamp()

    var body: some Scene {
        MenuBarExtra {
            Content(lamp: lamp)
        } label: {
            Image(systemName: lamp.state.on ? "lightbulb.fill" : "lightbulb")
        }
        .menuBarExtraStyle(.window)
    }
}
