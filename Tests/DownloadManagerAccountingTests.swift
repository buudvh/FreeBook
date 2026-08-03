import XCTest
@testable import FreeBook

final class DownloadManagerAccountingTests: XCTestCase {
    func testCalculateOutcome_allCached_returnsCompleted() {
        let outcome = DownloadTaskOutcomeCalculator.calculateOutcome(
            taskType: .download,
            uncachedAttemptCount: 0,
            savedCount: 0,
            failedCount: 0,
            isExportTxtEmpty: false
        )
        XCTAssertEqual(outcome, .completed)
    }

    func testCalculateOutcome_partialFailure_returnsFailedWithSavedAndFailedCounts() {
        let outcome = DownloadTaskOutcomeCalculator.calculateOutcome(
            taskType: .download,
            uncachedAttemptCount: 10,
            savedCount: 7,
            failedCount: 3,
            isExportTxtEmpty: false
        )
        if case .failed(let message) = outcome {
            XCTAssertTrue(message.contains("Đã lưu 7 chương"))
            XCTAssertTrue(message.contains("Thất bại 3 chương"))
        } else {
            XCTFail("Kì vọng kết quả thất bại cho partial failure")
        }
    }

    func testCalculateOutcome_zeroSave_returnsFailedWithFailedCount() {
        let outcome = DownloadTaskOutcomeCalculator.calculateOutcome(
            taskType: .download,
            uncachedAttemptCount: 5,
            savedCount: 0,
            failedCount: 5,
            isExportTxtEmpty: false
        )
        XCTAssertEqual(outcome, .failed(message: "Không thể tải chương mới nào (Thất bại: 5)."))
    }

    func testCalculateOutcome_exportTxtZeroFailedButEmptyContent_returnsFailed() {
        let outcome = DownloadTaskOutcomeCalculator.calculateOutcome(
            taskType: .exportTxt,
            uncachedAttemptCount: 0,
            savedCount: 0,
            failedCount: 0,
            isExportTxtEmpty: true
        )
        if case .failed(let message) = outcome {
            XCTAssertTrue(message.contains("Xuất file TXT không hoàn chỉnh"))
            XCTAssertTrue(message.contains("Rỗng: true"))
        } else {
            XCTFail("Kì vọng kết quả thất bại khi file TXT bị rỗng dù failedCount == 0")
        }
    }

    func testCalculateOutcome_exportTxtIncomplete_returnsFailed() {
        let outcome = DownloadTaskOutcomeCalculator.calculateOutcome(
            taskType: .exportTxt,
            uncachedAttemptCount: 5,
            savedCount: 3,
            failedCount: 2,
            isExportTxtEmpty: false
        )
        if case .failed(let message) = outcome {
            XCTAssertTrue(message.contains("Xuất file TXT không hoàn chỉnh"))
            XCTAssertTrue(message.contains("Lỗi: 2 chương"))
        } else {
            XCTFail("Kì vọng kết quả thất bại khi xuất TXT không hoàn chỉnh")
        }
    }

    func testCalculateOutcome_exportOnlyCachedWithContent_returnsCompleted() {
        let outcome = DownloadTaskOutcomeCalculator.calculateOutcome(
            taskType: .exportTxt,
            uncachedAttemptCount: 0,
            savedCount: 0,
            failedCount: 0,
            isExportTxtEmpty: false
        )
        XCTAssertEqual(outcome, .completed)
    }
}
