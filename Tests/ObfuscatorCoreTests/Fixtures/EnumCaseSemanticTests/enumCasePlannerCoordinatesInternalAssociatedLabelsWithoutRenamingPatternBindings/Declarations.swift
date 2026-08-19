enum InternalState {
    case idle
    case ready
}
enum InternalPayload {
    case payload(value: Int)
}
public enum PublicState {
    case visible
}
