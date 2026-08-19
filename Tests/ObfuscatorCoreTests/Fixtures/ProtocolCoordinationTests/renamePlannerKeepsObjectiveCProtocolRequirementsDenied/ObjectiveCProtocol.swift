@objc protocol LegacyService { func ping() }
final class Adapter: NSObject, LegacyService { func ping() {} }
