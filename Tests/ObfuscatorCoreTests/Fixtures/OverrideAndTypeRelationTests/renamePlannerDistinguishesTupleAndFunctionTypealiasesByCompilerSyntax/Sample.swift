enum Namespace {
    typealias Payload = (id: Int, value: String)
    typealias Handler =
        (Int) -> Void
}
let payload = Namespace.Payload(id: 1, value: "one")
let handler: Namespace.Handler = { _ in }
handler(payload.id)
