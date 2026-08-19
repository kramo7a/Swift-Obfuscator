struct Box<Value: Hashable> {
    let stored: Value
    func accept(_ input: Value) {
        let _: Value = input
    }
}
typealias Alias = String
