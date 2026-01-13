import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @StateObject private var authManager = AuthManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.18),
                    Color(red: 0.15, green: 0.1, blue: 0.25)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Logo/Title
                VStack(spacing: 16) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Zara Voice")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Your AI companion")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Error message
                if let error = authManager.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                // Sign in buttons
                VStack(spacing: 16) {
                    // Sign in with Apple (native, no SDK needed)
                    SignInWithAppleButton(
                        onRequest: { request in
                            request.requestedScopes = [.email]
                        },
                        onCompletion: { result in
                            switch result {
                            case .success(let authorization):
                                if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                    Task {
                                        await authManager.signInWithApple(credential: appleIDCredential)
                                    }
                                }
                            case .failure(let error):
                                authManager.error = error.localizedDescription
                            }
                        }
                    )
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .cornerRadius(8)
                    
                    // Google Sign-In button (styled, will use web flow)
                    Button(action: startGoogleSignIn) {
                        HStack {
                            Image(systemName: "g.circle.fill")
                                .font(.title2)
                            Text("Sign in with Google")
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(red: 0.26, green: 0.52, blue: 0.96))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 40)
                
                if authManager.isLoading {
                    ProgressView()
                        .tint(.white)
                }
                
                Spacer()
                
                // Footer
                Text("Secure authentication via OAuth")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .padding(.bottom)
            }
        }
    }
    
    private func startGoogleSignIn() {
        // Open Google OAuth in browser (ASWebAuthenticationSession)
        Task {
            await performGoogleWebAuth()
        }
    }
    
    @MainActor
    private func performGoogleWebAuth() async {
        let clientId = "446740474721-bn1j0m9g981o1hd0ul1c82mgk5m2as3c.apps.googleusercontent.com"
        let redirectUri = "com.googleusercontent.apps.446740474721-bn1j0m9g981o1hd0ul1c82mgk5m2as3c:/oauth2callback"
        let scope = "email profile"
        
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline")
        ]
        
        guard let url = components.url else { return }
        
        // Use ASWebAuthenticationSession for secure OAuth flow
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "com.googleusercontent.apps.446740474721-bn1j0m9g981o1hd0ul1c82mgk5m2as3c"
        ) { callbackURL, error in
            if let error = error {
                Task { @MainActor in
                    authManager.error = error.localizedDescription
                }
                return
            }
            
            guard let callbackURL = callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                return
            }
            
            // Exchange code for token with our backend
            Task {
                await exchangeGoogleCode(code: code)
            }
        }
        
        session.presentationContextProvider = WebAuthContextProvider.shared
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }
    
    @MainActor
    private func exchangeGoogleCode(code: String) async {
        authManager.isLoading = true
        
        do {
            let url = URL(string: "https://agent-flow.net/auth/mobile/google/callback")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body = ["code": code, "redirect_uri": "com.googleusercontent.apps.446740474721-bn1j0m9g981o1hd0ul1c82mgk5m2as3c:/oauth2callback"]
            request.httpBody = try JSONEncoder().encode(body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw AuthError.unauthorized
            }
            
            let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
            authManager.authToken = authResponse.token
            authManager.userEmail = authResponse.email
            authManager.isAuthenticated = true
            
            // Save to UserDefaults
            UserDefaults.standard.set(authResponse.token, forKey: "auth_token")
            UserDefaults.standard.set(authResponse.email, forKey: "user_email")
            
        } catch {
            authManager.error = error.localizedDescription
        }
        
        authManager.isLoading = false
    }
}

// Helper for ASWebAuthenticationSession
class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthContextProvider()
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

#Preview {
    LoginView()
}
