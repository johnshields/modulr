import SwiftUI
import AppKit

/**
 * OutputDeviceMenu
 * Single button + popover menu listing all currently-known output devices.
 * The icon changes to reflect the active device's transport (built-in, AirPlay,
 * Bluetooth, headphones); the tooltip shows its name. The footer button opens
 * macOS Sound settings so users can pair fresh AirPlay receivers — once paired
 * they appear in this list immediately.
 */
struct OutputDeviceMenu: View {
    @StateObject private var deviceList = OutputDeviceList()

    private var currentDevice: OutputDevice? {
        deviceList.devices.first { $0.id == deviceList.currentDeviceID }
    }

    var body: some View {
        Menu {
            ForEach(deviceList.devices) { device in
                Button {
                    OutputDeviceList.setDefault(device.id)
                } label: {
                    Label {
                        HStack {
                            Text(device.name)
                            if device.id == deviceList.currentDeviceID {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    } icon: {
                        Image(systemName: device.iconName)
                    }
                }
            }
            Divider()
            Button {
                openSoundSettings()
            } label: {
                Label("Add AirPlay device…", systemImage: "plus")
            }
        } label: {
            Image(systemName: currentDevice?.iconName ?? "airplayaudio")
                .foregroundStyle(.white.opacity(0.85))
                .font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(currentDevice.map { "Output: \($0.name)" } ?? "Output device")
    }

    private func openSoundSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Sound-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.sound",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }
}
