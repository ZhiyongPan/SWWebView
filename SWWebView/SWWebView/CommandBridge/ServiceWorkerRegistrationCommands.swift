import Foundation
import PromiseKit
import ServiceWorker
import ServiceWorkerContainer
import WebKit

class ServiceWorkerRegistrationCommands {
    static func unregister(eventStream: EventStream, json: AnyObject?) throws -> Promise<Any?>? {
        guard let registrationID = json?["id"] as? String else {
            throw ErrorMessage("Must provide registration ID in JSON body")
        }

        return eventStream.container.getRegistrations()
            .then { registrations -> Promise<Any?> in

                guard let registration = registrations.first(where: { $0.id == registrationID }) else {
                    throw ErrorMessage("Registration does not exist")
                }

                return registration.unregister().map { _ -> [String: Bool] in
                    [
                        "success": true
                    ]
                }
            }
    }
}
