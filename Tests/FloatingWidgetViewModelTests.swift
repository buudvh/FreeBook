import XCTest
@testable import FreeBook

@MainActor
final class FloatingWidgetViewModelTests: XCTestCase {
    private let buttonSize: CGFloat = 55
    private let screenWidth: CGFloat = 390
    private let screenHeight: CGFloat = 844
    private let ratioKey = "ttsWidgetVerticalRatio"
    private let edgeKey = "ttsWidgetEdge"

    func testDragEndSnapsToLeftEdge() {
        resetStoredWidgetState()
        let model = FloatingWidgetViewModel()

        model.handleDragEnd(
            finalPosition: CGPoint(x: 120, y: 320),
            buttonSize: buttonSize,
            screenWidth: screenWidth,
            screenHeight: screenHeight
        )

        XCTAssertEqual(model.edgeDirection, .left)
        XCTAssertEqual(model.mode, .collapsed)
        XCTAssertEqual(model.verticalRatio, 320 / screenHeight, accuracy: 0.0001)
        XCTAssertEqual(UserDefaults.standard.string(forKey: edgeKey), "left")
        model.cancelTasks()
        resetStoredWidgetState()
    }

    func testDragEndSnapsToRightEdge() {
        resetStoredWidgetState()
        let model = FloatingWidgetViewModel()

        model.handleDragEnd(
            finalPosition: CGPoint(x: 300, y: 420),
            buttonSize: buttonSize,
            screenWidth: screenWidth,
            screenHeight: screenHeight
        )

        XCTAssertEqual(model.edgeDirection, .right)
        XCTAssertEqual(model.mode, .collapsed)
        XCTAssertEqual(model.verticalRatio, 420 / screenHeight, accuracy: 0.0001)
        XCTAssertEqual(UserDefaults.standard.string(forKey: edgeKey), "right")
        model.cancelTasks()
        resetStoredWidgetState()
    }

    func testDragEndClampsVerticalPositionToSafeArea() {
        resetStoredWidgetState()
        let model = FloatingWidgetViewModel()
        let minY = buttonSize / 2 + 100
        let maxY = screenHeight - buttonSize / 2 - 120

        model.handleDragEnd(
            finalPosition: CGPoint(x: 120, y: 0),
            buttonSize: buttonSize,
            screenWidth: screenWidth,
            screenHeight: screenHeight
        )
        XCTAssertEqual(model.verticalRatio, minY / screenHeight, accuracy: 0.0001)

        model.handleDragEnd(
            finalPosition: CGPoint(x: 120, y: screenHeight + 200),
            buttonSize: buttonSize,
            screenWidth: screenWidth,
            screenHeight: screenHeight
        )
        XCTAssertEqual(model.verticalRatio, maxY / screenHeight, accuracy: 0.0001)

        model.cancelTasks()
        resetStoredWidgetState()
    }

    func testDragFromHiddenEndsCollapsedAndPersistsPosition() {
        resetStoredWidgetState()
        let model = FloatingWidgetViewModel()
        model.mode = .hidden

        model.handleDragStart()
        XCTAssertEqual(model.mode, .collapsed)

        model.handleDragEnd(
            finalPosition: CGPoint(x: 80, y: 360),
            buttonSize: buttonSize,
            screenWidth: screenWidth,
            screenHeight: screenHeight
        )

        XCTAssertEqual(model.mode, .collapsed)
        XCTAssertEqual(model.edgeDirection, .left)
        XCTAssertEqual(UserDefaults.standard.string(forKey: edgeKey), "left")
        XCTAssertEqual(UserDefaults.standard.double(forKey: ratioKey), Double(360 / screenHeight), accuracy: 0.0001)
        model.cancelTasks()
        resetStoredWidgetState()
    }

    private func resetStoredWidgetState() {
        UserDefaults.standard.removeObject(forKey: ratioKey)
        UserDefaults.standard.removeObject(forKey: edgeKey)
    }
}
