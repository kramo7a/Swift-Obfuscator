func inspect(_ value: Int?) -> Int {
    guard let value else { return value ?? 0 }
    do {
        let value = value + 1
        _ = value
    }
    return value
}
