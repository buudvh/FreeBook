import Foundation

struct RegexRule {
    let regex: NSRegularExpression
    let template: String

    init(pattern: String, options: NSRegularExpression.Options = [], template: String) {
        self.regex = try! NSRegularExpression(pattern: pattern, options: options)
        self.template = template
    }
}

