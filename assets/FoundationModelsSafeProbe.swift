// FoundationModelsSafeProbe.swift — compile/link probe that does not touch
// the model during application launch. LiveContainer may run without the
// Apple Intelligence subsystem or entitlement; the app must still open.
import Foundation
import FoundationModels

@available(iOS 26.0, *)
public enum SafeFoundationModels {
    public static var availability: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "available"
        case .unavailable(let reason):
            return "unavailable:\(reason)"
        @unknown default:
            return "unavailable:unknown"
        }
    }
}
