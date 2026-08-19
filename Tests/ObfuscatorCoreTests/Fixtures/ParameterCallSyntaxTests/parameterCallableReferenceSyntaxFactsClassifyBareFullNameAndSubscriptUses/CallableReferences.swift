struct Service {
    func convert(value: Int) -> Int { value }
    subscript(label value: Int) -> Int { value }
}
func use(service: Service) {
    let bare = service.convert
    let full = service.convert(value:)
    _ = service[label: 1]
    let mismatched = service.convert(other:)
}
