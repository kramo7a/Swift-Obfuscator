class Base {
    init(session: Int, url: String) {}
    convenience init(session: Int) {
        self.init(session: session, url: "")
    }
}
class Child: Base {}
let child = Child(session: 1)
