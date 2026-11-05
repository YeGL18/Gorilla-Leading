# Run with: ruby Tests/TripReplayCompletionChecks.rb
# Exercise production transport/lifecycle code without launching an app or display link.
require 'tmpdir'
repo = File.expand_path('..', __dir__)
source = File.read("#{repo}/GorillaTranslate/Views/TripReplayView.swift")
model = File.read("#{repo}/GorillaTranslate/Models/TripReplay.swift")

def section(source, first, last)
  start = source.index(first) or abort "Missing #{first}"
  finish = source.index(last, start) or abort "Missing #{last}"
  source[start...finish]
end

transport = section(source, '@MainActor' + "\nprivate final class ReplayReadoutClock", 'private struct ReplayTimeReader')
transport = transport.gsub('@MainActor', '').gsub('private final class Replay', 'final class Replay')
transport = transport.sub(/    private func startLink\(\) \{.*?^    \}/m, '    private func startLink() { }')
transport = transport.gsub('@objc ', '').sub('private func frame(', 'func frame(')
motion = section(model, 'struct ReplayScrubMotion {', 'struct ReplayAltitudeFilter {')
# Keep the actual presentation binding setter and lifecycle methods under test.
binding = section(source, '    private var detailsPresentation:', '    private func pausePlayback()')
binding = binding.gsub(/\b(showDetails|detailsDismissing)\b/, 'self.\\1')
methods = section(source, '    private func pausePlayback()', '    var body: some View {' + "\n        Group {")

Dir.mktmpdir('gorilla-replay-completion-') do |root|
  fixture = <<~SWIFT
    import Foundation
    typealias CFTimeInterval = Double
    protocol ObservableObject {}
    @propertyWrapper struct Published<Value> {
        var wrappedValue: Value
    }
    struct Binding<Value> {
        let get: () -> Value
        let set: (Value) -> Void
        init(get: @escaping () -> Value, set: @escaping (Value) -> Void) { self.get = get; self.set = set }
    }
    final class CADisplayLink {
        var timestamp: Double = 0
        func invalidate() {}
    }
    #{motion}
    #{transport}
    final class DetailHarness {
        enum Phase { case active, inactive }
        var scenePhase = Phase.active
        var replayVisible = true
        var playing = true
        var playbackRate = 8.0
        var showDetails = true
        var detailsDismissing = false
        var reopenDetailsAfterDismiss = false
        var trip: Bool? = true
        let transport = ReplayTransport()
        #{binding}
        #{methods}
        func dismissSheet() { detailsPresentation.set(false) }
        func finish() { playbackEnded() }
        func didDismiss() { detailsDismissed() }
        func pause() { pausePlayback() }
        func leave() { leaveReplay() }
    }
    let start = Date(timeIntervalSince1970: 1000)
    let end = start.addingTimeInterval(0.1)
    let transport = ReplayTransport()
    let display = CADisplayLink()
    var completions = 0
    transport.onPlaybackEnded = { completions += 1 }
    transport.configure(start: start, end: end, sampleCount: 2)
    transport.play(true, rate: 16)
    transport.frame(display)
    precondition(completions == 1 && transport.selection == end)
    transport.frame(display)
    precondition(completions == 1, "Completion must fire once")
    transport.seek(end)
    transport.frame(display)
    transport.play(false, rate: 16)
    transport.frame(display)
    transport.scrub(end, speed: 1000)
    for _ in 0..<300 { display.timestamp += 1.0 / 60; transport.frame(display) }
    precondition(completions == 1, "Seek, pause and scrub at end are not completion")
    transport.seek(start)
    transport.play(true, rate: 16)
    transport.stop()
    transport.frame(display)
    precondition(completions == 1, "Stopping must cancel completion")

    transport.seek(start)
    transport.play(true, rate: 16)
    transport.frame(display)
    precondition(completions == 2, "A new playback run must still complete normally")

    let normal = DetailHarness()
    normal.finish()
    precondition(!normal.playing && normal.showDetails)
    let hidden = DetailHarness()
    hidden.dismissSheet()
    precondition(hidden.playing, "Swipe dismissal must preserve playback")
    hidden.didDismiss()
    hidden.finish()
    precondition(!hidden.playing && hidden.showDetails)
    let racing = DetailHarness()
    racing.dismissSheet()
    racing.finish()
    precondition(!racing.showDetails && racing.reopenDetailsAfterDismiss)
    racing.didDismiss()
    precondition(racing.showDetails && !racing.reopenDetailsAfterDismiss)
    for cancel in 0..<4 {
        let detail = DetailHarness()
        detail.dismissSheet()
        detail.finish()
        switch cancel {
        case 0: detail.pause() // Also used by seek/scrub.
        case 1: detail.leave()
        case 2: detail.scenePhase = .inactive; detail.pause()
        default: detail.trip = nil
        }
        detail.didDismiss()
        precondition(!detail.showDetails, "Cancelled completion must not reopen")
    }
    let stale = DetailHarness()
    stale.leave()
    stale.finish()
    stale.didDismiss()
    precondition(!stale.showDetails && stale.transport.onPlaybackEnded == nil)
    let inactive = DetailHarness()
    inactive.showDetails = false
    inactive.scenePhase = .inactive
    inactive.finish()
    precondition(!inactive.showDetails)
    let paused = DetailHarness()
    paused.dismissSheet()
    paused.pause()
    paused.finish()
    paused.didDismiss()
    precondition(!paused.showDetails)
    print("PASS: natural completion, hidden/dismissing sheet, pause/scrub/stop, departure/background/deletion cancellation")
  SWIFT
  File.write("#{root}/Checks.swift", fixture)
  abort 'Compile failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache', "#{root}/Checks.swift", '-o', "#{root}/checks")
  abort 'Checks failed' unless system("#{root}/checks")
end
