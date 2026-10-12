import Foundation

enum AuthMethod: String, Codable, CaseIterable, Identifiable {
    case password
    case key

    var id: String { rawValue }

    var label: String {
        switch self {
        case .password: return "Password"
        case .key: return "Key (no password)"
        }
    }
}

struct Host: Codable, Identifiable, Hashable {
    var id = UUID()
    var nickname = ""
    var username = ""
    var hostname = ""
    var port = 22
    var auth: AuthMethod = .password
    var fontSize: Double = 12

    var displayName: String { nickname.isEmpty ? "\(username)@\(hostname)" : nickname }
    var address: String { port == 22 ? "\(username)@\(hostname)" : "\(username)@\(hostname):\(port)" }
}

/// The saved host list, kept in UserDefaults as JSON. Passwords live in the Keychain, not here.
@MainActor
final class HostStore: ObservableObject {
    @Published private(set) var hosts: [Host] = []

    private let defaultsKey = "hosts.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([Host].self, from: data) {
            hosts = saved
        }
    }

    func save(_ host: Host) {
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
        persist()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            let host = hosts[index]
            Keychain.delete(account: Keychain.passwordAccount(for: host))
            HostKeyStore.forget(host: host)
        }
        hosts.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
