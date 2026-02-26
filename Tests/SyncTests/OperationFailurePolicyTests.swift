//
//  OperationFailurePolicyTests.swift
//  MiNoteLibraryTests
//
//  OperationFailurePolicy 单元测试
//  验证错误分类、重试决策、延迟计算
//

import XCTest
@testable import MiNoteMac

final class OperationFailurePolicyTests: XCTestCase {

    private var policy: OperationFailurePolicy!

    override func setUp() {
        super.setUp()
        policy = OperationFailurePolicy(config: OperationQueueConfig(
            maxRetryCount: 3,
            baseRetryDelay: 1.0,
            maxRetryDelay: 60.0
        ))
    }

    // MARK: - 错误分类测试

    func testClassifyURLErrorTimeout() {
        let error = URLError(.timedOut)
        XCTAssertEqual(policy.classifyError(error), .timeout)
    }

    func testClassifyURLErrorNotConnected() {
        let error = URLError(.notConnectedToInternet)
        XCTAssertEqual(policy.classifyError(error), .network)
    }

    func testClassifyURLErrorConnectionLost() {
        let error = URLError(.networkConnectionLost)
        XCTAssertEqual(policy.classifyError(error), .network)
    }

    func testClassifyURLErrorBadServerResponse() {
        let error = URLError(.badServerResponse)
        XCTAssertEqual(policy.classifyError(error), .serverError)
    }

    func testClassifyMiNoteErrorCookieExpired() {
        let error = MiNoteError.cookieExpired
        XCTAssertEqual(policy.classifyError(error), .authExpired)
    }

    func testClassifyMiNoteErrorNotAuthenticated() {
        let error = MiNoteError.notAuthenticated
        XCTAssertEqual(policy.classifyError(error), .authExpired)
    }

    func testClassifyMiNoteErrorInvalidResponse() {
        let error = MiNoteError.invalidResponse
        XCTAssertEqual(policy.classifyError(error), .serverError)
    }

    func testClassifyMiNoteErrorNetworkError() {
        let urlError = URLError(.timedOut)
        let error = MiNoteError.networkError(urlError)
        XCTAssertEqual(policy.classifyError(error), .timeout)
    }

    func testClassifyNSError404() {
        let error = NSError(domain: "NoteAPI", code: 404)
        XCTAssertEqual(policy.classifyError(error), .notFound)
    }

    func testClassifyNSError401() {
        let error = NSError(domain: "NoteAPI", code: 401)
        XCTAssertEqual(policy.classifyError(error), .authExpired)
    }

    func testClassifyNSError409() {
        let error = NSError(domain: "FolderAPI", code: 409)
        XCTAssertEqual(policy.classifyError(error), .conflict)
    }

    func testClassifyNSError500() {
        let error = NSError(domain: "FileAPI", code: 500)
        XCTAssertEqual(policy.classifyError(error), .serverError)
    }

    func testClassifyUnknownError() {
        struct CustomError: Error {}
        let error = CustomError()
        XCTAssertEqual(policy.classifyError(error), .unknown)
    }

    // MARK: - isRetryable 测试

    func testNetworkErrorIsRetryable() {
        let error = URLError(.notConnectedToInternet)
        XCTAssertTrue(policy.isRetryable(error))
    }

    func testTimeoutIsRetryable() {
        let error = URLError(.timedOut)
        XCTAssertTrue(policy.isRetryable(error))
    }

    func testServerErrorIsRetryable() {
        let error = URLError(.badServerResponse)
        XCTAssertTrue(policy.isRetryable(error))
    }

    func testAuthExpiredNotRetryable() {
        let error = MiNoteError.cookieExpired
        XCTAssertFalse(policy.isRetryable(error))
    }

    func testNotFoundNotRetryable() {
        let error = NSError(domain: "NoteAPI", code: 404)
        XCTAssertFalse(policy.isRetryable(error))
    }

    func testConflictNotRetryable() {
        let error = NSError(domain: "NoteAPI", code: 409)
        XCTAssertFalse(policy.isRetryable(error))
    }

    // MARK: - 重试决策测试

    func testDecideNetworkError_retry() {
        let error = URLError(.notConnectedToInternet)
        let decision = policy.decide(error: error, retryCount: 0)

        if case let .retry(delay) = decision {
            XCTAssertGreaterThan(delay, 0)
        } else {
            XCTFail("网络错误首次应返回 retry")
        }
    }

    func testDecideNotFoundError_abandon() {
        let error = NSError(domain: "NoteAPI", code: 404)
        let decision = policy.decide(error: error, retryCount: 0)

        if case let .abandon(reason) = decision {
            XCTAssertTrue(reason.contains("不可重试"))
        } else {
            XCTFail("404 错误应返回 abandon")
        }
    }

    func testDecideAuthExpired_abandon() {
        let error = MiNoteError.cookieExpired
        let decision = policy.decide(error: error, retryCount: 0)

        if case let .abandon(reason) = decision {
            XCTAssertTrue(reason.contains("不可重试"))
        } else {
            XCTFail("认证过期应返回 abandon")
        }
    }

    func testDecideMaxRetryExceeded_abandon() {
        let error = URLError(.timedOut)
        let decision = policy.decide(error: error, retryCount: 3)

        if case let .abandon(reason) = decision {
            XCTAssertTrue(reason.contains("最大重试次数"))
        } else {
            XCTFail("超过最大重试次数应返回 abandon")
        }
    }

    func testDecideRetryCountBelowMax_retry() {
        let error = URLError(.timedOut)
        let decision = policy.decide(error: error, retryCount: 2)

        if case .retry = decision {
            // 通过
        } else {
            XCTFail("未超过最大重试次数的可重试错误应返回 retry")
        }
    }

    // MARK: - 延迟计算测试

    func testRetryDelayExponentialBackoff() {
        let delay0 = policy.calculateRetryDelay(retryCount: 0)
        let delay1 = policy.calculateRetryDelay(retryCount: 1)
        let delay2 = policy.calculateRetryDelay(retryCount: 2)

        // 指数退避：基础延迟 * 2^retryCount + jitter
        // retryCount=0: 1.0 * 1 = 1.0 + jitter(0~0.25)
        // retryCount=1: 1.0 * 2 = 2.0 + jitter(0~0.5)
        // retryCount=2: 1.0 * 4 = 4.0 + jitter(0~1.0)
        XCTAssertGreaterThanOrEqual(delay0, 1.0)
        XCTAssertLessThanOrEqual(delay0, 1.25)
        XCTAssertGreaterThanOrEqual(delay1, 2.0)
        XCTAssertLessThanOrEqual(delay1, 2.5)
        XCTAssertGreaterThanOrEqual(delay2, 4.0)
        XCTAssertLessThanOrEqual(delay2, 5.0)
    }

    func testRetryDelayCappedAtMax() {
        // retryCount=10: 1.0 * 1024 = 1024，应被 cap 到 60
        let delay = policy.calculateRetryDelay(retryCount: 10)
        XCTAssertLessThanOrEqual(delay, 75.0) // 60 + 25% jitter
    }
}
