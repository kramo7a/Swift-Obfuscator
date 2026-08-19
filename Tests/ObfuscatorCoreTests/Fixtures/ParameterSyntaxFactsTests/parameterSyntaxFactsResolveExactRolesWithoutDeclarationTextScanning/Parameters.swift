struct Sample {
    var stored: Int = 0 {
        willSet(nextValue) { _ = nextValue }
    }
    func outer(external local: Int) {
        func nested(_ nestedValue: Int, wire inner: Int = 1) {
            _ = local + nestedValue + inner
        }
    }
    subscript(offset index: Int) -> Int { index }
}
enum Event { case payload(label value: Int, _: String, Bool) }
let closure = { (closureValue: Int) in closureValue }
