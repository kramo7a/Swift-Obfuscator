enum Focus { case standard; case commented(Int) }
func route(_ groupId: Int, focus: Focus) -> Int {
    let result = switch focus {
    case .standard: groupId
    case .commented(let groupId): groupId
    }
    return result + groupId
}
