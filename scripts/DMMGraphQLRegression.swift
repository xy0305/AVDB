import Foundation

@main struct DMMGraphQLRegression {
    static func main() throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1])
        func read(_ name: String) throws -> Data { try Data(contentsOf: base.appendingPathComponent(name)) }
        func fails(_ expected: DMMRankingError, _ action: () throws -> Void) {
            do { try action(); preconditionFailure("Expected rejection") }
            catch { precondition(error as? DMMRankingError == expected, "got \(error)") }
        }

        for (file, kind) in [
            ("graphql-daily-neutral.json", DMMRankingKind.daily),
            ("graphql-weekly-neutral.json", .weekly),
            ("graphql-monthly-neutral.json", .monthly)
        ] {
            let board = try DMMRankingGraphQL.board(data: try read(file), kind: kind, observedAt: Date(timeIntervalSince1970: 0))
            precondition(board.kind == kind)
            precondition(board.contentRows.count == kind.expectedCount)
            precondition(board.contentRows.map(\.rank) == Array(1...kind.expectedCount))
            precondition(board.contentRows.first?.cid == "neutral00001")
            precondition(board.actressRows.isEmpty)
        }

        let actress = try DMMRankingGraphQL.board(data: try read("graphql-actress-monthly-neutral.json"), kind: .actress, observedAt: Date(timeIntervalSince1970: 0))
        precondition(actress.actressRows.count == 100)
        precondition(actress.actressRows.first?.actressID == "900001")
        precondition(actress.actressRows.first?.name == "Neutral Actress 1")

        fails(.incomplete) {
            _ = try DMMRankingGraphQL.board(data: try read("graphql-daily-incomplete.json"), kind: .daily, observedAt: Date())
        }
        fails(.accessGate) {
            _ = try DMMRankingGraphQL.board(data: try read("graphql-blocked.json"), kind: .weekly, observedAt: Date())
        }

        // Payload shape for verified operations only.
        let weeklyPayload = try JSONSerialization.jsonObject(with: try DMMRankingGraphQL.payload(for: .weekly)) as! [String: Any]
        precondition(weeklyPayload["operationName"] as? String == "AVDBContentRanking")
        let actressPayload = try JSONSerialization.jsonObject(with: try DMMRankingGraphQL.payload(for: .actress)) as! [String: Any]
        precondition(actressPayload["operationName"] as? String == "AVDBActressRanking")
        precondition(DMMRankingGraphQL.endpoint.host == "api.video.dmm.co.jp")

        print("PASS: GraphQL neutral parse daily20/weekly100/monthly100/actress100, incomplete+blocked fail-closed, verified payload shapes")
    }
}
