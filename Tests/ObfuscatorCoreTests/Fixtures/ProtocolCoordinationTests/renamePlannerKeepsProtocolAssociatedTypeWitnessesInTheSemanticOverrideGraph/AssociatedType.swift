protocol Payload { associatedtype DTO }
struct Message: Payload { typealias DTO = String }
