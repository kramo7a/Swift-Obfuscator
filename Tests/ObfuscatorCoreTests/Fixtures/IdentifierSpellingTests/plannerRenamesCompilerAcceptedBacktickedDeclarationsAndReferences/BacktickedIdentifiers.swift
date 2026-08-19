struct `Type` {
    static let `default` = 4
    func `do`(_ value: Int) -> Int {
        value + Self.`default`
    }
}
let sample = `Type`()
precondition(sample.`do`(3) == 7)
