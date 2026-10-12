#!/usr/bin/env python3
"""Compile shipping startup/token methods against isolated stores and a mocked SDK."""
from pathlib import Path
import shutil, subprocess, tempfile

def declaration(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

root = Path(__file__).resolve().parents[1]
app = (root / 'AVDB/AVDBApp.swift').read_text()
client = (root / 'AVDB/Networking/APIClient.swift').read_text()
shipping_app = app[app.index('@MainActor\nfinal class AppState'):]
methods = '\n'.join(declaration(client, marker) for marker in [
    'public func setToken(', 'public var hasToken:'])
error = declaration(client, 'public enum JavDBError:')
source = '''import Foundation
import Combine
struct User { let id: Int }
''' + error + '''
final class APIClient: @unchecked Sendable {
    static let shared = APIClient()
    static let tokenKey = "avdb.javdb.token"
    static let store = UserDefaults(suiteName: "avdb.auth.regression." + UUID().uuidString)!
    var token: String?
    let tokenLock = NSLock()
    init() { token = Self.store.string(forKey: Self.tokenKey) }
''' + methods.replace('UserDefaults.standard', 'Self.store') + '''
}
@MainActor final class JavDBSDK {
    static let shared = JavDBSDK()
    var outcome: Result<(User, Int), Error> = .success((User(id: 1), 0))
    var beforeReturn: (() -> Void)?
    var logoutCalls = 0
    func userInfo() async throws -> (User, Int) {
        await Task.yield()
        beforeReturn?()
        return try outcome.get()
    }
    func logout() { logoutCalls += 1; APIClient.shared.setToken(nil) }
}
''' + shipping_app + '''
@main struct Regression {
    @MainActor static func main() async {
        let client = APIClient.shared, sdk = JavDBSDK.shared
        let fixture = "synthetic-test-credential"
        client.setToken(fixture)
        assert(APIClient().token == fixture, "shipping setToken survives client recreation")
        for error: Error in [URLError(.notConnectedToInternet), URLError(.timedOut), CancellationError(), JavDBError.decodeError("mock"), JavDBError.invalidSignature, JavDBError.httpError(403, "mock"), JavDBError.httpError(500, "mock")] {
            sdk.outcome = .failure(error)
            let state = AppState()
            await state.restoreTask?.value
            assert(state.isLoggedIn)
            assert(client.token == fixture && APIClient().token == fixture)
        }
        sdk.outcome = .failure(JavDBError.httpError(401, "mock"))
        let unauthorized = AppState()
        await unauthorized.restoreTask?.value
        assert(!unauthorized.isLoggedIn && APIClient().token == fixture)
        sdk.outcome = .success((User(id: 7), 0))
        let relaunched = AppState()
        await relaunched.restoreTask?.value
        assert(relaunched.isLoggedIn && relaunched.currentUser?.id == 7)
        sdk.beforeReturn = { client.setToken(nil) }
        let loggedOut = AppState()
        loggedOut.isLoggedIn = false
        await loggedOut.restoreTask?.value
        assert(!loggedOut.isLoggedIn && loggedOut.currentUser == nil)
        client.setToken(fixture)
        sdk.beforeReturn = { client.setToken("synthetic-replacement") }
        let changedAccount = AppState()
        await changedAccount.restoreTask?.value
        assert(changedAccount.currentUser == nil)
        assert(APIClient().token == "synthetic-replacement")
        assert(sdk.logoutCalls == 0, "startup never clears persisted credentials")
        // Only remove synthetic test data in this UUID-named suite.
        client.setToken(nil)
        print("PASS: shipping auth restore, relaunch, transient/401/403 errors and account races")
    }
}
'''
if not shutil.which('swiftc'):
    print('SKIP runtime: swiftc unavailable; CI macOS must run production auth replay')
else:
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory)
        (path / 'Auth.swift').write_text(source)
        subprocess.run(['swiftc', '-parse-as-library', str(path / 'Auth.swift'), '-o', str(path / 'auth')], check=True)
        subprocess.run([str(path / 'auth')], check=True)
