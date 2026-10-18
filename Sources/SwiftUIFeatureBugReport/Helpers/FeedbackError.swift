//
//  FeedbackError.swift
//  SwiftUIFeatureBugReport
//

import Foundation

public enum FeedbackError: LocalizedError, Sendable {

    /// No iCloud account. Read-only, not a failure - see `FeedbackContainer.identityState`.
    case notSignedIn

    /// Identity has not resolved yet. Views should wait rather than render "not mine, not voted".
    case identityUnavailable

    case metadataTooLarge(bytes: Int, limit: Int)

    /// The misconfiguration case. Almost always a skipped setup step rather than a package bug.
    case developerRoleNotConfigured

    case rateLimited(retryAfter: TimeInterval)

    case networkUnavailable

    /// The record is gone - usually because a developer deleted it. Handled silently at call sites.
    case recordMissing

    /// The record *type* does not exist in this environment. Almost always a schema that was imported
    /// into Development but never deployed to Production.
    case schemaNotDeployed

    case imageEncodingFailed

    case underlying(String)

    public var errorDescription: String? {

        switch self {

        case .notSignedIn:
            return L10n.t("feedback.error.notSignedIn")

        case .identityUnavailable:
            return L10n.t("feedback.error.identityUnavailable")

        case .metadataTooLarge(let bytes, let limit):
            return L10n.t("feedback.error.metadataTooLarge \(bytes) \(limit)")

        case .developerRoleNotConfigured:
            return L10n.t("feedback.error.developerRole")

        case .rateLimited(let retryAfter):
            return L10n.t("feedback.error.rateLimited \(Int(retryAfter.rounded(.up)))")

        case .networkUnavailable:
            return L10n.t("feedback.error.network")

        case .recordMissing:
            return L10n.t("feedback.error.recordMissing")

        case .schemaNotDeployed:
            return L10n.t("feedback.error.schemaNotDeployed")

        case .imageEncodingFailed:
            return L10n.t("feedback.error.imageEncoding")

        case .underlying(let message):
            return message
        }
    }
}
