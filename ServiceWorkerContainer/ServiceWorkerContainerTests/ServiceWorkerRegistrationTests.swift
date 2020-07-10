import GCDWebServers
import JavaScriptCore
import PromiseKit
@testable import ServiceWorker
@testable import ServiceWorkerContainer
import XCTest

class ServiceWorkerRegistrationTests: XCTestCase {

    let factory = WorkerRegistrationFactory(withWorkerFactory: WorkerFactory())

    override func setUp() {
        super.setUp()
        CoreDatabase.clearForTests()
        TestWeb.createServer()
        URLCache.shared.removeAllCachedResponses()

        CoreDatabase.dbDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("testDB", isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: CoreDatabase.dbDirectory!.path) == false {
                try FileManager.default.createDirectory(at: CoreDatabase.dbDirectory!, withIntermediateDirectories: true, attributes: nil)
            }
        } catch {
            fatalError()
        }

        factory.workerFactory.serviceWorkerDelegateProvider = ServiceWorkerStorageProvider(storageURL: CoreDatabase.dbDirectory!)
        CoreDatabase.inConnection { connection -> Promise<Bool> in
            return .value(connection.open)
        }.assertResolves()
    }

    override func tearDown() {
        TestWeb.destroyServer()
    }

    func testCreateBlankRegistration() {
        var reg: ServiceWorkerRegistration?

        XCTAssertNoThrow(reg = try self.factory.create(scope: URL(string: "https://www.example.com")!))
        XCTAssertEqual(reg!.scope.absoluteString, "https://www.example.com")

        // An attempt to create a registration when one already exists should fail
        XCTAssertThrowsError(try self.factory.create(scope: URL(string: "https://www.example.com")!))
    }

    func testFailRegistrationOutOfScope() {
        var reg: ServiceWorkerRegistration?

        XCTAssertNoThrow(reg = try self.factory.create(scope: URL(string: "https://www.example.com/one")!))
        XCTAssertEqual(reg!.scope.absoluteString, "https://www.example.com/one")

        reg!.register(URL(string: "https://www.example.com/two/test.js")!)
            .assertRejects()
    }

    func testShouldPopulateWorkerFields() {
        XCTAssertNoThrow(try CoreDatabase.inConnection { connection in

            let registrationValues = ["https://www.example.com", "TEST_ID", "TEST_ID_active", "TEST_ID_installing", "TEST_ID_waiting", "TEST_ID_redundant"]
            _ = try connection.insert(sql: "INSERT INTO registrations (scope, registration_id, active, installing, waiting, redundant) VALUES (?,?,?,?,?,?)", values: registrationValues)

            try ["active", "installing", "waiting", "redundant"].forEach { state in

                let dummyWorkerValues: [Any] = [
                    "TEST_ID_" + state,
                    "https://www.example.com/worker.js",
                    "DUMMY_HEADERS",
                    "DUMMY_CONTENT",
                    ServiceWorkerInstallState.activated.rawValue,
                    "TEST_ID"
                ]

                _ = try connection.insert(sql: "INSERT INTO workers (worker_id, url, headers, content, install_state, registration_id) VALUES (?,?,?,?,?,?)", values: dummyWorkerValues)
            }

        })

        var reg: ServiceWorkerRegistration?
        XCTAssertNoThrow(reg = try self.factory.get(byScope: URL(string: "https://www.example.com")!)!)

        XCTAssert(reg!.active!.id == "TEST_ID_active")
        XCTAssert(reg!.installing!.id == "TEST_ID_installing")
        XCTAssert(reg!.waiting!.id == "TEST_ID_waiting")
        XCTAssert(reg!.redundant!.id == "TEST_ID_redundant")
    }

    func testShouldInstallWorker() {
        TestWeb.server!.addHandler(forMethod: "GET", path: "/test.js", request: GCDWebServerRequest.self) { (_) -> GCDWebServerResponse? in
            GCDWebServerDataResponse(data: """

            var installed = false;
            self.addEventListener("install", function() {
                installed = true
            });
            "testtest!"

            """.data(using: String.Encoding.utf8)!, contentType: "text/javascript")
        }

        firstly { () -> Promise<Void> in
            let reg = try factory.create(scope: TestWeb.serverURL)
            return reg.register(TestWeb.serverURL.appendingPathComponent("test.js"))
                .then { result in
                    result.registerComplete
                }
                .then { _ -> Promise<Bool> in
                    XCTAssertNotNil(reg.active)
                    return reg.active!.evaluateScript("installed")
                }
                .map { jsVal -> Void in
                    XCTAssertEqual(jsVal, true)
                }
        }
        .assertResolves()
    }

    func testShouldStayWaitingWhenActiveWorkerExists() {
        TestWeb.server!.addHandler(forMethod: "GET", path: "/test.js", request: GCDWebServerRequest.self) { (_) -> GCDWebServerResponse? in
            GCDWebServerDataResponse(text: "console.log('load')")
        }

        TestWeb.server!.addHandler(forMethod: "GET", path: "/test2.js", request: GCDWebServerRequest.self) { (_) -> GCDWebServerResponse? in
            GCDWebServerDataResponse(text: "console.log('load2')")
        }

        firstly { () -> Promise<Void> in
            let reg = try factory.create(scope: TestWeb.serverURL)
            return reg.register(TestWeb.serverURL.appendingPathComponent("test.js"))
                .then { result in
                    result.registerComplete
                }
                .then { (_) -> Promise<Void> in
                    let currentActive = reg.active
                    XCTAssertNotNil(currentActive)
                    return reg.register(TestWeb.serverURL.appendingPathComponent("test2.js"))
                        .then { result in
                            result.registerComplete
                        }
                        .map {
                            XCTAssertEqual(currentActive, reg.active)
                            XCTAssertNotNil(reg.waiting)
                            XCTAssertEqual(reg.active!.url.absoluteString, TestWeb.serverURL.appendingPathComponent("test.js").absoluteString)
                            XCTAssertEqual(reg.waiting!.url.absoluteString, TestWeb.serverURL.appendingPathComponent("test2.js").absoluteString)
                        }
                }
        }
        .assertResolves()
    }

    func testShouldReplaceWhenSkipWaitingCalled() {
        TestWeb.server!.addHandler(forMethod: "GET", path: "/test.js", request: GCDWebServerRequest.self) { (_) -> GCDWebServerResponse? in
            GCDWebServerDataResponse(data: "console.log('loader!')".data(using: String.Encoding.utf8)!, contentType: "text/javascript")
        }

        TestWeb.server!.addHandler(forMethod: "GET", path: "/test2.js", request: GCDWebServerRequest.self) { (_) -> GCDWebServerResponse? in
            GCDWebServerDataResponse(data: """
                self.addEventListener('install', function() {
                    self.skipWaiting();
                })
            """.data(using: String.Encoding.utf8)!, contentType: "text/javascript")
        }

        firstly { () -> Promise<Void> in
            let reg = try factory.create(scope: TestWeb.serverURL)
            return reg.register(TestWeb.serverURL.appendingPathComponent("test.js"))
                .then { result in
                    result.registerComplete
                }
                .then { (_) -> Promise<Void> in
                    let currentActive = reg.active
                    XCTAssertNotNil(currentActive)
                    return reg.register(TestWeb.serverURL.appendingPathComponent("test2.js"))
                        .then { result in
                            result.registerComplete
                        }
                        .map {
                            XCTAssertEqual(currentActive?.state, ServiceWorkerInstallState.redundant)
                            XCTAssertEqual(reg.active?.state, ServiceWorkerInstallState.activated)
                            XCTAssertEqual(reg.active?.url.absoluteString, TestWeb.serverURL.appendingPathComponent("test2.js").absoluteString)
                        }
                }
        }
        .assertResolves()
    }

    func testShouldBecomeRedundantIfInstallFails() {
        TestWeb.server!.addHandler(forMethod: "GET", path: "/test.js", request: GCDWebServerRequest.self) { (_) -> GCDWebServerResponse? in
            GCDWebServerDataResponse(data: """
                self.addEventListener('install', function(e) {
                    e.waitUntil(new Promise(function(fulfill, reject) {
                        reject(new Error("no"))
                    }))
                })
            """.data(using: String.Encoding.utf8)!, contentType: "text/javascript")
        }

        firstly { () -> Promise<Void> in
            let reg = try factory.create(scope: TestWeb.serverURL)

            return reg.register(TestWeb.serverURL.appendingPathComponent("test.js"))
                .then { result -> Promise<ServiceWorker?> in
                    return result.registerComplete
                        .then { () -> Promise<ServiceWorker?> in
                            return Promise.value(result.worker)
                        }
                        .recover { error -> Guarantee<ServiceWorker?> in
                            XCTAssertEqual("\(error)", "no")
                            return .value(result.worker)
                        }
                }
                .map { worker in
                    XCTAssertEqual(worker?.state, ServiceWorkerInstallState.activated)
                    XCTAssertEqual(reg.active, worker)
                }
        }
        .assertResolves()
    }

    func testActiveShouldRemainWhenInstallingWorkerFails() {
        TestWeb.server!.addHandler(forMethod: "GET", path: "/test.js", request: GCDWebServerRequest.self) { (_) -> GCDWebServerResponse? in
            GCDWebServerDataResponse(data: "".data(using: String.Encoding.utf8)!, contentType: "text/javascript")
        }

        TestWeb.server!.addHandler(forMethod: "GET", path: "/test2.js", request: GCDWebServerRequest.self) { (_) -> GCDWebServerResponse? in
            GCDWebServerDataResponse(data: """
                self.addEventListener('install', function() {
                    self.skipWaiting();
                })
                self.addEventListener('activate', function(e) {
                    e.waitUntil(new Promise(function(fulfill,reject) {
                        reject(new Error("no"));
                    }))
                });
            """.data(using: String.Encoding.utf8)!, contentType: "text/javascript")
        }

        firstly { () -> Promise<Void> in
            let reg = try factory.create(scope: TestWeb.serverURL)
            return reg.register(TestWeb.serverURL.appendingPathComponent("test.js"))
                .then { $0.registerComplete }
                .then { _ -> Promise<Void> in
                    let currentActive = reg.active
                    XCTAssertNotNil(currentActive)
                    return reg.register(TestWeb.serverURL.appendingPathComponent("test2.js"))
                        .then { register -> Promise<Void> in
                            register.registerComplete
                        }
                        .then { _ -> Promise<Void> in
                            XCTFail("Should not succeed!")
                            return .value
                        }
                        .recover { _ -> Void in
                            XCTAssertEqual(currentActive, reg.active)
                            XCTAssertNotNil(reg.redundant)
                            XCTAssertEqual(reg.active?.url.absoluteString, TestWeb.serverURL.appendingPathComponent("test.js").absoluteString)
                            XCTAssertEqual(reg.redundant?.url.absoluteString, TestWeb.serverURL.appendingPathComponent("test2.js").absoluteString)
                            return ()
                        }
                }
        }
        .assertResolves()
    }

    func testShouldFailWhenJSDoesNotParse() {
        TestWeb.server!.addHandler(forMethod: "GET", path: "/test.js", request: GCDWebServerRequest.self) { (_) -> GCDWebServerResponse? in
            GCDWebServerDataResponse(data: "][".data(using: String.Encoding.utf8)!, contentType: "text/javascript")
        }

        firstly { () -> Promise<Void> in
            let reg = try factory.create(scope: TestWeb.serverURL)
            return reg.register(TestWeb.serverURL.appendingPathComponent("test.js"))
                .then { $0.registerComplete }
                .map { () -> Void in
                    XCTFail("Should not succeed")
                }
                .recover { _ in
                    XCTAssertNotNil(reg.redundant)
                }
        }
        .assertResolves()
    }

    func testShouldNotUpdateWhenBytesMatch() {
        TestWeb.server!.addHandler(forMethod: "GET", path: "/test.js", request: GCDWebServerRequest.self) { (_) -> GCDWebServerResponse? in
            GCDWebServerDataResponse(data: """

            var installed = false;
            self.addEventListener("install", function() {
                installed = true
            });

            """.data(using: String.Encoding.utf8)!, contentType: "text/javascript")
        }

        firstly { () -> Promise<Void> in

            let reg = try factory.create(scope: TestWeb.serverURL)

            return reg.register(TestWeb.serverURL.appendingPathComponent("test.js"))
                .then { $0.registerComplete }
                .then { () -> Promise<Void> in
                    XCTAssertNotNil(reg.active)
                    return reg.update()
                }
                .map {
                    XCTAssertNil(reg.waiting)
                    try CoreDatabase.inConnection { db in
                        try db.select(sql: "SELECT count(*) AS workercount FROM workers") { resultSet in
                            _ = try? resultSet.next()
                            XCTAssertEqual(try resultSet.int("workercount"), 1)
                        }
                    }
                }
        }
        .assertResolves()
    }

    func testShouldUpdateWhenBytesChange() {
        var content = "'WORKERCONTENT1'"

        TestWeb.server!.addHandler(forMethod: "GET", path: "/test.js", request: GCDWebServerRequest.self) { (_) -> GCDWebServerResponse? in
            GCDWebServerDataResponse(data: content.data(using: String.Encoding.utf8)!, contentType: "text/javascript")
        }

        firstly { () -> Promise<Void> in

            let reg = try factory.create(scope: TestWeb.serverURL)

            return reg.register(TestWeb.serverURL.appendingPathComponent("test.js"))
                .then { $0.registerComplete }
                .then { () -> Promise<Void> in
                    XCTAssertNotNil(reg.active)
                    content = "'WORKERCONTENT2'"
                    return reg.update()
                }
                .map {
                    XCTAssertNotNil(reg.waiting)
                }
        }
        .assertResolves()
    }

    func testShouldUnregister() {
        self.testShouldInstallWorker()
        firstly { () -> Promise<Void> in
            let reg = try factory.get(byScope: TestWeb.serverURL)!
            let worker = reg.active!
            return reg.unregister()
                .map {
                    XCTAssertEqual(reg.unregistered, true)
                    XCTAssertEqual(worker.state, ServiceWorkerInstallState.redundant)
                    XCTAssertNil(try self.factory.get(byId: reg.id))
                }
        }
        .assertResolves()
    }
}
