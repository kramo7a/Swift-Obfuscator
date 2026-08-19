func inspect(_ value: Int??) -> Int {
    if let value = value {
        guard let value else { return 0 }
        return value
    }
    return (value ?? nil) ?? 0
}
