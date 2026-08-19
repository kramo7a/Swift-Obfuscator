func inspect(_ value: Int?) -> Int {
    guard value != nil, let value = value else {
        return value ?? 0
    }
    return value
}
