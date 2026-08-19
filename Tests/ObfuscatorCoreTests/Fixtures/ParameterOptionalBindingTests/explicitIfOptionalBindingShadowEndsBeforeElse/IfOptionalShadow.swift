func inspect(_ value: Int?) -> Int {
    if let value = value {
        return value
    } else {
        return value ?? 0
    }
}
