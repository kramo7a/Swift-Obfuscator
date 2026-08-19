protocol Service { func run() }
struct LocalModel {}
extension LocalModel { func localHelper() {} }
extension String { struct ExternalNested { func externalHelper() {} } }
@objc class LocalObjCModel: NSObject {}
extension LocalObjCModel { func localObjCHelper() {} }
@objcMembers class RuntimeOwner { struct RuntimeNested { var value: Int { 0 } } }
func compilerDynamicallyDispatched() {}
@IBOutlet var outlet: AnyObject?
class RuntimeOverride { override func run() {} }
class LocalSwiftSubclass: RuntimeOwner {}
