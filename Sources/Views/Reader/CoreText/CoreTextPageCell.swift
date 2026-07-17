import Foundation
import UIKit

final class CoreTextPageCell: UICollectionViewCell {
    static let reuseIdentifier = "CoreTextPageCell"
    
    private let pageView = CoreTextPageView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let errorLabel = UILabel()
    private let reloadButton = UIButton(type: .system)
    
    var onReloadTap: (() -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        contentView.backgroundColor = .clear
        backgroundColor = .clear
        
        // Setup pageView
        pageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pageView)
        
        // Setup loadingIndicator
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        contentView.addSubview(loadingIndicator)
        
        // Setup errorLabel
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.font = .systemFont(ofSize: 14)
        errorLabel.textColor = .systemRed
        contentView.addSubview(errorLabel)
        
        // Setup reloadButton
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        reloadButton.setTitle("Tải lại", for: .normal)
        reloadButton.addTarget(self, action: #selector(handleReloadTap), for: .touchUpInside)
        contentView.addSubview(reloadButton)
        
        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            pageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            pageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            errorLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -20),
            errorLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            reloadButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 12),
            reloadButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor)
        ])
        
        showTextState()
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        pageView.attributedString = nil
        pageView.pageRange = nil
        pageView.highlightRange = nil
        onReloadTap = nil
        showTextState()
    }
    
    @objc private func handleReloadTap() {
        onReloadTap?()
    }
    
    /// Cấu hình hiển thị chữ bình thường
    func configure(
        attributedString: NSAttributedString,
        pageRange: NSRange,
        highlightRange: NSRange?,
        insets: UIEdgeInsets,
        highlightColor: UIColor,
        themeTextColor: UIColor
    ) {
        showTextState()
        pageView.contentInsets = insets
        pageView.highlightColor = highlightColor
        pageView.highlightRange = highlightRange
        pageView.attributedString = attributedString
        pageView.pageRange = pageRange
        
        loadingIndicator.color = themeTextColor.opacity(0.8)
    }
    
    /// Hiển thị trạng thái đang tải chương
    func showLoading(themeTextColor: UIColor) {
        pageView.isHidden = true
        errorLabel.isHidden = true
        reloadButton.isHidden = true
        loadingIndicator.isHidden = false
        loadingIndicator.color = themeTextColor.opacity(0.8)
        loadingIndicator.startAnimating()
    }
    
    /// Hiển thị trạng thái tải lỗi
    func showError(message: String, themeTextColor: UIColor) {
        pageView.isHidden = true
        loadingIndicator.stopAnimating()
        errorLabel.isHidden = false
        reloadButton.isHidden = false
        
        errorLabel.text = message
        errorLabel.textColor = .systemRed
        reloadButton.setTitleColor(themeTextColor, for: .normal)
    }
    
    private func showTextState() {
        pageView.isHidden = false
        loadingIndicator.stopAnimating()
        errorLabel.isHidden = true
        reloadButton.isHidden = true
    }
}

// Helper để tạo UIColor.opacity
private extension UIColor {
    func opacity(_ alpha: CGFloat) -> UIColor {
        return self.withAlphaComponent(alpha)
    }
}
