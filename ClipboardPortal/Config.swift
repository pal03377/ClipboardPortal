import Foundation

// Configure these values by editing ConfigDevelopment.xcconfig and ConfigProduction.xcconfig
let serverUrl   = URL(string: Bundle.main.object(forInfoDictionaryKey: "ServerURL") as! String)!
let wsServerUrl = URL(string: Bundle.main.object(forInfoDictionaryKey: "WebsocketServerURL") as! String)!

let textPrefix = "text: " // Prefix in file contents to detect sending text
