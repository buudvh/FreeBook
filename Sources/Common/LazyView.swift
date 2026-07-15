import SwiftUI

public struct LazyView<Content: View>: View {
    private let build: () -> Content
    
    public init(_ build: @escaping () -> Content) {
        self.build = build
    }
    
    public var body: Content {
        build()
    }
}
