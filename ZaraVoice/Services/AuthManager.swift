import Foundation
import AuthenticationServices

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isAuthenticated = false
    @Published var userEmail: String?
    @Published var authToken: String?
    @Published var isLoading = false
    @Published var error: String?
    
    private let baseURL = "https://agent-flow.net"
    private let tokenKey = "auth_token"
    private let emailKey = "user_email"
    
    private init() {
        // Load saved credentials
        loadSavedCredentials()
    }
    
    private func loadSavedCredentials() {
        if let token = UserDefaults.standard.string(forKey: tokenKey),
           let email = UserDefaults.standard.string(forKey: emailKey) {
            self.authToken = token
            self.userEmail = email
            self.isAuthenticated = true
        }
    }
    
    private func saveCredentials(token: String, email: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        UserDefaults.standard.set(email, forKey: emailKey)
        self.authToken = token
        self.userEmail = email
        self.isAuthenticated = true
    }
    
    func signOut() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: emailKey)
        self.authToken = nil
        self.userEmail = nil
        self.isAuthenticated = false
    }
    
    // Sign in with Apple for simplicity (native iOS support, no SDK needed)
    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async {
        isLoading = true
        error = nil
        
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            error = "Failed to get identity token"
            isLoading = false
            return
        }
        
        // Exchange Apple token with our backend
        do {
            let response = try await exchangeAppleToken(idToken: tokenString, email: credential.email)
            saveCredentials(token: response.token, email: response.email)
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // Exchange Google ID token (if using Google Sign-In SDK)
    func signInWithGoogle(idToken: String) async {
        isLoading = true
        error = nil
        
        do {
            let response = try await exchangeGoogleToken(idToken: idToken)
            saveCredentials(token: response.token, email: response.email)
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func exchangeGoogleToken(idToken: String) async throws -> AuthResponse {
        let url = URL(string: "\(baseURL)/auth/mobile/google")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["id_token": idToken]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.unauthorized
        }
        
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }
    
    private func exchangeAppleToken(idToken: String, email: String?) async throws -> AuthResponse {
        let url = URL(string: "\(baseURL)/auth/mobile/apple")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: String] = ["id_token": idToken]
        if let email = email {
            body["email"] = email
        }
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.unauthorized
        }
        
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }
}

struct AuthResponse: Codable {
    let token: String
    let email: String
}

enum AuthError: Error {
    case unauthorized
    case networkError
}
