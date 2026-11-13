import XCTest
@testable import Kima

/// The account-creation path end to end at its own seam. Named behavior change (ticket 11):
/// a created account now stores the refresh token like every other sign-in path, so it gets
/// silent re-login from its first launch. Servers that don't send one yet still establish.
@MainActor
final class CreateAccountViewModelTests: KeychainLoginTestCase {
    private let server = KimaServer(baseURL: URL(string: "https://create.example:3030")!)

    private func makeVM() -> CreateAccountViewModel {
        let vm = CreateAccountViewModel(server: server)
        vm.makeClient = { at, credential in
            KimaAPIClient(server: at, credential: credential, sessions: StubSessionFactory())
        }
        return vm
    }

    private func fill(_ vm: CreateAccountViewModel) {
        vm.username = "admin"
        vm.password = "secret"
        vm.confirmPassword = "secret"
    }

    func testAccountCreationStoresTheRefreshToken() async {
        StubURLProtocol.handler = { _ in
            (200, Data(#"{"token":"jwt-2","refreshToken":"refresh-2"}"#.utf8))
        }
        let vm = makeVM()
        fill(vm)
        await vm.submit()

        XCTAssertEqual(vm.phase, .registered)
        XCTAssertEqual(KeychainStore.credential(KeychainStore.accessToken, for: server), "jwt-2")
        XCTAssertEqual(KeychainStore.credential(KeychainStore.refreshToken, for: server), "refresh-2")
        XCTAssertEqual(ServerURLStore.stored, "https://create.example:3030")
    }

    func testServerWithoutRefreshTokenStillEstablishes() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"token":"jwt-3"}"#.utf8)) }
        let vm = makeVM()
        fill(vm)
        await vm.submit()

        XCTAssertEqual(vm.phase, .registered)
        XCTAssertEqual(KeychainStore.credential(KeychainStore.accessToken, for: server), "jwt-3")
        XCTAssertNil(KeychainStore.storedCredential(KeychainStore.refreshToken))
        XCTAssertEqual(ServerURLStore.stored, "https://create.example:3030")
    }
}
