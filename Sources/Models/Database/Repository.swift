import Foundation
import SwiftData

@Model
public final class Repository {
    @Attribute(.unique) public var url: String
    public var name: String
    public var author: String?
    public var desc: String?
    // Kept for SwiftData schema compatibility. Repository enable/disable UI was removed.
    public var isEnabled: Bool = true
    public var lastUpdated: Date = Date()
    
    @Relationship(deleteRule: .cascade, inverse: \Extension.repository)
    public var extensions: [Extension] = []
    
    public init(url: String, name: String, author: String? = nil, desc: String? = nil, isEnabled: Bool = true) {
        self.url = url
        self.name = name
        self.author = author
        self.desc = desc
        self.isEnabled = isEnabled
        self.lastUpdated = Date()
    }
}
