struct Group {}
func inspect(_ group: Group) -> Group {
    _ = { let group = Group(); _ = group }
    return group
}
