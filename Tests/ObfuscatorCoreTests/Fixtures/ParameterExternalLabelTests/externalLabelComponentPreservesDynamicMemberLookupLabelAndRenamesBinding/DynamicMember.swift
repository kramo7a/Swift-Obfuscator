struct Root { let value: Int }
@dynamicMemberLookup
struct Wrapper {
    let root: Root
    subscript<T>(dynamicMember keyPath: KeyPath<Root, T>) -> T {
        root[keyPath: keyPath]
    }
}
