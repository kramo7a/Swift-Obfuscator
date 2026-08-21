protocol Service {
    func send(wire requirementValue: Int)
}
struct ServiceImpl: Service {
    func send(wire localValue: Int) {
        _ = localValue
    }
}
func exercise(service: Service) {
    service.send(wire: 1)
    _ = Service.send(wire:)
}
