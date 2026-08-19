func combine(_ hidden: Int, wire local: Int, shorthand: Int) -> Int {
    hidden + local + shorthand
}
let result = combine(1, wire: 2, shorthand: 3)
let functionValue = combine
struct Box {
    init(loadController: Int, workspaceId localWorkspaceID: Int) {
        _ = loadController + localWorkspaceID
    }
}
func broken(one: Int) {}
enum Event { case received(payload: Int) }
struct Table { subscript(offset index: Int) -> Int { index } }
