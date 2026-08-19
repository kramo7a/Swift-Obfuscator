func inspect(_ value: Int?) -> Int {
    if let value {
        let value = value + 1
        return value
    }
    return value ?? 0
}
