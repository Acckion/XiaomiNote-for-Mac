//
//  ImageServiceProtocol.swift
//  MiNoteMac
//
//  Created on 2026-01-22.
//  图片服务协议 - 定义图片处理操作接口
//

import Foundation
import AppKit

/// 图片服务协议
///
/// 定义了图片处理相关的操作接口，包括：
/// - 图片上传和下载
/// - 图片缓存
/// - 图片处理
protocol ImageServiceProtocol {
    // MARK: - 上传操作

    /// 上传图片
    /// - Parameter image: 图片对象
    /// - Returns: 图片URL
    func uploadImage(_ image: NSImage) async throws -> String

    /// 上传图片数据
    /// - Parameters:
    ///   - data: 图片数据
    ///   - filename: 文件名
    /// - Returns: 图片URL
    func uploadImageData(_ data: Data, filename: String) async throws -> String

    // MARK: - 下载操作

    /// 下载图片
    /// - Parameter url: 图片URL
    /// - Returns: 图片对象
    func downloadImage(from url: String) async throws -> NSImage

    /// 下载图片数据
    /// - Parameter url: 图片URL
    /// - Returns: 图片数据
    func downloadImageData(from url: String) async throws -> Data

    // MARK: - 缓存操作

    /// 获取缓存的图片
    /// - Parameter url: 图片URL
    /// - Returns: 图片对象，如果未缓存返回 nil
    func getCachedImage(for url: String) -> NSImage?

    /// 缓存图片
    /// - Parameters:
    ///   - image: 图片对象
    ///   - url: 图片URL
    func cacheImage(_ image: NSImage, for url: String)

    /// 清除图片缓存
    func clearImageCache()

    // MARK: - 图片处理

    /// 压缩图片
    /// - Parameters:
    ///   - image: 图片对象
    ///   - quality: 压缩质量（0.0 - 1.0）
    /// - Returns: 压缩后的图片数据
    func compressImage(_ image: NSImage, quality: Double) -> Data?

    /// 调整图片大小
    /// - Parameters:
    ///   - image: 图片对象
    ///   - size: 目标大小
    /// - Returns: 调整后的图片
    func resizeImage(_ image: NSImage, to size: CGSize) -> NSImage?

    /// 生成缩略图
    /// - Parameters:
    ///   - image: 图片对象
    ///   - size: 缩略图大小
    /// - Returns: 缩略图
    func generateThumbnail(from image: NSImage, size: CGSize) -> NSImage?
}
