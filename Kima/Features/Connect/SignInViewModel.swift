import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Connect to an EXISTING account, two ways:
///  • password sign-in (POST /api/auth/login, with 2FA via APIError.requires2FA), or
///  • device-link pairing code (POST /api/device-link/verify → permanent API key).
/// On success the credential is stored in the Keychain and the server URL persisted.
@MainActor
@Observable
final class SignInViewModel {
    enum Method: String, CaseIterable { case password = "password", pairing = "pairing code" }
    enum Phase: Equatable { case idle, working, failed(String), success }

    let server: KimaServer
    var method: Method = .password

    // Password path
    var username = ""
    var password = ""
    var needs2FA = false
    var twoFactorCode = ""

    // Device-link path
    var pairingCode = ""

    var phase: Phase = .idle

    init(server: KimaServer) { self.server = server }

    var canSubmit: Bool {
        guard phase != .working else { return false }
        switch method {
        case .password:
            return !username.isEmpty && !password.isEmpty && (!needs2FA || !twoFactorCode.isEmpty)
        case .pairing:
            let cleaned = pairingCode.trimmingCharacters(in: .whitespaces).uppercased()
            let validCharset = CharacterSet(charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
            return cleaned.count == 6 && cleaned.unicodeScalars.allSatisfy(validCharset.contains)
        }
    }

    func submit() async {
        switch method {
        case .password: await signInWithPassword()
        case .pairing:  await pairWithCode()
        }
    }

    private func signInWithPassword() async {
        guard phase != .working else { return }
        phase = .working
        let client = KimaAPIClient(server: server)
        do {
            let response = try await client.login(
                username: username,
                password: password,
                token: needs2FA ? twoFactorCode : nil
            )
            guard let accessToken = response.token else {
                // Server returned HTTP 200 but no token — bad 2FA code or broken server response.
                if response.requires2FA == true {
                    let wasAlready2FA = needs2FA
                    needs2FA = true
                    twoFactorCode = ""
                    phase = wasAlready2FA
                        ? .failed("wrong code. try again.")
                        : .idle
                } else {
                    phase = .failed("sign-in failed: the server returned an unexpected response.")
                }
                return
            }
            guard KeychainStore.setCredential(accessToken, for: KeychainStore.accessToken, server: server) else {
                phase = .failed("couldn't securely save your sign-in. please try again.")
                return
            }
            KeychainStore.setCredential(response.refreshToken, for: KeychainStore.refreshToken, server: server)  // best-effort
            // Drop any other stored login, e.g. another server's API key, which would otherwise
            // win over this token and be sent to this server.
            KeychainStore.clearCredentials(except: [KeychainStore.accessToken, KeychainStore.refreshToken])
            persistServerURL()
            phase = .success
        } catch APIError.requires2FA {
            needs2FA = true
            phase = .idle                 // prompt for the code, then resubmit
        } catch APIError.unauthorized {
            phase = .failed("wrong username or password.")
        } catch let error as APIError {
            phase = .failed(error.errorDescription ?? "sign-in failed.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func pairWithCode() async {
        guard phase != .working else { return }
        phase = .working
        let client = KimaAPIClient(server: server)
        let code = pairingCode.trimmingCharacters(in: .whitespaces).uppercased()
        let validCharset = CharacterSet(charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        guard code.count == 6, code.unicodeScalars.allSatisfy(validCharset.contains) else {
            phase = .failed("enter a valid 6-character pairing code.")
            return
        }
        do {
            let response = try await client.deviceLinkVerify(code: code, deviceName: Self.deviceName)
            guard response.success, let apiKey = response.apiKey else {
                phase = .failed("that code didn't work. get a new one and try again.")
                return
            }
            guard KeychainStore.setCredential(apiKey, for: KeychainStore.apiKey, server: server) else {
                phase = .failed("couldn't securely save your device link. please try again.")
                return
            }
            KeychainStore.clearCredentials(except: [KeychainStore.apiKey])   // drops any other server's tokens
            persistServerURL()
            phase = .success
        } catch let error as APIError {
            phase = .failed(error.errorDescription ?? "pairing failed.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func persistServerURL() {
        ServerURLStore.setStored(server.baseURL.absoluteString)
    }

    private static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "iPhone"
        #endif
    }
}
