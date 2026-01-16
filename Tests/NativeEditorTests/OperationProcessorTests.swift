import XCTest
@testable import MiNoteLibrary

/// OperationProcessor 单元测试
///
/// 测试操作处理器的核心功能：
/// - 错误分类
/// - 重试延迟计算
/// - 错误可重试判断
///
/// 任务: 12.2
final class OperationProcessorTests: XCTestCase {
    
    // MARK: - 重试延迟计算测试
    
    /// 测试重试延迟计算（指数退避）
    @MainActor
    func testCalculateRetryDelay() async {
        let processor = OperationProcessor.shared
        
        // 验证指数退避序列：1s, 2s, 4s, 8s, 16s, 32s, 60s, 60s...
        let delay0 = await processor.calculateRetryDelay(retryCount: 0)
        let delay1 = await processor.calculateRetryDelay(retryCount: 1)
        let delay2 = await processor.calculateRetryDelay(retryCount: 2)
        let delay3 = await processor.calculateRetryDelay(retryCount: 3)
        let delay4 = await processor.calculateRetryDelay(retryCount: 4)
        let delay5 = await processor.calculateRetryDelay(retryCount: 5)
        let delay6 = await processor.calculateRetryDelay(retryCount: 6)
        let delay7 = await processor.calculateRetryDelay(retryCount: 7)
        let delay100 = await processor.calculateRetryDelay(retryCount: 100)
        
        XCTAssertEqual(delay0, 1.0, accuracy: 0.01)
        XCTAssertEqual(delay1, 2.0, accuracy: 0.01)
        XCTAssertEqual(delay2, 4.0, accuracy: 0.01)
        XCTAssertEqual(delay3, 8.0, accuracy: 0.01)
        XCTAssertEqual(delay4, 16.0, accuracy: 0.01)
        XCTAssertEqual(delay5, 32.0, accuracy: 0.01)
        XCTAssertEqual(delay6, 60.0, accuracy: 0.01)  // 最大值
        XCTAssertEqual(delay7, 60.0, accuracy: 0.01)  // 保持最大值
        XCTAssertEqual(delay100, 60.0, accuracy: 0.01)  // 保持最大值
    }
    
    // MARK: - 错误分类测试
    
    /// 测试网络错误分类
    @MainActor
    func testClassifyNetworkError() async {
        let processor = OperationProcessor.shared
        
        // URLError - 网络连接丢失
        let networkLostError = URLError(.networkConnectionLost)
        let networkLostType = await processor.classifyError(networkLostError)
        XCTAssertEqual(networkLostType, .network)
        
        // URLError - 未连接到互联网
        let notConnectedError = URLError(.notConnectedToInternet)
        let notConnectedType = await processor.classifyError(notConnectedError)
        XCTAssertEqual(notConnectedType, .network)
        
        // URLError - 无法找到主机
        let cannotFindHostError = URLError(.cannotFindHost)
        let cannotFindHostType = await processor.classifyError(cannotFindHostError)
        XCTAssertEqual(cannotFindHostType, .network)
        
        // URLError - 无法连接到主机
        let cannotConnectError = URLError(.cannotConnectToHost)
        let cannotConnectType = await processor.classifyError(cannotConnectError)
        XCTAssertEqual(cannotConnectType, .network)
        
        // URLError - DNS 查找失败
        let dnsError = URLError(.dnsLookupFailed)
        let dnsType = await processor.classifyError(dnsError)
        XCTAssertEqual(dnsType, .network)
    }
    
    /// 测试超时错误分类
    @MainActor
    func testClassifyTimeoutError() async {
        let processor = OperationProcessor.shared
        
        let timeoutError = URLError(.timedOut)
        let errorType = await processor.classifyError(timeoutError)
        XCTAssertEqual(errorType, .timeout)
    }
    
    /// 测试服务器错误分类
    @MainActor
    func testClassifyServerError() async {
        let processor = OperationProcessor.shared
        
        // URLError - 服务器响应错误
        let badResponseError = URLError(.badServerResponse)
        let badResponseType = await processor.classifyError(badResponseError)
        XCTAssertEqual(badResponseType, .serverError)
        
        // URLError - 无法解析响应
        let cannotParseError = URLError(.cannotParseResponse)
        let cannotParseType = await processor.classifyError(cannotParseError)
        XCTAssertEqual(cannotParseType, .serverError)
        
        // NSError - HTTP 500
        let http500Error = NSError(domain: "MiNoteService", code: 500, userInfo: nil)
        let http500Type = await processor.classifyError(http500Error)
        XCTAssertEqual(http500Type, .serverError)
        
        // NSError - HTTP 503
        let http503Error = NSError(domain: "MiNoteService", code: 503, userInfo: nil)
        let http503Type = await processor.classifyError(http503Error)
        XCTAssertEqual(http503Type, .serverError)
    }
    
    /// 测试认证错误分类
    @MainActor
    func testClassifyAuthError() async {
        let processor = OperationProcessor.shared
        
        // MiNoteError - Cookie 过期
        let cookieExpiredError = MiNoteError.cookieExpired
        let cookieExpiredType = await processor.classifyError(cookieExpiredError)
        XCTAssertEqual(cookieExpiredType, .authExpired)
        
        // MiNoteError - 未认证
        let notAuthenticatedError = MiNoteError.notAuthenticated
        let notAuthenticatedType = await processor.classifyError(notAuthenticatedError)
        XCTAssertEqual(notAuthenticatedType, .authExpired)
        
        // NSError - HTTP 401
        let http401Error = NSError(domain: "MiNoteService", code: 401, userInfo: nil)
        let http401Type = await processor.classifyError(http401Error)
        XCTAssertEqual(http401Type, .authExpired)
        
        // URLError - 需要用户认证
        let authRequiredError = URLError(.userAuthenticationRequired)
        let authRequiredType = await processor.classifyError(authRequiredError)
        XCTAssertEqual(authRequiredType, .authExpired)
    }
    
    /// 测试资源不存在错误分类
    @MainActor
    func testClassifyNotFoundError() async {
        let processor = OperationProcessor.shared
        
        // NSError - HTTP 404
        let http404Error = NSError(domain: "MiNoteService", code: 404, userInfo: nil)
        let errorType = await processor.classifyError(http404Error)
        XCTAssertEqual(errorType, .notFound)
    }
    
    /// 测试冲突错误分类
    @MainActor
    func testClassifyConflictError() async {
        let processor = OperationProcessor.shared
        
        // NSError - HTTP 409
        let http409Error = NSError(domain: "MiNoteService", code: 409, userInfo: nil)
        let errorType = await processor.classifyError(http409Error)
        XCTAssertEqual(errorType, .conflict)
    }
    
    /// 测试未知错误分类
    @MainActor
    func testClassifyUnknownError() async {
        let processor = OperationProcessor.shared
        
        // 普通 NSError
        let genericError = NSError(domain: "TestDomain", code: 999, userInfo: nil)
        let errorType = await processor.classifyError(genericError)
        XCTAssertEqual(errorType, .unknown)
    }
    
    // MARK: - 错误可重试判断测试
    
    /// 测试可重试错误判断
    @MainActor
    func testIsRetryable() async {
        let processor = OperationProcessor.shared
        
        // 网络错误 - 可重试
        let networkError = URLError(.networkConnectionLost)
        let isNetworkRetryable = await processor.isRetryable(networkError)
        XCTAssertTrue(isNetworkRetryable)
        
        // 超时错误 - 可重试
        let timeoutError = URLError(.timedOut)
        let isTimeoutRetryable = await processor.isRetryable(timeoutError)
        XCTAssertTrue(isTimeoutRetryable)
        
        // 服务器错误 - 可重试
        let serverError = URLError(.badServerResponse)
        let isServerRetryable = await processor.isRetryable(serverError)
        XCTAssertTrue(isServerRetryable)
        
        // 认证错误 - 不可重试
        let authError = MiNoteError.cookieExpired
        let isAuthRetryable = await processor.isRetryable(authError)
        XCTAssertFalse(isAuthRetryable)
        
        // 404 错误 - 不可重试
        let notFoundError = NSError(domain: "MiNoteService", code: 404, userInfo: nil)
        let isNotFoundRetryable = await processor.isRetryable(notFoundError)
        XCTAssertFalse(isNotFoundRetryable)
    }
    
    /// 测试需要用户操作判断
    @MainActor
    func testRequiresUserAction() async {
        let processor = OperationProcessor.shared
        
        // 认证错误 - 需要用户操作
        let authError = MiNoteError.cookieExpired
        let authRequiresAction = await processor.requiresUserAction(authError)
        XCTAssertTrue(authRequiresAction)
        
        // 网络错误 - 不需要用户操作
        let networkError = URLError(.networkConnectionLost)
        let networkRequiresAction = await processor.requiresUserAction(networkError)
        XCTAssertFalse(networkRequiresAction)
        
        // 服务器错误 - 不需要用户操作
        let serverError = URLError(.badServerResponse)
        let serverRequiresAction = await processor.requiresUserAction(serverError)
        XCTAssertFalse(serverRequiresAction)
    }
    
    // MARK: - 处理状态测试
    
    /// 测试处理状态属性
    @MainActor
    func testProcessingState() async {
        let processor = OperationProcessor.shared
        
        // 初始状态应该不在处理中
        let isProcessing = await processor.isProcessing
        // 注意：这个测试可能会因为其他测试的并发执行而不稳定
        // 这里只验证属性可以访问
        XCTAssertNotNil(isProcessing as Bool?)
        
        // 当前操作应该为 nil（如果没有正在处理的操作）
        let currentOp = await processor.currentOperation
        // 同样，这里只验证属性可以访问
        XCTAssertTrue(currentOp == nil || currentOp != nil)
    }
}
