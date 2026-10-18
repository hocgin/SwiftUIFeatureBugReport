//
//  CloudKitPaging.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import Foundation

/// Reads every page of a query, for the callers that must not act on a truncated result.
///
/// A single `records(matching:)` call returns one batch and a cursor. Following the cursor is the
/// caller's job, and forgetting it fails quietly: followers go un-notified, an author's remaining
/// requests stay visible.
enum CloudKitPaging {

    struct Result {

        var records: [CKRecord] = []
        /// Set when the load stopped early. `records` still holds everything fetched before that.
        var failure: FeedbackError?
    }

    static func fetchAll(_ query: CKQuery,
                         desiredKeys: [CKRecord.FieldKey]? = nil,
                         in database: CKDatabase) async -> Result {

        var result = Result()
        var cursor: CKQueryOperation.Cursor?
        var pages = 0

        repeat {

            guard pages < CloudKitErrorHandler.maxQueryPages else {

                result.failure = CloudKitErrorHandler.incompleteLoad
                break
            }

            pages += 1

            do {

                let page: (matchResults: [(CKRecord.ID, Swift.Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?)

                if let cursor {

                    page = try await database.records(continuingMatchFrom: cursor, desiredKeys: desiredKeys)
                }
                else {

                    page = try await database.records(matching: query, desiredKeys: desiredKeys)
                }

                if let failure = CloudKitErrorHandler.firstMatchFailure(in: page.matchResults) {

                    result.failure = failure
                }

                result.records += page.matchResults.compactMap { try? $0.1.get() }
                cursor = page.queryCursor
            }
            catch {

                if !CloudKitErrorHandler.isRecordMissing(error) {

                    result.failure = CloudKitErrorHandler.classifyQuery(error)
                }

                break
            }
        }
        while cursor != nil

        return result
    }
}
