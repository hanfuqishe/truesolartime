import Foundation

/// WeatherKit **尝试状态**（纯值，可离线断言）。
///
/// 存在的理由：真机上出现过「WeatherKit 一次都没被尝试」——诊断里只有「最近失败 = 暫無」，
/// 看不出到底是**没走到请求**、**设置不让试**、还是**试过但被冲掉**。这个状态机把三件事分开记：
/// 是否尝试、什么时候尝试、结果如何，并支持「地点变化 → 重置」。
struct WeatherAttemptState: Equatable {

    enum Outcome: Equatable {
        case notAttempted
        case succeeded
        case failed(String)
    }

    private(set) var attempted = false
    /// 尝试时刻（Unix 秒）；`nil` = 没试过。
    private(set) var attemptedAt: TimeInterval?
    private(set) var outcome: Outcome = .notAttempted

    /// 地点变化 / 用户手动切换数据源时重置：否则「第一次失败」之后会永远显示失败、也不再记录新尝试。
    mutating func reset() {
        attempted = false
        attemptedAt = nil
        outcome = .notAttempted
    }

    mutating func markSucceeded(at now: TimeInterval) {
        attempted = true
        attemptedAt = now
        outcome = .succeeded
    }

    mutating func markFailed(_ reason: String, at now: TimeInterval) {
        attempted = true
        attemptedAt = now
        outcome = .failed(reason)
    }

    /// 该不该在「地点变化」时重置（纯函数，方便断言）。
    static func shouldReset(placeChanged: Bool) -> Bool { placeChanged }

    /// 诊断一行：`未尝试` / `已尝试 · 12 分钟前 · 成功` / `已尝试 · 3 分钟前 · 失败：<原因>`。
    func summary(now: TimeInterval) -> String {
        guard attempted else { return "未尝试" }
        let minutes = attemptedAt.map { max(0, Int((now - $0) / 60)) } ?? 0
        switch outcome {
        case .notAttempted:
            return "已尝试 · \(minutes) 分钟前"
        case .succeeded:
            return "已尝试 · \(minutes) 分钟前 · 成功"
        case .failed(let reason):
            return "已尝试 · \(minutes) 分钟前 · 失败：\(reason)"
        }
    }
}
