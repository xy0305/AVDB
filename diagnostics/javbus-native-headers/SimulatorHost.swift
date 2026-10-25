import UIKit

@main final class ProbeApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey:Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UIViewController(); window?.makeKeyAndVisible()
        Task {
            do {
                let result = await NativeProbe.run()
                let data = try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
                let folder = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
                try data.write(to:folder.appendingPathComponent("ios-simulator.json"),options:.atomic)
            } catch {
                let folder = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
                try? Data("probe serialization failure".utf8).write(to:folder.appendingPathComponent("failed.txt"))
            }
        }
        return true
    }
}
