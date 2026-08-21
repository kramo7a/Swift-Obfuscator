func nextState() -> InternalState {
    .ready
}
let state = InternalState.idle
let sample = InternalPayload.payload(value: 1)
func payloadValue(_ input: InternalPayload) -> Int {
    switch input {
    case .payload(let value):
        value
    }
}
func labeledPayloadValue(_ input: InternalPayload) -> Int {
    switch input {
    case .payload(value: let value):
        value
    }
}
func ignoredPayloadValue(_ input: InternalPayload) -> Int {
    switch input {
    case .payload:
        0
    }
}
