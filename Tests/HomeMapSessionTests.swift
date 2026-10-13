import XCTest
@testable import HomeMapSessionChecks

@MainActor
final class HomeMapSessionTests: XCTestCase {
    private func session() -> HomeMapSession {
        let session = HomeMapSession()
        session.container = MapPresentationContainer(frame: .zero)
        session.coordinator = MapView.Coordinator()
        return session
    }

    func testNewTabAttachesBeforeOldTabDismantles() {
        let session = session()
        let home = HomeMapHost(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        let settings = HomeMapHost(frame: home.frame)
        home.session = session
        settings.session = session
        let map = session.container!.map
        XCTAssertTrue(session.attach(to: home))
        XCTAssertTrue(session.attach(to: settings))
        session.release(home)
        XCTAssertTrue(session.activeHost === settings)
        XCTAssertTrue(session.container?.superview === settings)
        XCTAssertTrue(session.container?.map === map)
        XCTAssertEqual(session.coordinator?.dismantles, 0)
        XCTAssertFalse(session.attach(to: settings))
    }

    func testOldTabDismantlesBeforeNewTabAttaches() {
        let session = session()
        let home = HomeMapHost(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        let settings = HomeMapHost(frame: home.frame)
        let container = session.container
        session.attach(to: home)
        session.release(home)
        XCTAssertNil(container?.superview)
        session.attach(to: settings)
        XCTAssertTrue(session.container === container)
        XCTAssertTrue(container?.superview === settings)
        XCTAssertEqual(session.coordinator?.dismantles, 0)
    }

    func testOnlyActiveHostCanRelayoutRenderer() {
        let session = session()
        let home = HomeMapHost(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        let settings = HomeMapHost(frame: CGRect(x: 0, y: 0, width: 850, height: 600))
        home.session = session
        settings.session = session
        session.attach(to: home)
        session.attach(to: settings)
        home.layoutSubviews()
        XCTAssertEqual(session.coordinator?.layouts, 0)
        settings.layoutSubviews()
        XCTAssertEqual(session.coordinator?.layouts, 1)
        XCTAssertEqual(session.container?.bounds.size, settings.bounds.size)
    }

    func testContextAndHostDoNotRetainSessionAndDisposeOnce() {
        var session: HomeMapSession? = session()
        weak var weakSession = session
        let coordinator = session!.coordinator!
        let context = HomeMapContext(session: session, isActive: true)
        let home = HomeMapHost()
        home.session = session
        session!.attach(to: home)
        session = nil
        XCTAssertNil(weakSession)
        XCTAssertNil(context.session)
        XCTAssertNil(home.session)
        XCTAssertEqual(coordinator.dismantles, 1)
    }

    func testUnlaidOutNewHostDoesNotCollapseLiveMap() {
        let session = session()
        let home = HomeMapHost(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        let settings = HomeMapHost()
        settings.session = session
        session.attach(to: home)
        session.attach(to: settings)
        settings.layoutSubviews()
        XCTAssertEqual(session.container?.bounds.size, home.bounds.size)
        XCTAssertEqual(session.coordinator?.layouts, 0)
    }

    func testLastHostReleasesCallbacksCapturingTheSessionOwner() {
        var session: HomeMapSession? = session()
        weak var weakSession = session
        let coordinator = session!.coordinator!
        coordinator.parent.onMapBlankTap = { [session] in _ = session }
        let home = HomeMapHost()
        home.session = session
        session!.attach(to: home)
        session = nil
        XCTAssertNotNil(weakSession)
        weakSession?.release(home)
        XCTAssertNil(weakSession)
        XCTAssertEqual(coordinator.dismantles, 1)
    }
}
