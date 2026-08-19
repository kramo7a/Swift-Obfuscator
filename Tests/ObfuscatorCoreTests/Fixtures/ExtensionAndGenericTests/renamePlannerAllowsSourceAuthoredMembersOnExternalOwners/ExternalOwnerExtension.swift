extension String {
    func framed() -> String { "[\(self)]" }
}
precondition("value".framed() == "[value]")
