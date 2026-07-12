import SwiftUI
import UniformTypeIdentifiers
import UIKit

extension UTType {
    static var onnx: UTType {
        if let utType = UTType(filenameExtension: "onnx", conformingTo: .data) {
            return utType
        }
        return UTType(exportedAs: "com.onnxruntime.onnx")
    }
}

// MARK: - Host view controller

final class DocumentPickerHostViewController: UIViewController, UIDocumentPickerDelegate {
    var allowedContentTypes: [UTType] = []
    var allowsMultipleSelection = false
    var onPick: (([URL]) -> Void)?
    var onCancel: (() -> Void)?
    var onFinished: (() -> Void)?

    private var didPresentPicker = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didPresentPicker else { return }
        didPresentPicker = true
        presentDocumentPicker()
    }

    private func presentDocumentPicker() {
        guard presentedViewController == nil else { return }
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: allowedContentTypes,
            asCopy: true
        )
        picker.delegate = self
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        present(picker, animated: true)
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        controller.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.onPick?(urls)
            self.finishPresentation()
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true) { [weak self] in
            self?.onCancel?()
            self?.finishPresentation()
        }
    }

    private func finishPresentation() {
        let finished = onFinished
        if presentingViewController != nil {
            dismiss(animated: true) {
                DispatchQueue.main.async {
                    finished?()
                }
            }
        } else {
            DispatchQueue.main.async {
                finished?()
            }
        }
    }
}

// MARK: - Modal presenter (no SwiftUI .sheet wrapper)

struct DocumentPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let allowedContentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onPick: ([URL]) -> Void
    let onCancel: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let anchor = UIViewController()
        anchor.view.backgroundColor = .clear
        anchor.view.isUserInteractionEnabled = false
        return anchor
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if isPresented {
            guard context.coordinator.host == nil else { return }
            let host = DocumentPickerHostViewController()
            host.allowedContentTypes = allowedContentTypes
            host.allowsMultipleSelection = allowsMultipleSelection
            host.onPick = onPick
            host.onCancel = onCancel
            host.onFinished = { [weak coordinator = context.coordinator] in
                coordinator?.isPresented.wrappedValue = false
                coordinator?.host = nil
            }
            host.modalPresentationStyle = .overFullScreen
            host.view.backgroundColor = .clear
            context.coordinator.host = host
            uiViewController.present(host, animated: true)
        } else if let host = context.coordinator.host {
            if host.presentingViewController === uiViewController {
                uiViewController.dismiss(animated: true) {
                    context.coordinator.host = nil
                }
            } else {
                context.coordinator.host = nil
            }
        }
    }

    final class Coordinator {
        var isPresented: Binding<Bool>
        var host: DocumentPickerHostViewController?

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }
    }
}

// MARK: - Sheet content (dictionary import and legacy callers)

struct DocumentPicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onPick: ([URL]) -> Void
    let onCancel: (() -> Void)?

    func makeUIViewController(context: Context) -> DocumentPickerHostViewController {
        let host = DocumentPickerHostViewController()
        host.allowedContentTypes = allowedContentTypes
        host.allowsMultipleSelection = allowsMultipleSelection
        host.onPick = onPick
        host.onCancel = onCancel
        return host
    }

    func updateUIViewController(_ uiViewController: DocumentPickerHostViewController, context: Context) {}
}
