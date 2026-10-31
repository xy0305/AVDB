import Foundation
enum LiveEngineError: LocalizedError { case modelMissing(String), notReady, unavailable(String) }
