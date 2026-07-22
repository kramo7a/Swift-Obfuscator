struct Greeter {
    var message: String

    func greet(name: String) -> String {
        let decoratedName = name.uppercased()
        return "\(message), \(decoratedName)"
    }
}

func makeGreeting() -> String {
    let greeter = Greeter(message: "Hello")
    return greeter.greet(name: "Swift")
}

print(makeGreeting())
