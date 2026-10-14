"""Run the production route VM with controlled transport on macOS, never a copied mock VM."""
from pathlib import Path
import shutil, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
vm = (root/'AVDB/Services/MovieListViewModel.swift').read_text()
vm = vm[vm.index('struct CatalogQuery:'):]
view = (root/'AVDB/Views/Categories/CategoriesView.swift').read_text()
view = view[view.index('struct CatalogListView:'):]
assert '.task(id: query)' in view and 'await reload()' not in view
assert '@StateObject private var vm: CatalogListViewModel' in view
assert '.scrollPosition(id: $vm.scrollID)' in view
assert '.refreshable { await vm.refresh() }' in view
sdk = (root/'AVDB/Services/JavDBSDK.swift').read_text()
latest = sdk[sdk.index('    public func latestMovies('):sdk.index('    /// TOP250')]
assert 'guard resp.isSuccess' in latest and 'guard let decoded' in latest
api = (root/'AVDB/Networking/APIClient.swift').read_text()
assert 'config.timeoutIntervalForResource = 60' in api
assert 'avdbCatalogAccountChanged' in api
source = 'import Foundation\nimport Combine\nstruct Movie { let id: String }\n' + vm + '\n' + (root/'scripts/CatalogLifecycleRegression.swift').read_text()
if shutil.which('swiftc'):
    with tempfile.TemporaryDirectory() as tmp:
        p = Path(tmp)/'catalog.swift'; p.write_text(source)
        subprocess.run(['swiftc', '-parse-as-library', str(p), '-o', tmp+'/catalog'], check=True)
        subprocess.run([tmp+'/catalog'], check=True, timeout=45)
else:
    print('Swift unavailable: executable production VM tests deferred to macOS CI (not claimed locally)')
print('PASS catalog view ownership/query/scroll/error/timeout contracts')
