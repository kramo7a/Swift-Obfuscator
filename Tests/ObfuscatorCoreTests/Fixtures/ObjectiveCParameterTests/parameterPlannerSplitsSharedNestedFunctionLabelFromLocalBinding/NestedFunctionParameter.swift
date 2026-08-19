func outer() {
    func configure(layer: Int) -> Int { layer }
    precondition(configure(layer: 41) == 41)
}
outer()
