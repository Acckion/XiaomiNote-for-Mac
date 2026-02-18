//
//  AuthenticationViewModelTests.swift
//  MiNoteMac
//
//  Created on 2026-01-23.
//  AuthenticationViewModel 单元测试
//

import Combine
import XCTest
@testable import MiNoteLibrary

/// AuthenticationViewModel 单元测试
@MainActor
final class AuthenticationViewModelTests: XCTestCase {
    // MARK: - Properties

    var sut: AuthenticationViewModel!
    var mockAuthService: MockAuthenticationService!
    var mockNoteStorage: MockNoteStorage!
    var cancellables: Set<AnyCancellable>!

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()

        mockAuthService = MockAuthenticationService()
        mockNoteStorage = MockNoteStorage()
        cancellables = Set<AnyCancellable>()

        sut = AuthenticationViewModel(
            authService: mockAuthService,
            noteStorage: mockNoteStorage
        )
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        mockNoteStorage = nil
        mockAuthService = nil

        super.tearDown()
    }

    // MARK: - 初始化测试

    func testInit_ShouldSetupCorrectly() {
        // Then
        XCTAssertFalse(sut.isLoggedIn)
        XCTAssertNil(sut.userProfile)
        XCTAssertFalse(sut.showLoginView)
        XCTAssertFalse(sut.isCookieExpired)
        XCTAssertFalse(sut.isPrivateNotesUnlocked)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - login() 测试

    func testLogin_WhenSuccessful_ShouldUpdateState() async {
        // Given
        let username = "test@example.com"
        let password = "password123"
        let expectedProfile = UserProfile.mock(nickname: username)
        mockAuthService.mockUserProfile = expectedProfile

        // When
        await sut.login(username: username, password: password)

        // Then
        XCTAssertTrue(sut.isLoggedIn)
        XCTAssertEqual(sut.userProfile?.nickname, username)
        XCTAssertFalse(sut.showLoginView)
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
        XCTAssertEqual(mockAuthService.loginCallCount, 1)
    }

    func testLogin_WhenFailed_ShouldShowError() async {
        // Given
        let username = "test@example.com"
        let password = "wrong_password"
        mockAuthService.mockError = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid credentials"])

        // When
        await sut.login(username: username, password: password)

        // Then
        XCTAssertFalse(sut.isLoggedIn)
        XCTAssertNil(sut.userProfile)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.errorMessage?.contains("登录失败") ?? false)
        XCTAssertFalse(sut.isLoading)
    }

    func testLogin_WhenAlreadyLoading_ShouldNotStartAgain() async {
        // Given
        sut.isLoading = true
        let username = "test@example.com"
        let password = "password123"

        // When
        await sut.login(username: username, password: password)

        // Then
        XCTAssertEqual(mockAuthService.loginCallCount, 0)
    }

    // MARK: - loginWithCookie() 测试

    func testLoginWithCookie_WhenSuccessful_ShouldUpdateState() async {
        // Given
        let cookie = "test_cookie"
        let expectedProfile = UserProfile.mock()
        mockAuthService.mockUserProfile = expectedProfile

        // When
        await sut.loginWithCookie(cookie)

        // Then
        XCTAssertTrue(sut.isLoggedIn)
        XCTAssertNotNil(sut.userProfile)
        XCTAssertFalse(sut.showLoginView)
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(mockAuthService.loginWithCookieCallCount, 1)
    }

    func testLoginWithCookie_WhenFailed_ShouldShowError() async {
        // Given
        let cookie = "invalid_cookie"
        mockAuthService.mockError = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid cookie"])

        // When
        await sut.loginWithCookie(cookie)

        // Then
        XCTAssertFalse(sut.isLoggedIn)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.errorMessage?.contains("Cookie 登录失败") ?? false)
    }

    // MARK: - logout() 测试

    func testLogout_ShouldClearState() async {
        // Given
        sut.isLoggedIn = true
        sut.userProfile = UserProfile.mock()
        sut.isPrivateNotesUnlocked = true

        // When
        await sut.logout()

        // Then
        XCTAssertFalse(sut.isLoggedIn)
        XCTAssertNil(sut.userProfile)
        XCTAssertFalse(sut.isPrivateNotesUnlocked)
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(mockAuthService.logoutCallCount, 1)
    }

    func testLogout_WhenFailed_ShouldShowError() async {
        // Given
        sut.isLoggedIn = true
        mockAuthService.mockError = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Logout failed"])

        // When
        await sut.logout()

        // Then
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.errorMessage?.contains("登出失败") ?? false)
    }

    // MARK: - refreshCookie() 测试

    func testRefreshCookie_WhenSuccessful_ShouldUpdateState() async {
        // Given
        mockAuthService.mockAccessToken = "new_token"

        // When
        await sut.refreshCookie()

        // Then
        XCTAssertFalse(sut.isCookieExpired)
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(mockAuthService.refreshAccessTokenCallCount, 1)
    }

    func testRefreshCookie_WhenFailed_ShouldShowError() async {
        // Given
        mockAuthService.mockError = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Refresh failed"])

        // When
        await sut.refreshCookie()

        // Then
        XCTAssertTrue(sut.isCookieExpired)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.errorMessage?.contains("Cookie 刷新失败") ?? false)
    }

    // MARK: - unlockPrivateNotes() 测试

    func testUnlockPrivateNotes_ShouldUpdateState() async {
        // Given
        let password = "private_password"

        // When
        await sut.unlockPrivateNotes(password: password)

        // Then
        XCTAssertTrue(sut.isPrivateNotesUnlocked)
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - lockPrivateNotes() 测试

    func testLockPrivateNotes_ShouldClearState() {
        // Given
        sut.isPrivateNotesUnlocked = true

        // When
        sut.lockPrivateNotes()

        // Then
        XCTAssertFalse(sut.isPrivateNotesUnlocked)
    }

    // MARK: - fetchUserProfile() 测试

    func testFetchUserProfile_WhenSuccessful_ShouldUpdateState() async {
        // Given
        let expectedProfile = UserProfile.mock()
        mockAuthService.mockUserProfile = expectedProfile

        // When
        await sut.fetchUserProfile()

        // Then
        XCTAssertNotNil(sut.userProfile)
        XCTAssertEqual(sut.userProfile?.nickname, expectedProfile.nickname)
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(mockAuthService.fetchUserProfileCallCount, 1)
    }

    func testFetchUserProfile_WhenFailed_ShouldShowError() async {
        // Given
        mockAuthService.mockError = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Fetch failed"])

        // When
        await sut.fetchUserProfile()

        // Then
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.errorMessage?.contains("获取用户信息失败") ?? false)
    }

    // MARK: - 认证状态观察测试

    func testAuthenticationStateChange_ShouldUpdateViewModel() async {
        // Given
        let expectation = XCTestExpectation(description: "Authentication state changed")

        sut.$isLoggedIn
            .dropFirst()
            .sink { isLoggedIn in
                if isLoggedIn {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        mockAuthService.setAuthenticated(true)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(sut.isLoggedIn)
    }

    func testUserProfileChange_ShouldUpdateViewModel() async {
        // Given
        let expectedProfile = UserProfile.mock()
        let expectation = XCTestExpectation(description: "User profile changed")

        sut.$userProfile
            .dropFirst()
            .sink { profile in
                if profile != nil {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        mockAuthService.setCurrentUser(expectedProfile)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(sut.userProfile?.nickname, expectedProfile.nickname)
    }
}

// MARK: - UserProfile Mock Extension

extension UserProfile {
    static func mock(
        nickname: String = "test_user",
        icon: String = "https://example.com/icon.png"
    ) -> UserProfile {
        UserProfile(
            nickname: nickname,
            icon: icon
        )
    }
}
