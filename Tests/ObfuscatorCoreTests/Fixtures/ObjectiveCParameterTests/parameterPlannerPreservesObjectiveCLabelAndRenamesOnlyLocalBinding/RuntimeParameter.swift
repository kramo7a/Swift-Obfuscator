import Foundation
final class RuntimeBridge: NSObject {
    @objc(executePayload:)
    func execute(payload value: Int) -> Int { value + 1 }
}
precondition(RuntimeBridge().execute(payload: 41) == 42)
