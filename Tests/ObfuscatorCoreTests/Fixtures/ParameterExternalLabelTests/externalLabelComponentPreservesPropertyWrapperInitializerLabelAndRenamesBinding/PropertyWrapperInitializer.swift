@propertyWrapper
struct Wrapper<Value> {
    var wrappedValue: Value
    init(wrappedValue value: Value) {
        wrappedValue = value
    }
}
