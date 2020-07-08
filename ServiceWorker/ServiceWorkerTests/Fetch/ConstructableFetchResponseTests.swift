import XCTest
@testable import ServiceWorker
import PromiseKit
import JavaScriptCore

class ConstructableFetchResponseTests: XCTestCase {

    func testManualTextResponseCreationInWorker() {

        let sw = ServiceWorker.createTestWorker(id: self.name)

        sw.evaluateScript("""
            var response = new Response("hello");
            response.text()
            .then((text) => {
                return [text, response.status, response.url, response.headers.get('content-type')]
            })
        """)
            .then { (jsVal: JSContextPromise) -> Promise<[Any?]> in
                return jsVal.resolve()
            }
            .compactMap { (array) in
                XCTAssertEqual(array[0] as? String, "hello")
                XCTAssertEqual(array[1] as? Int, 200)
                XCTAssertEqual(array[2] as? String, "")
                XCTAssertEqual(array[3] as? String, "text/plain;charset=UTF-8")
            }
            .assertResolves()
    }

    func testResponseConstructionOptions() {

        let sw = ServiceWorker.createTestWorker(id: self.name)

        sw.evaluateScript("""
            new Response("hello", {
                status: 201,
                statusText: "CUSTOM TEXT",
                headers: {
                    "X-Custom-Header":"blah",
                    "Content-Type":"text/custom-content"
                }
            })
        """)
            .then { (response: FetchResponseProxy?) -> Promise<String> in
                XCTAssertEqual(response!.status, 201)
                XCTAssertEqual(response!.statusText, "CUSTOM TEXT")
                XCTAssertEqual(response!.headers.get("X-Custom-Header"), "blah")
                XCTAssertEqual(response!.headers.get("Content-Type"), "text/custom-content")
                return response!.text()
            }
            .map { text -> Void in
                XCTAssertEqual(text, "hello")
            }
            .assertResolves()
    }

    func testResponseWithArrayBuffer() {

        let sw = ServiceWorker.createTestWorker(id: self.name)

        sw.evaluateScript("""
            let buffer = new Uint8Array([1,2,3,4]).buffer;
            new Response(buffer)
        """)
            .then { (response: FetchResponseProtocol?) -> Promise<Data> in
                return response!.data()
            }
            .map { data -> Void in
                let array = [UInt8](data)
                XCTAssertEqual(array[0], 1)
                XCTAssertEqual(array[1], 2)
                XCTAssertEqual(array[2], 3)
                XCTAssertEqual(array[3], 4)
            }
            .assertResolves()
    }
}
