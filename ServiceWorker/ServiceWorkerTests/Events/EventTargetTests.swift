import JavaScriptCore
@testable import ServiceWorker
import XCTest

class EventTargetTests: XCTestCase {
    func testShouldFireEvents() {
        let sw = ServiceWorker.createTestWorker(id: name)

        return sw.evaluateScript("""
            var didFire = false;
            self.addEventListener('test', function() {
                didFire = true;
            });
            self.dispatchEvent(new Event('test'));
            didFire;
        """)

            .map { (didFire: Bool?) -> Void in
                XCTAssertEqual(didFire, true)
            }
            .assertResolves()
    }

    func testShouldRemoveEventListeners() {
        let testEvents = EventTarget()

        let sw = ServiceWorker.createTestWorker(id: name)

        let expect = expectation(description: "Code ran")

        sw.withJSContext { context in
            context.globalObject.setValue(testEvents, forProperty: "testEvents")
        }
        .then {
            sw.evaluateScript("""
                var didFire = false;
                function trigger() {
                    didFire = true;
                }
                testEvents.addEventListener('test', trigger);
                testEvents.removeEventListener('test', trigger);
                testEvents.dispatchEvent(new Event('test'));
                didFire;
            """)
        }
        .compactMap { (didFire: Bool?) -> Void in
            XCTAssertEqual(didFire, false)
            expect.fulfill()
        }
        .catch { error -> Void in
            XCTFail("\(error)")
        }

        wait(for: [expect], timeout: 1)
    }

    func testShouldFireSwiftEvents() {
        let testEvents = EventTarget()
        var fired = false

        let testEvent = ConstructableEvent(type: "test")

        testEvents.addEventListener("test") { (ev: ConstructableEvent) in
            XCTAssertEqual(ev, testEvent)
            fired = true
        }

        testEvents.dispatchEvent(testEvent)

        XCTAssertTrue(fired)
    }
}
