struct Schema: Codable {
    let value: Int
    enum CodingKeys: String, CodingKey { case value = "wire_value" }
}
