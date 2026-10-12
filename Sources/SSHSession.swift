import Citadel
import Foundation
import NIOCore
import NIOSSH
import SwiftTerm
import UIKit

/// One SSH connection feeding one SwiftTerm terminal view.
@MainActor
final class SSHSession: NSObject, ObservableObject, TerminalViewDelegate {
    enum State: Equatable {
        case idle, connecting, connected, closed(String)
    }

    let host: Host
    let terminalView: TerminalView
    @Published var state: State = .idle

    private var client: SSHClient?
    private var writer: TTYStdinWriter?
    private var task: Task<Void, Never>?

    init(host: Host) {
        self.host = host
        // Start at screen size (not .zero) so the first terminal size is close to the real one.
        terminalView = TerminalView(
            frame: UIScreen.main.bounds,
            font: UIFont.monospacedSystemFont(ofSize: CGFloat(host.fontSize), weight: .regular)
        )
        super.init()
        terminalView.terminalDelegate = self
        // SwiftTerm's default background is clear, so each redraw painted over the old text without
        // erasing it, and UIKit stretched the old picture on resize. An opaque background that is
        // redrawn (not stretched) on every size change fixes the smeared, striped output.
        terminalView.nativeBackgroundColor = .black
        terminalView.nativeForegroundColor = UIColor(red: 0.75, green: 1.0, blue: 0.80, alpha: 1)
        terminalView.backgroundColor = .black
        terminalView.isOpaque = true
        terminalView.contentMode = .redraw
    }

    func connect(password: String?) {
        guard task == nil else { return }
        state = .connecting
        print("Connecting to \(host.hostname):\(host.port) via ssh\r\n")

        task = Task { [weak self] in
            await self?.run(password: password)
        }
    }

    func disconnect() {
        task?.cancel()
        let client = client
        Task { try? await client?.close() }
    }

    private func run(password: String?) async {
        do {
            let auth: SSHAuthenticationMethod
            switch host.auth {
            case .password:
                auth = .passwordBased(username: host.username, password: password ?? "")
            case .key:
                guard let key = KeyManager.privateKey else {
                    throw SimpleError("No key yet: open Keys on the host list and generate one first.")
                }
                auth = .ed25519(username: host.username, privateKey: key)
            }

            let validator = TrustOnFirstUseValidator(host: host) { fingerprint in
                Task { @MainActor [weak self] in
                    self?.print("New computer; saved its host key \(fingerprint)\r\n")
                }
            }

            let client = try await SSHClient.connect(
                host: host.hostname,
                port: host.port,
                authenticationMethod: auth,
                hostKeyValidator: .custom(validator),
                reconnect: .never
            )
            self.client = client
            state = .connected

            let terminal = terminalView.getTerminal()
            let request = SSHChannelRequestEvent.PseudoTerminalRequest(
                wantReply: true,
                term: "xterm-256color",
                terminalCharacterWidth: terminal.cols,
                terminalRowHeight: terminal.rows,
                terminalPixelWidth: 0,
                terminalPixelHeight: 0,
                terminalModes: .init([:])
            )

            try await client.withPTY(request) { inbound, outbound in
                await MainActor.run { self.writer = outbound }
                // The view may have been laid out (and resized) while the session was opening:
                // tell the computer the size the terminal really has now.
                let size = await MainActor.run { (self.terminalView.getTerminal().cols, self.terminalView.getTerminal().rows) }
                try? await outbound.changeSize(cols: size.0, rows: size.1, pixelWidth: 0, pixelHeight: 0)
                for try await output in inbound {
                    let buffer: ByteBuffer
                    switch output {
                    case .stdout(let data): buffer = data
                    case .stderr(let data): buffer = data
                    }
                    let bytes = Array(buffer.readableBytesView)
                    await MainActor.run { self.terminalView.feed(byteArray: bytes[...]) }
                }
            }
            finish("Connection closed.")
        } catch is CancellationError {
            finish("Disconnected.")
        } catch {
            finish(describe(error))
        }
    }

    private func finish(_ message: String) {
        writer = nil
        let client = client
        self.client = nil
        Task { try? await client?.close() }
        print("\r\n[\(message)]\r\n")
        state = .closed(message)
        task = nil
    }

    private func describe(_ error: Error) -> String {
        if let local = error as? LocalizedError, let text = local.errorDescription { return text }
        let text = String(describing: error)
        if text.lowercased().contains("auth") {
            return "Login failed: check the username and password (or that your key is on the computer)."
        }
        return "Could not connect: \(text)"
    }

    private func print(_ text: String) {
        terminalView.feed(text: text)
    }

    /// Sends text typed outside the terminal (e.g. from the extra keys bar).
    func send(_ bytes: [UInt8]) {
        guard let writer else { return }
        Task { try? await writer.write(ByteBuffer(bytes: bytes)) }
    }

    // MARK: TerminalViewDelegate

    nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let bytes = Array(data)
        Task { @MainActor in self.send(bytes) }
    }

    nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        Task { @MainActor in
            guard let writer = self.writer else { return }
            try? await writer.changeSize(cols: newCols, rows: newRows, pixelWidth: 0, pixelHeight: 0)
        }
    }

    nonisolated func setTerminalTitle(source: TerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    nonisolated func scrolled(source: TerminalView, position: Double) {}
    nonisolated func bell(source: TerminalView) {}
    nonisolated func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link) else { return }
        Task { @MainActor in UIApplication.shared.open(url) }
    }

    nonisolated func clipboardCopy(source: TerminalView, content: Data) {
        guard let text = String(data: content, encoding: .utf8) else { return }
        Task { @MainActor in UIPasteboard.general.string = text }
    }
}

struct SimpleError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
