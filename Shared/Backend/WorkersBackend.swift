import Foundation

func getAPIKey() -> String? {
    let apiKey = Bundle.main.infoDictionary?["BACKEND_API_KEY"] as? String
    
    return apiKey
}
