import SwiftUI

/// Màn hình AI Agent Harness Toàn Màn Hình trong Reader.
public struct ReaderAIFullScreenView: View {
    @Environment(\.dismiss) internal var dismiss

    public let bookId: String
    public let bookTitle: String
    public let chapterIndex: Int
    public let chapterTitle: String
    public let currentChapterRawContent: String

    @State internal var currentSession: AIChatSession
    @State internal var inputText: String = ""
    @State internal var isStreaming: Bool = false
    @State internal var streamingTask: Task<Void, Never>? = nil

    @State internal var isBatchExtracting: Bool = false
    @State internal var batchProgress: (current: Int, total: Int)? = nil
    @State internal var batchExtractionTask: Task<Void, Never>? = nil
    @State internal var batchExtractedNames: [AIExtractedName] = []

    @State internal var showingSettings: Bool = false
    @State internal var showingSessionList: Bool = false
    @State internal var availableModels: [String] = []
    @State internal var selectedModel: String = ""
    @State internal var selectedMode: AIHarnessMode = .bypass
    @State internal var currentSessionId: UUID = UUID()

    public init(
        bookId: String,
        bookTitle: String,
        chapterIndex: Int,
        chapterTitle: String,
        currentChapterRawContent: String
    ) {
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.currentChapterRawContent = currentChapterRawContent

        let initialSession = AIChatSession(bookId: bookId, title: "Phiên chat mới")
        self._currentSession = State(initialValue: initialSession)
        self._currentSessionId = State(initialValue: initialSession.id)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Thanh tiến trình khi đang quét toàn bộ chương đã tải
                if isBatchExtracting, let progress = batchProgress {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Đang quét tên riêng: Batch \(progress.current)/\(progress.total)...")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("Đã tìm thấy \(batchExtractedNames.count) tên riêng")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Dừng") {
                            cancelBatchExtraction()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.12))
                }

                // Vùng nội dung tin nhắn chat
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(currentSession.messages) { message in
                                messageRow(message)
                                    .id(message.id)
                            }

                            // Bảng tên riêng từ Batch Extraction nếu có
                            if !batchExtractedNames.isEmpty && !isBatchExtracting {
                                ReaderAINameReviewCardView(names: $batchExtractedNames) { itemsToSave in
                                    saveNamesToDictionary(itemsToSave)
                                }
                                .padding(.horizontal, 12)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .onChange(of: currentSession.messages.count) { _, _ in
                        if let lastId = currentSession.messages.last?.id {
                            withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                        }
                    }
                }

                Divider()

                // Thanh gợi ý thao tác nhanh
                ReaderAIQuickActionChipsView { actionType in
                    handleQuickAction(actionType)
                }

                // Khung nhập tin nhắn tích hợp Mode Menu & Model Picker
                ReaderAIInputBarView(
                    inputText: $inputText,
                    selectedMode: $selectedMode,
                    selectedModel: $selectedModel,
                    availableModels: availableModels,
                    isStreaming: isStreaming,
                    onSend: { sendUserMessage() },
                    onStop: { stopStreaming() }
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }

                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(currentSession.title)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                        Text("\(bookTitle) • Chương \(chapterIndex + 1)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 8) {
                        Button(action: startNewChat) {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                Text("Mới")
                            }
                            .font(.system(size: 12, weight: .semibold))
                        }

                        Button(action: { showingSessionList = true }) {
                            Image(systemName: "clock.arrow.circlepath")
                        }

                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    AISettingsView()
                }
                .onDisappear {
                    reloadSettings()
                }
            }
            .sheet(isPresented: $showingSessionList) {
                ReaderAISessionListView(
                    bookId: bookId,
                    currentSessionId: $currentSessionId,
                    onSelectSession: { session in
                        switchToSession(session)
                    },
                    onNewSession: {
                        startNewChat()
                    }
                )
            }
            .onAppear {
                initializeSession()
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: AIChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 32)
                Text(message.content)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(16)
            } else {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                    .font(.system(size: 14))
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 8) {
                    if !message.content.isEmpty {
                        Text(message.content)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(16)
                    }

                    if let actions = message.harnessActions, !actions.isEmpty {
                        ReaderAIActionPlanCardView(
                            actions: actions,
                            mode: currentSession.mode,
                            onApprove: { action in approveAction(action) },
                            onReject: { action in rejectAction(action) },
                            onApproveAll: { approveAllActions(actions) }
                        )
                    }

                    if var extracted = message.extractedNames, !extracted.isEmpty {
                        ReaderAINameReviewCardView(names: Binding(
                            get: { extracted },
                            set: { extracted = $0 }
                        )) { itemsToSave in
                            saveNamesToDictionary(itemsToSave)
                        }
                    }
                }
                Spacer(minLength: 32)
            }
        }
        .padding(.horizontal, 12)
    }
}
