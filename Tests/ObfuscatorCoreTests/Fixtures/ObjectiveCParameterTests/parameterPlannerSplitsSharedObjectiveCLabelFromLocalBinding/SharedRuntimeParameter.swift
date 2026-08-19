import Foundation
final class RuntimeBridge: NSObject {
    @objc(executePayload:)
    func execute(payload: Int) -> Int { payload + 1 }
}
precondition(RuntimeBridge().execute(payload: 41) == 42)
