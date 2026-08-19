struct ContextualBox {
    var value: Int {
        didSet { precondition(value >= 0) }
    }
    var prefix: Int
    func get() -> Self {
        Self(value: value, prefix: prefix)
    }
    func set(_ newValue: Int) -> Self {
        Self(value: newValue, prefix: prefix)
    }
    subscript(_ offset: Int) -> Int {
        value + offset
    }
}
var sample = ContextualBox(value: 1, prefix: 2)
sample.value = 3
precondition(sample.get().prefix == 2)
precondition(sample.set(4)[1] == 5)
