import SwiftTerm
import SwiftUI

@main
struct ConnectBotApp: App {
    @StateObject private var store = HostStore()

    var body: some Scene {
        WindowGroup {
            HostListView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Host list

struct HostListView: View {
    @EnvironmentObject private var store: HostStore
    @State private var editing: Host?
    @State private var showingKeys = false

    var body: some View {
        NavigationStack {
            Group {
                if store.hosts.isEmpty {
                    ContentUnavailableView {
                        Label("No hosts configured", systemImage: "terminal")
                    } actions: {
                        Button("Add host") { editing = Host() }
                    }
                } else {
                    List {
                        ForEach(store.hosts) { host in
                            NavigationLink(value: host) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(host.displayName).font(.headline)
                                    Text(host.address).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button("Edit") { editing = host }.tint(.blue)
                            }
                            .contextMenu {
                                Button("Edit") { editing = host }
                            }
                        }
                        .onDelete(perform: store.delete)
                    }
                }
            }
            .navigationTitle("ConnectBot")
            .navigationDestination(for: Host.self) { host in
                TerminalScreen(host: host)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Keys") { showingKeys = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = Host() } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editing) { host in
                HostEditorView(host: host)
            }
            .sheet(isPresented: $showingKeys) {
                KeysView()
            }
        }
    }
}

// MARK: - Add / edit host

struct HostEditorView: View {
    @EnvironmentObject private var store: HostStore
    @Environment(\.dismiss) private var dismiss
    @State var host: Host
    @State private var password = ""
    @State private var hasSavedPassword = false
    @State private var forgotHostKey = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nickname (e.g. My Laptop)", text: $host.nickname)
                    TextField("Username", text: $host.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Host (e.g. 100.112.134.81)", text: $host.hostname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Port", value: $host.port, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                }
                Section("Login") {
                    Picker("Method", selection: $host.auth) {
                        ForEach(AuthMethod.allCases) { Text($0.label).tag($0) }
                    }
                    if host.auth == .password {
                        SecureField(hasSavedPassword ? "Password (saved; type to change)" : "Password (optional: asked when connecting)", text: $password)
                        if hasSavedPassword {
                            Button("Clear saved password", role: .destructive) {
                                Keychain.delete(account: Keychain.passwordAccount(for: host))
                                hasSavedPassword = false
                            }
                        }
                    } else {
                        Text("Uses the key from Keys on the host list. Its public key must be on the computer.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Terminal") {
                    Stepper("Font size: \(Int(host.fontSize))", value: $host.fontSize, in: 6...32)
                }
                if HostKeyStore.saved(for: host) != nil, !forgotHostKey {
                    Section {
                        Button("Forget saved host key", role: .destructive) {
                            HostKeyStore.forget(host: host)
                            forgotHostKey = true
                        }
                    } footer: {
                        Text("Only needed if the computer's SSH server was reinstalled.")
                    }
                }
            }
            .navigationTitle(store.hosts.contains { $0.id == host.id } ? "Edit host" : "Add host")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        host.username = host.username.trimmingCharacters(in: .whitespaces)
                        host.hostname = host.hostname.trimmingCharacters(in: .whitespaces)
                        if host.auth == .password, !password.isEmpty {
                            Keychain.set(Data(password.utf8), account: Keychain.passwordAccount(for: host))
                        }
                        store.save(host)
                        dismiss()
                    }
                    .disabled(host.hostname.isEmpty || host.username.isEmpty)
                }
            }
            .onAppear {
                hasSavedPassword = Keychain.get(account: Keychain.passwordAccount(for: host)) != nil
            }
        }
    }
}

// MARK: - Keys

struct KeysView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var publicKey = KeyManager.publicKeyLine
    @State private var copied = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                if let publicKey {
                    Section {
                        Text(publicKey).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        Button(copied ? "Copied" : "Copy public key") {
                            UIPasteboard.general.string = publicKey
                            copied = true
                        }
                        ShareLink(item: publicKey) { Label("Share public key", systemImage: "square.and.arrow.up") }
                    } header: {
                        Text("Your Ed25519 key")
                    } footer: {
                        Text("Put this line on the computer (Windows admin: C:\\ProgramData\\ssh\\administrators_authorized_keys), then set the host's login to Key. The public key is not secret.")
                    }
                    Section {
                        Button("Delete key", role: .destructive) { confirmDelete = true }
                    }
                } else {
                    Section {
                        Button("Generate key") {
                            KeyManager.generate()
                            publicKey = KeyManager.publicKeyLine
                        }
                    } footer: {
                        Text("Creates a login key that stays on this iPhone, so you can connect without typing a password.")
                    }
                }
            }
            .navigationTitle("Keys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete the key? Hosts using it will stop working until a new key is added to them.",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete key", role: .destructive) {
                    KeyManager.deleteKey()
                    publicKey = nil
                    copied = false
                }
            }
        }
    }
}

// MARK: - Terminal

struct TerminalScreen: View {
    let host: Host
    @StateObject private var session: SSHSession
    @State private var askPassword = false
    @State private var password = ""

    init(host: Host) {
        self.host = host
        _session = StateObject(wrappedValue: SSHSession(host: host))
    }

    var body: some View {
        TerminalRepresentable(view: session.terminalView)
            .background(Color.black)
            .navigationTitle(host.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if case .closed = session.state {
                        Button("Reconnect") { start() }
                    } else {
                        Button {
                            if let text = UIPasteboard.general.string { session.send(Array(text.utf8)) }
                        } label: { Image(systemName: "doc.on.clipboard") }
                    }
                }
            }
            .alert("Password for \(host.address)", isPresented: $askPassword) {
                SecureField("Password", text: $password)
                Button("Connect") { connect(with: password, save: false) }
                Button("Connect & save") { connect(with: password, save: true) }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear {
                if session.state == .idle { start() }
                _ = session.terminalView.becomeFirstResponder()
            }
            .onDisappear { session.disconnect() }
    }

    private func start() {
        if case .closed = session.state {
            // A fresh screen keeps things simple: reconnect on the same terminal.
            session.state = .idle
        }
        if host.auth == .password,
           Keychain.get(account: Keychain.passwordAccount(for: host)) == nil {
            password = ""
            askPassword = true
        } else {
            let saved = Keychain.get(account: Keychain.passwordAccount(for: host)).flatMap { String(data: $0, encoding: .utf8) }
            session.connect(password: saved)
        }
    }

    private func connect(with password: String, save: Bool) {
        if save { Keychain.set(Data(password.utf8), account: Keychain.passwordAccount(for: host)) }
        session.connect(password: password)
        _ = session.terminalView.becomeFirstResponder()
    }
}

struct TerminalRepresentable: UIViewRepresentable {
    let view: TerminalView

    func makeUIView(context: Context) -> TerminalView { view }
    func updateUIView(_ uiView: TerminalView, context: Context) {}
}
