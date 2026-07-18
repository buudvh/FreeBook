import XCTest
@testable import FreeBook

@MainActor
final class FloatingWidgetViewModelTests: XCTestCase {
    private let widgetWidth: CGFloat = 252
    private let widgetHeight: CGFloat = 56
    private let screenWidth: CGFloat = 390
    private let screenHeight: CGFloat = 844
    private let ratioKey = "ttsWidgetVerticalRatio"
    private let edgeKey = "ttsWidgetEdge"

    func testDragEndSnapsToLeftEdge() {
        resetStoredWidgetState()
        let model = FloatingWidgetViewModel()

        model.handleDragEnd(
            finalPosition: CGPoint(x: 20, y: 320),
            widgetWidth: widgetWidth,
            widgetHeight: widgetHeight,
            screenWidth: screenWidth,
            screenHeight: screenHeight,
            edgeSnapDistance: 40
        )

        XCTAssertEqual(model.edgeDirection, .left)
        XCTAssertEqual(model.mode, .peeking)
        XCTAssertEqual(model.verticalRatio, 320 / screenHeight, accuracy: 0.0001)
        XCTAssertEqual(UserDefaults.standard.string(forKey: edgeKey), "left")
        model.cancelTasks()
        resetStoredWidgetState()
    }

    func testDragEndSnapsToRightEdge() {
        resetStoredWidgetState()
        let model = FloatingWidgetViewModel()

        model.handleDragEnd(
            finalPosition: CGPoint(x: 370, y: 420),
            widgetWidth: widgetWidth,
            widgetHeight: widgetHeight,
            screenWidth: screenWidth,
            screenHeight: screenHeight,
            edgeSnapDistance: 40
        )

        XCTAssertEqual(model.edgeDirection, .right)
        XCTAssertEqual(model.mode, .peeking)
        XCTAssertEqual(model.verticalRatio, 420 / screenHeight, accuracy: 0.0001)
        XCTAssertEqual(UserDefaults.standard.string(forKey: edgeKey), "right")
        model.cancelTasks()
        resetStoredWidgetState()
    }

    func testDragEndClampsVerticalPositionToSafeArea() {
        resetStoredWidgetState()
        let model = FloatingWidgetViewModel()
        let minY = widgetHeight / 2 + 92
        let maxY = screenHeight - widgetHeight / 2 - 92

        model.handleDragEnd(
            finalPosition: CGPoint(x: 20, y: 0),
            widgetWidth: widgetWidth,
            widgetHeight: widgetHeight,
            screenWidth: screenWidth,
            screenHeight: screenHeight,
            edgeSnapDistance: 40
        )
        XCTAssertEqual(model.verticalRatio, minY / screenHeight, accuracy: 0.0001)

        model.handleDragEnd(
            finalPosition: CGPoint(x: 20, y: screenHeight + 200),
            widgetWidth: widgetWidth,
            widgetHeight: widgetHeight,
            screenWidth: screenWidth,
            screenHeight: screenHeight,
            edgeSnapDistance: 40
        )
        XCTAssertEqual(model.verticalRatio, maxY / screenHeight, accuracy: 0.0001)

        model.cancelTasks()
        resetStoredWidgetState()
    }

    func testDragFromPeekingToEdgeStaysPeekingAndPersistsPosition() {
        resetStoredWidgetState()
        let model = FloatingWidgetViewModel()
        model.mode = .peeking

        model.handleDragStart()
        XCTAssertEqual(model.mode, .peeking)

        model.handleDragEnd(
            finalPosition: CGPoint(x: 20, y: 360),
            widgetWidth: widgetWidth,
            widgetHeight: widgetHeight,
            screenWidth: screenWidth,
            screenHeight: screenHeight,
            edgeSnapDistance: 40
        )

        XCTAssertEqual(model.mode, .peeking)
        XCTAssertEqual(model.edgeDirection, .left)
        XCTAssertEqual(UserDefaults.standard.string(forKey: edgeKey), "left")
        XCTAssertEqual(UserDefaults.standard.double(forKey: ratioKey), Double(360 / screenHeight), accuracy: 0.0001)
        model.cancelTasks()
        resetStoredWidgetState()
    }

    func testDragFromPeekingAwayFromEdgeEndsRevealed() {
        resetStoredWidgetState()
        let model = FloatingWidgetViewModel()
        model.mode = .peeking

        model.handleDragStart()
        model.handleDragEnd(
            finalPosition: CGPoint(x: screenWidth / 2, y: 360),
            widgetWidth: widgetWidth,
            widgetHeight: widgetHeight,
            screenWidth: screenWidth,
            screenHeight: screenHeight,
            edgeSnapDistance: 40
        )

        XCTAssertEqual(model.mode, .revealed)
        XCTAssertFalse(model.isDragging)
        model.cancelTasks()
        resetStoredWidgetState()
    }

    func testRevealTransitionsFromPeekingToRevealed() {
        resetStoredWidgetState()
        let model = FloatingWidgetViewModel()
        model.mode = .peeking

        model.reveal()

        XCTAssertEqual(model.mode, .revealed)
        model.cancelTasks()
        resetStoredWidgetState()
    }

    func testInvalidScreenSizeEndsDragging() {
        resetStoredWidgetState()
        let model = FloatingWidgetViewModel()
        model.handleDragStart()

        model.handleDragEnd(
            finalPosition: CGPoint(x: 20, y: 360),
            widgetWidth: widgetWidth,
            widgetHeight: widgetHeight,
            screenWidth: 0,
            screenHeight: 0,
            edgeSnapDistance: 40
        )

        XCTAssertFalse(model.isDragging)
        model.cancelTasks()
        resetStoredWidgetState()
    }

    func testAutoHideBlockedDuringDrag() {
        resetStoredWidgetState()
        let model = FloatingWidgetViewModel()
        model.mode = .peeking

        // Simulate drag in progress
        model.isDragging = true
        model.startAutoHideTimer()

        // Timer should not have been scheduled at all
        // Mode should still be peeking immediately
        XCTAssertEqual(model.mode, .peeking)

        // Clean up
        model.isDragging = false
        model.cancelTasks()
        resetStoredWidgetState()
    }

    private func resetStoredWidgetState() {
        UserDefaults.standard.removeObject(forKey: ratioKey)
        UserDefaults.standard.removeObject(forKey: edgeKey)
    }
}
