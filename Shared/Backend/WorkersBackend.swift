import Foundation

let BACKEND_URL = "https://backend.roam.msd3.io"

func getAPIKey() -> String? {
    let apiKey = Bundle.main.infoDictionary?["BACKEND_API_KEY"] as? String
    
    return apiKey
}

func uploadDebugLogs(logs: DebugInfo) async throws {
    let apiKey = getAPIKey() ?? "";
    
    
}
