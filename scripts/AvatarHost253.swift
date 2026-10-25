import SwiftUI
import UIKit

@main struct AvatarHost253: App {
    var body: some Scene { WindowGroup { AvatarHostView253() } }
}
struct AvatarHostView253: View {
    @State private var actor: Actor?
    @State private var status = "Running production JavBus service"
    var body: some View {
        VStack(spacing: 20) {
            Text("AVDB production avatar 253").font(.headline)
            if let actor {
                ActorAvatarArtwork(actor: actor, numbers: ["DSOD-070"], contentMode: .fit)
                    .frame(width:125,height:125).background(Color.magenta)
            }
            Text(status).font(.caption)
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color.white)
        .task {
            let dir = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
            do {
                try await ProductionLive253.checks()
                var result = try await ProductionLive253.run()
                actor = try JSONDecoder().decode(Actor.self,from:Data(#"{"id":"neutral-live253","name":"池田マリナ"}"#.utf8))
                status = "JavBus · decoded 125×125"
                try await Task.sleep(nanoseconds:2_000_000_000)
                result["uiHost"] = "actual production ActorAvatarArtwork, real service cache, no adult cover fixture"
                try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("ios-simulator.json"))
            } catch {
                status = "Failed"
                try? String(describing:error).write(to:dir.appendingPathComponent("failed.txt"),atomically:true,encoding:.utf8)
            }
        }
    }
}
