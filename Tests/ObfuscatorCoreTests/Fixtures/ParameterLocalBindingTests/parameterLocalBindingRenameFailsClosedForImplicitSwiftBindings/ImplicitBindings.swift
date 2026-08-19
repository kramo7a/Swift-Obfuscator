func catchShadow(_ error: Error) {
    do { throw error } catch { _ = error }
}
subscript(_ newValue: Int) -> Int {
    get { newValue }
    set { print(newValue) }
}
func observerShadow(_ oldValue: Int) {
    var value = 0 { didSet { print(oldValue) } }
    print(oldValue, value)
}
