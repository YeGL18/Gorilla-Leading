import Foundation

// Run inside a disposable macOS .app fixture with ParkingCommunityAPIBaseURL
// set to the production URL. This exercises the actual resolver without Keychain.
@main struct NamedTunnelConfigurationChecks {
    static func main() {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        precondition(domain == "com.gorilla.named-tunnel-checks")
        defer { defaults.removePersistentDomain(forName: domain) }
        let production = "https://api.lucidtelos.com/v1/parking-community"
        func reset() { defaults.removePersistentDomain(forName: domain) }
        reset()
        precondition(CommunityHTTPClient.configuredURL?.absoluteString == production)
        reset()
        defaults.set("https://old-test.trycloudflare.com/v1/parking-community", forKey: CommunityHTTPClient.overrideKey)
        precondition(CommunityHTTPClient.configuredURL?.absoluteString == production)
        precondition(defaults.string(forKey: CommunityHTTPClient.overrideKey) == nil)
        // An intentionally saved developer tunnel after migration remains usable.
        let next = "https://new-test.trycloudflare.com/v1/parking-community"
        defaults.set(next, forKey: CommunityHTTPClient.overrideKey)
        precondition(CommunityHTTPClient.configuredURL?.absoluteString == next)
        reset()
        let custom = "https://custom.example/v1/parking-community"
        defaults.set(custom, forKey: CommunityHTTPClient.overrideKey)
        precondition(CommunityHTTPClient.configuredURL?.absoluteString == custom)
        reset()
        let lookalike = "https://trycloudflare.com.example/v1/parking-community"
        defaults.set(lookalike, forKey: CommunityHTTPClient.overrideKey)
        precondition(CommunityHTTPClient.configuredURL?.absoluteString == lookalike)
        print("PASS: fixed endpoint, one-time temporary tunnel migration, custom server preservation")
    }
}
