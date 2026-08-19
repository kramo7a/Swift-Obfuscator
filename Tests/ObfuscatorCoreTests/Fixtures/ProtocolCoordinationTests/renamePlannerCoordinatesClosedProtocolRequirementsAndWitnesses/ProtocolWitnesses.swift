protocol Analyzer {
    func run()
}
struct First: Analyzer { func run() {} }
struct Second: Analyzer { func run() {} }
func exercise(_ value: any Analyzer) { value.run() }
func exerciseFirst() { First().run() }
func exerciseSecond() { Second().run() }
