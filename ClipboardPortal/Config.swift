import Foundation

// Configure these values by editing ConfigDevelopment.xcconfig and ConfigProduction.xcconfig
let serverUrl = URL(string: Bundle.main.object(forInfoDictionaryKey: "ServerURL") as! String)!