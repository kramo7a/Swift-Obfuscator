func work(_ action: (Int) -> Void) { action(0) }
func compute(state: Int, commands: (Int) -> Void) {
    func nested(state: Int) { commands(state) }
    work { state in commands(state) }
    work { [state = state] _ in commands(state) }
    nested(state: state)
    commands(state)
}
compute(state: 1, commands: { _ in })
