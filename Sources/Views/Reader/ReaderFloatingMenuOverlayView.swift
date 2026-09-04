import SwiftUI

struct ReaderFloatingMenuOverlayView: View {
    @Binding var isShowing: Bool
    @Binding var clearSelectionTrigger: UUID?
    let selectionMinY: CGFloat
    let selectionMaxY: CGFloat
    let geometryOriginY: CGFloat
    let screenWidth: CGFloat
    let screenHeight: CGFloat

    let onTranslate: () -> Void
    let onSpeak: () -> Void
    let onPhoneme: () -> Void
    let onCopy: () -> Void
    let onCopyOriginal: () -> Void
    let onReadSelected: () -> Void
    let onDeleteJunk: () -> Void
    let onAddToTTSReplacement: () -> Void
    let onSearchWeb: () -> Void

    var body: some View {
        ZStack {
            if isShowing {
                // Overlay trong suốt phủ toàn màn hình bắt tap ra ngoài menu
                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            clearSelectionTrigger = UUID()
                            isShowing = false
                        }
                    )
                    .zIndex(9)

                // Floating bubble menu khi bôi đen
                FloatingSelectionMenu(
                    selectionMinY: selectionMinY,
                    selectionMaxY: selectionMaxY,
                    geometryOriginY: geometryOriginY,
                    screenWidth: screenWidth,
                    screenHeight: screenHeight,
                    onTranslate: {
                        clearSelectionTrigger = UUID()
                        isShowing = false
                        onTranslate()
                    },
                    onSpeak: {
                        clearSelectionTrigger = UUID()
                        isShowing = false
                        onSpeak()
                    },
                    onPhoneme: {
                        clearSelectionTrigger = UUID()
                        isShowing = false
                        onPhoneme()
                    },
                    onCopy: {
                        clearSelectionTrigger = UUID()
                        isShowing = false
                        onCopy()
                    },
                    onCopyOriginal: {
                        clearSelectionTrigger = UUID()
                        isShowing = false
                        onCopyOriginal()
                    },
                    onReadSelected: {
                        onReadSelected()
                    },
                    onDeleteJunk: {
                        clearSelectionTrigger = UUID()
                        isShowing = false
                        onDeleteJunk()
                    },
                    onAddToTTSReplacement: {
                        clearSelectionTrigger = UUID()
                        isShowing = false
                        onAddToTTSReplacement()
                    },
                    onSearchWeb: {
                        clearSelectionTrigger = UUID()
                        isShowing = false
                        onSearchWeb()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .zIndex(10)
            }
        }
    }
}
