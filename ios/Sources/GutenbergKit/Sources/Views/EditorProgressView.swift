import SwiftUI

#if canImport(UIKit)
import UIKit

/// A UIKit view displaying a progress bar with a customizable label underneath.
class UIEditorProgressView: UIView {

    /// The text displayed below the progress bar.
    var loadingText: String {
        get { label.text ?? "" }
        set { label.text = newValue }
    }

    private let progressView: UIProgressView = {
        let view = UIProgressView(progressViewStyle: .default)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    convenience init(loadingText: String) {
        self.init(frame: .zero)
        self.loadingText = loadingText
    }

    func setProgress(_ progress: EditorProgress, animated: Bool) {
        progressView.setProgress(Float(progress.fractionCompleted), animated: animated)
    }

    private func setupViews() {
        addSubview(progressView)
        addSubview(label)

        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            progressView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0),

            label.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
    }
}

struct EditorProgressView: UIViewRepresentable {
    typealias UIViewType = UIEditorProgressView

    @Binding
    var progress: EditorProgress

    let loadingText: String

    func makeUIView(context: Context) -> UIViewType {
        UIViewType(loadingText: loadingText)
    }

    @MainActor
    func updateUIView(_ uiView: UIViewType, context: Context) {
        uiView.setProgress(progress, animated: true)
    }
}

#Preview {
    @Previewable @State
    var editorProgress: EditorProgress = EditorProgress(completed: 1, total: 100)

    Spacer()
    EditorProgressView(progress: $editorProgress, loadingText: "Loading Editor")
    Spacer()
    HStack {
        Spacer()
        Button("-") {
            withAnimation {
                editorProgress = EditorProgress(
                    completed: max(-10, editorProgress.completed - 10),
                    total: editorProgress.total
                )
            }
        }.buttonStyle(.borderedProminent)
        Spacer()
        Button("+") {
            withAnimation {
                editorProgress = EditorProgress(
                    completed: editorProgress.completed + 10,
                    total: editorProgress.total
                )
            }
        }.buttonStyle(.borderedProminent)
        Spacer()
    }
}

#endif
