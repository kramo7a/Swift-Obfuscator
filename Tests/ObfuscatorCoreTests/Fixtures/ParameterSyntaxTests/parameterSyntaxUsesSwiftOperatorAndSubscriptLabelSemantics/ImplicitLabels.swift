struct Sample {
    static func + (lhs: Sample, rhs: Sample) -> Sample {
        _ = lhs
        return rhs
    }
    subscript(index: Int) -> Int {
        index
    }
    subscript(label localIndex: Int) -> Int {
        localIndex
    }
}
