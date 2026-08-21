struct Service {
    func send(required: Int, optional: Int = 0, values: Int..., completion: () -> Void, failure: () -> Void) {}
    func choose(first: () -> Void = {}, second: () -> Void = {}) {}
    func finish(animated: Bool = true, completion: (() -> Void)? = nil) {}
}
func use(service: Service) {
    service.send(required: 1, values: 2, 3) {} failure: {}
    service.choose {}
    service.finish {}
}
