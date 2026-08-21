struct Box {
    init(first: Int, second: Int = 0) {}
}
func consume<T>(value: T) {}
func use(box: Box) {
    _ = Box(first: 1)
    box.run(value: 2) {}
    consume<Int>(value: 3)
    _ = box[index: 0]
    box.perform(value: 4) {} failure: {}
    @Wrapper(value: 5) var wrapped = 0
    box.show(сallSettingsSource: 6)
}
