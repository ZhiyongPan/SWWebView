import UIKit
import SWWebView
import WebKit
import GCDWebServers
import ServiceWorkerContainer
import ServiceWorker
import PromiseKit

class ViewController: UIViewController {

    var coordinator: SWWebViewCoordinator?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        self.addStubs()
        let config = WKWebViewConfiguration()

        Log.info = { print($0) }

        let storageURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("testapp-db", isDirectory: true)

        do {
            if FileManager.default.fileExists(atPath: storageURL.path) {
                try FileManager.default.removeItem(at: storageURL)
            }
            try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            fatalError()
        }

        self.coordinator = SWWebViewCoordinator(storageURL: storageURL)

        let swView = SWWebView(frame: self.view.frame, configuration: config)
        // This will move to a delegate method eventually
        swView.serviceWorkerPermittedDomains.append("localhost:8000")
        swView.serviceWorkerPermittedDomains.append("localhost")
        swView.containerDelegate = self.coordinator!
        self.view.addSubview(swView)

        let url = URLComponents(string: "http://localhost:8000/")!
        URLCache.shared.removeAllCachedResponses()
        print("Loading \(url.url!.absoluteString)")
        _ = swView.load(URLRequest(url: url.url!))
    }

    func addStubs() {
        SWWebViewBridge.routes["/ping"] = { _, _ in

            Promise.value([
                "pong": true
            ])
        }

        SWWebViewBridge.routes["/ping-with-body"] = { _, json in

            let responseText = json?["value"] as? String ?? "no body found"

            return Promise.value([
                "pong": responseText
            ])
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}
