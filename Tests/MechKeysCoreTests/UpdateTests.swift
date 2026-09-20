import Foundation
import Testing

@testable import MechKeysCore

@Suite("Release versions")
struct AppVersionTests {

    @Test("Versions compare by number, not as text")
    func comparesNumerically() {
        // The reason this type exists: "0.10.0" sorts before "0.9.0" as a
        // string, which would hide an update — and that is the very next tag
        // this project will publish.
        #expect(AppVersion("0.10.0")! > AppVersion("0.9.0")!)
        #expect(AppVersion("1.0.0")! > AppVersion("0.99.99")!)
        #expect(AppVersion("0.9.10")! > AppVersion("0.9.9")!)
        #expect(AppVersion("0.9.0")! == AppVersion("0.9.0")!)
    }

    @Test("A tag is accepted with or without its v")
    func acceptsTagForm() {
        // GitHub tags are `v0.9.0`; the bundle's version string is `0.9.0`.
        // Both have to land on the same value or every check would find an
        // update.
        #expect(AppVersion("v0.9.0") == AppVersion("0.9.0"))
        #expect(AppVersion("0.9")! == AppVersion(major: 0, minor: 9, patch: 0))
        #expect(AppVersion("2")! == AppVersion(major: 2, minor: 0, patch: 0))
    }

    @Test("A suffix is ignored rather than refused")
    func ignoresSuffix() {
        #expect(AppVersion("1.0.0-beta.1")! == AppVersion("1.0.0")!)
    }

    @Test("Nonsense is refused")
    func rejectsNonsense() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("nightly") == nil)
    }
}

@Suite("Release feed")
struct AppReleaseTests {

    /// The shape the release workflow actually publishes: a versioned image, a
    /// fixed-name copy of it for the website's download button, and checksums.
    private func json(
        tag: String = "v1.0.0",
        draft: Bool = false,
        prerelease: Bool = false,
        assets: String = """
        [{"name": "MechKeys-1.0.0.dmg",
          "browser_download_url": "https://example.invalid/MechKeys-1.0.0.dmg"},
         {"name": "MechKeys.dmg",
          "browser_download_url": "https://example.invalid/MechKeys.dmg"},
         {"name": "SHA256SUMS.txt",
          "browser_download_url": "https://example.invalid/SHA256SUMS.txt"}]
        """
    ) -> Data {
        Data(
            """
            {"tag_name": "\(tag)", "body": "notes", "draft": \(draft),
             "prerelease": \(prerelease), "assets": \(assets)}
            """.utf8)
    }

    private func decode(_ data: Data) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    @Test("A published release yields its disk image and checksums")
    func readsRelease() throws {
        let release = try #require(decode(json()).release)

        #expect(release.version == AppVersion("1.0.0"))
        #expect(release.checksums.lastPathComponent == "SHA256SUMS.txt")
    }

    @Test("The versioned image is preferred over the fixed-name copy")
    func prefersTheVersionedImage() throws {
        // Both are byte-identical, so either would install. The versioned name
        // is the one that says which release it came from, in the log and in
        // the SHA256SUMS.txt lookup.
        let release = try #require(decode(json()).release)
        #expect(release.diskImage.lastPathComponent == "MechKeys-1.0.0.dmg")
    }

    @Test("A release with only the fixed-name image still installs")
    func acceptsOnlyTheFixedName() throws {
        let assets = """
            [{"name": "MechKeys.dmg",
              "browser_download_url": "https://example.invalid/MechKeys.dmg"},
             {"name": "SHA256SUMS.txt",
              "browser_download_url": "https://example.invalid/SHA256SUMS.txt"}]
            """
        let release = try #require(decode(json(assets: assets)).release)
        #expect(release.diskImage.lastPathComponent == "MechKeys.dmg")
    }

    @Test("Drafts and pre-releases are not offered")
    func skipsUnfinishedReleases() throws {
        #expect(try decode(json(draft: true)).release == nil)
        #expect(try decode(json(prerelease: true)).release == nil)
    }

    @Test("A release with no checksums is not offered")
    func requiresChecksums() throws {
        // Without them an update cannot be verified, so it is not installed.
        let assets = """
            [{"name": "MechKeys-1.0.0.dmg",
              "browser_download_url": "https://example.invalid/MechKeys-1.0.0.dmg"}]
            """
        #expect(try decode(json(assets: assets)).release == nil)
    }

    @Test("A release with no disk image is not offered")
    func requiresDiskImage() throws {
        let assets = """
            [{"name": "SHA256SUMS.txt",
              "browser_download_url": "https://example.invalid/SHA256SUMS.txt"}]
            """
        #expect(try decode(json(assets: assets)).release == nil)
    }

    @Test("A tag that is not a version is not offered")
    func requiresVersionTag() throws {
        #expect(try decode(json(tag: "nightly")).release == nil)
    }
}

@Suite("Checksums")
struct ChecksumsTests {
    private let digest = String(repeating: "a", count: 64)

    @Test("The digest is found by file name")
    func findsDigest() {
        // SHA256SUMS.txt carries a line for the versioned image and one for
        // the fixed-name copy; the right one has to come back.
        let text = """
            \(String(repeating: "b", count: 64))  MechKeys.dmg
            \(digest)  MechKeys-1.0.0.dmg
            """
        #expect(Checksums.digest(for: "MechKeys-1.0.0.dmg", in: text) == digest)
    }

    @Test("A binary marker and a leading path are both tolerated")
    func toleratesShasumForms() {
        #expect(Checksums.digest(for: "a.dmg", in: "\(digest) *a.dmg") == digest)
        #expect(Checksums.digest(for: "a.dmg", in: "\(digest)  dist/a.dmg") == digest)
    }

    @Test("A missing or malformed entry yields nothing")
    func rejectsRubbish() {
        #expect(Checksums.digest(for: "a.dmg", in: "\(digest)  b.dmg") == nil)
        #expect(Checksums.digest(for: "a.dmg", in: "not-a-digest  a.dmg") == nil)
        #expect(Checksums.digest(for: "a.dmg", in: "") == nil)
    }
}

@Suite("Announcing an installed update")
struct UpdateAnnouncementTests {

    @Test("A newer version than last time is an update that landed")
    func announcesAnUpgrade() {
        let installed = UpdateAnnouncement.installedVersion(
            current: AppVersion("1.0.0"), previous: AppVersion("0.9.0"))
        #expect(installed == AppVersion("1.0.0"))
    }

    @Test("The same version is an ordinary launch")
    func saysNothingOnARelaunch() {
        // Quitting and reopening must not look like an update.
        #expect(
            UpdateAnnouncement.installedVersion(
                current: AppVersion("0.9.0"), previous: AppVersion("0.9.0")) == nil)
    }

    @Test("A first launch has nothing to compare against")
    func saysNothingOnAFreshInstall() {
        #expect(
            UpdateAnnouncement.installedVersion(current: AppVersion("0.9.0"), previous: nil) == nil)
    }

    @Test("A downgrade is not announced as an update")
    func saysNothingWhenGoingBackwards() {
        // Putting an older copy back is not something to congratulate anyone
        // on, and a `swift build` binary has no version at all.
        #expect(
            UpdateAnnouncement.installedVersion(
                current: AppVersion("0.9.0"), previous: AppVersion("1.0.0")) == nil)
        #expect(
            UpdateAnnouncement.installedVersion(current: nil, previous: AppVersion("0.9.0")) == nil)
    }
}

@Suite("Update failures")
@MainActor
struct UpdateFailureTests {

    private func makeChecker() -> UpdateChecker {
        let name = "com.mechkeys.tests.update.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return UpdateChecker(store: SettingsStore(defaults: defaults), defaults: defaults)
    }

    private var release: AppRelease {
        AppRelease(
            version: AppVersion(major: 1, minor: 0, patch: 0),
            notes: "",
            diskImage: URL(string: "https://example.invalid/MechKeys-1.0.0.dmg")!,
            checksums: URL(string: "https://example.invalid/SHA256SUMS.txt")!
        )
    }

    @Test("Retry after a failed check looks again rather than installing")
    func retriesTheCheck() {
        // Retry has to know which half failed: a check that could not reach
        // GitHub has no release to install, and retrying the wrong one would
        // do nothing at all.
        let checker = makeChecker()
        checker.preview(
            .failed(UpdateChecker.Failure(message: "offline", retry: .check)))

        guard case .failed(let failure) = checker.state else {
            Issue.record("expected a failure state")
            return
        }
        #expect(failure.retry == .check)
    }

    @Test("Retry after a failed install remembers which release to install")
    func retriesTheInstall() {
        let checker = makeChecker()
        checker.preview(
            .failed(UpdateChecker.Failure(message: "checksum", retry: .install(release))))

        guard case .failed(let failure) = checker.state,
            case .install(let pending) = failure.retry
        else {
            Issue.record("expected an install failure")
            return
        }
        #expect(pending.version == AppVersion("1.0.0"))
    }

    @Test("Retry does nothing when nothing has failed")
    func ignoresRetryWhenIdle() {
        let checker = makeChecker()
        checker.preview(.upToDate)
        checker.retry()
        #expect(checker.state == .upToDate)
    }

    @Test("Dismissing an answer clears it, but leaves work in flight alone")
    func dismissClearsAnswersOnly() {
        // The panel closing is not a cancel: a replacement half-written to
        // /Applications has to finish.
        let checker = makeChecker()

        checker.preview(.upToDate)
        checker.dismiss()
        #expect(checker.state == .idle)

        checker.preview(.available(release))
        checker.dismiss()
        #expect(checker.state == .idle)

        checker.preview(.installing)
        checker.dismiss()
        #expect(checker.state == .installing)
    }

    @Test("A check is refused while one is already running")
    func refusesOverlappingChecks() async {
        let checker = makeChecker()
        checker.preview(.downloading(0.5))
        await checker.check(userInitiated: true)
        #expect(checker.state == .downloading(0.5))
    }
}

@Suite("Recording the launched version")
@MainActor
struct UpdateLaunchTests {

    @Test("The version this launch ran as is written down")
    func recordsTheVersion() {
        // Nothing survives the bundle being replaced and restarted, so the
        // only way to notice an update landed is to have written the previous
        // version somewhere durable.
        let name = "com.mechkeys.tests.launch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        let checker = UpdateChecker(
            store: SettingsStore(defaults: defaults), defaults: defaults)
        checker.recordLaunch()

        // Under `swift test` there is no bundle version, so nothing is
        // recorded and nothing is announced — which is the behaviour a
        // development build should have.
        if AppVersion.current == nil {
            #expect(defaults.string(forKey: UpdateChecker.lastRunVersionKey) == nil)
            #expect(checker.installedVersion == nil)
        } else {
            #expect(
                defaults.string(forKey: UpdateChecker.lastRunVersionKey)
                    == AppVersion.current?.description)
        }
    }
}
