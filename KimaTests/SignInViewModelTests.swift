import XCTest
@testable import Kima

/// The password sign-in path end to end at its own seam: a stubbed /api/auth/login response
/// lands as a stored login (via the shared ritual) and a persisted server address.
@MainActor
final class SignInViewModelTests: KeychainLoginTestCase {
    private let server = KimaServer(baseURL: URL(string: "https://signin.example:3030")!)

    private func makeVM() -> SignInViewModel {
        let vm = SignInViewModel(server: server)
        vm.makeClient = { at, _ in KimaAPIClient(server: at, sessions: StubSessionFactory()) }
        return vm
    }

    func testPasswordSignInStoresTheLoginAndAddress() async {
        StubURLProtocol.handler = { _ in
            (200, Data(#"{"token":"jwt-1","refreshToken":"refresh-1"}"#.utf8))
        }
        let vm = makeVM()
        vm.username = "user"
        vm.password = "secret"
        await vm.submit()

        XCTAssertEqual(vm.phase, .success)
        XCTAssertEqual(KeychainStore.credential(KeychainStore.accessToken, for: server), "jwt-1")
        XCTAssertEqual(KeychainStore.credential(KeychainStore.refreshToken, for: server), "refresh-1")
        XCTAssertEqual(ServerURLStore.stored, "https://signin.example:3030")
    }

    func testWrongPasswordStoresNothing() async {
        StubURLProtocol.handler = { _ in (401, Data(#"{"error":"Invalid credentials"}"#.utf8)) }
        let vm = makeVM()
        vm.username = "user"
        vm.password = "wrong"
        await vm.submit()

        if case .failed = vm.phase {} else { XCTFail("expected .failed, got \(vm.phase)") }
        XCTAssertNil(KeychainStore.storedCredential(KeychainStore.accessToken))
        XCTAssertNil(ServerURLStore.stored)
    }
}
