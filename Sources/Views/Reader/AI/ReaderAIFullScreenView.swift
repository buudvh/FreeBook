import SwiftUI

/// Màn hình AI Agent Harness Toàn Màn Hình trong Reader.
public struct ReaderAIFullScreenView: View {
    @Environment(\.dismiss) internal var dismiss

    public let bookId: String
    public let bookTitle: String
    public let chapterIndex: Int
    public let chapterTitle: String
    public let currentChapterRawContent: String
    /// Cấu hình dịch của Reader cho truyện (1.3.603) — sheet quét tên riêng dịch tên chương theo nó.
    public let translatesChapterTitles: Bool
    public let convertsTraditionalToSimplified: Bool

    @State internal var currentSession: AIChatSession
    @State internal var inputText: String = ""
    @State internal var isStreaming: Bool = false
    @State internal var streamingTask: Task<Void, Never>? = nil

    @State internal var isBatchExtracting: Bool = false
    @State internal var batchProgress: AINameScanProgress? = nil
    @State internal var batchExtractionTask: Task<Void, Never>? = nil
    @State internal var batchExtractedNames: [AIExtractedName] = []
    @State internal var nameScanRetry: AIRuntimeCoordinator.NameScanRetryInfo? = nil

    @State internal var showingSettings: Bool = false
    @State internal var showingSessionList: Bool = false
    @State internal var showingMemorySheet: Bool = false
    @State internal var showingBatchPromptSheet: Bool = false
    @State internal var nameExtractionPromptForSheet: String = ""
    @State private var nameReviewTarget: ReaderAINameReviewSheet.Target? = nil
    @State internal var availableProfiles: [AIProviderProfile] = []
    @State internal var selectedProfileId: String = ""
    @State internal var availableModels: [String] = []
    @State internal var selectedModel: String = ""
    @State internal var selectedMode: AIHarnessMode = .bypass
    @State internal var currentSessionId: UUID = UUID()
    @State internal var isLoadingSession: Bool = true
    @State internal var visibleMessageCount: Int = 20

    internal var displayedMessages: [AIChatMessage] {
        let all = currentSession.messages
        if all.count <= visibleMessageCount {
            return all
        }
        return Array(all.suffix(visibleMessageCount))
    }

    public init(
        bookId: String,
        bookTitle: String,
        chapterIndex: Int,
        chapterTitle: String,
        currentChapterRawContent: String,
        translatesChapterTitles: Bool = false,
        convertsTraditionalToSimplified: Bool = false
    ) {
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.currentChapterRawContent = currentChapterRawContent
        self.translatesChapterTitles = translatesChapterTitles
        self.convertsTraditionalToSimplified = convertsTraditionalToSimplified

        let initialSession = AIChatSession(bookId: bookId, title: "Phiên chat mới")
        self._currentSession = State(initialValue: initialSession)
        self._currentSessionId = State(initialValue: initialSession.id)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Thanh tiến trình khi đang quét toàn bộ chương đã tải
                if isBatchExtracting, let progress = batchProgress {
                    ReaderAIBatchProgressBannerView(
                        progress: progress,
                        foundCount: batchExtractedNames.count,
                        onStop: { cancelBatchExtraction() }
                    )
                }

                // Vùng nội dung tin nhắn chat
                if isLoadingSession {
                    ReaderAISkeletonView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 12) {
                                if currentSession.messages.count > visibleMessageCount {
                                    Button(action: {
                                        withAnimation {
                                            visibleMessageCount += 20
                                        }
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "arrow.up.circle.fill")
                                            Text("Tải thêm tin nhắn cũ hơn (\(currentSession.messages.count - visibleMessageCount) còn lại)")
                                        }
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.vertical, 8)
                                    }
                                }

                                // Badge nén ngữ cảnh nếu session đã compact
                                if currentSession.contextSummary != nil {
                                    HStack(spacing: 6) {
                                        Image(systemName: "brain.head.profile")
                                        Text("Đã tối ưu ngữ cảnh hội thoại cũ")
                                    }
                                    .font(.caption2.bold())
                                    .foregroundColor(.purple)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.purple.opacity(0.1))
                                    .cornerRadius(12)
                                    .padding(.top, 4)
                                }

                                ForEach(displayedMessages) { message in
                                    messageRow(message)
                                        .id(message.id)
                                }

                                // Mốc neo đáy để cuộn chính xác, chống giật/đen màn hình
                                Color.clear
                                    .frame(height: 1)
                                    .id("bottomScrollAnchor")
                            }
                            .padding(.vertical, 12)
                        }
                        .defaultScrollAnchor(.bottom)
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: currentSession.messages.count) { _, _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    if let lastId = currentSession.messages.last?.id {
                                        proxy.scrollTo(lastId, anchor: .bottom)
                                    } else {
                                        proxy.scrollTo("bottomScrollAnchor", anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }

                Divider()

                // Thanh gợi ý thao tác nhanh — mờ và khoá khi có lệnh AI đang chạy (chat hoặc quét)
                ReaderAIQuickActionChipsView(isDisabled: isStreaming || isBatchExtracting) { actionType in
                    handleQuickAction(actionType)
                }

                // Khung nhập tin nhắn tích hợp Mode Menu, Provider & Model Picker
                ReaderAIInputBarView(
                    inputText: $inputText,
                    selectedMode: $selectedMode,
                    selectedProfileId: $selectedProfileId,
                    selectedModel: $selectedModel,
                    availableProfiles: availableProfiles,
                    availableModels: availableModels,
                    isStreaming: isStreaming,
                    onProfileChanged: { newProfileId in
                        handleProfileChanged(newProfileId)
                    },
                    onSend: { sendUserMessage() },
                    onStop: { stopStreaming() }
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color(white: 0.18))
                            .clipShape(Circle())
                    }
                }

                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Trợ lý AI")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text(currentSession.title)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: startNewChat) {
                            Label("Tạo phiên mới", systemImage: "plus")
                        }
                        Button(action: { showingMemorySheet = true }) {
                            Label("Trí nhớ truyện", systemImage: "brain")
                        }
                        Button(action: { showingSessionList = true }) {
                            Label("Lịch sử chat", systemImage: "clock.arrow.circlepath")
                        }
                        Divider()
                        Button(action: { showingSettings = true }) {
                            Label("Cài đặt AI", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
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
            .sheet(isPresented: $showingMemorySheet) {
                BookAIMemorySheet(bookId: bookId)
            }
            .sheet(isPresented: $showingSessionList) {
                ReaderAISessionListView(
                    bookId: bookId,
                    currentSessionId: $currentSessionId,
                    onSelectSession: { session in switchToSession(session) },
                    onNewSession: { startNewChat() }
                )
            }
            .sheet(item: $nameReviewTarget) { target in
                ReaderAINameReviewSheet(
                    content: target.content,
                    bookId: bookId,
                    onSave: { itemsToSave, isName, isMerge in
                        saveNamesToDictionary(itemsToSave, isName: isName, isMerge: isMerge)
                    }
                )
            }
            .sheet(isPresented: $showingBatchPromptSheet) {
                ReaderAIBatchPromptSheet(
                    settingsPrompt: nameExtractionPromptForSheet,
                    bookId: bookId,
                    chapterIndex: chapterIndex,
                    translatesChapterTitles: translatesChapterTitles,
                    convertsTraditionalToSimplified: convertsTraditionalToSimplified,
                    onStart: { prompt, fromChapterIndex, limit in
                        beginBatchExtraction(with: prompt, fromChapterIndex: fromChapterIndex, limit: limit)
                    }
                )
            }
            .onAppear {
                AIRuntimeCoordinator.shared.presentedAIBookId = bookId
                initializeSessionAsync()
            }
            .onDisappear {
                if AIRuntimeCoordinator.shared.presentedAIBookId == bookId {
                    AIRuntimeCoordinator.shared.presentedAIBookId = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: AISettingsStore.didChangeNotification)) { _ in
                reloadSettings()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openCurrentlyPlayingReader"))) { _ in
                dismiss()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("navigateReaderToPlayingChapter"))) { _ in
                dismiss()
            }
            // Chỉ trạng thái của **chính truyện này** (1.3.558) — tác vụ của truyện khác không khoá màn này.
            .onReceive(AIRuntimeCoordinator.shared.$runs) { runs in
                applyRunState(runs[bookId])
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: AIChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 32)
                AIMarkdownMessageView(content: message.content, isUser: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(red: 36/255.0, green: 44/255.0, blue: 56/255.0))
                    .cornerRadius(16)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.content
                        } label: {
                            Label("Sao chép tin nhắn", image: AppGlyph.copy.assetName)
                        }

                        if ReaderAINameReviewSheet.hasDictionaryEntries(in: message.content) {
                            Button {
                                nameReviewTarget = ReaderAINameReviewSheet.Target(content: message.content)
                            } label: {
                                Label("Thêm vào VP / Name riêng", systemImage: "tag")
                            }
                        }
                    }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if message.isStreaming && message.content.isEmpty {
                        ReaderAIThinkingIndicatorView()
                    } else if !message.content.isEmpty {
                        AIMarkdownMessageView(content: message.content, isUser: false)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(16)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = message.content
                                } label: {
                                    Label("Sao chép tin nhắn", image: AppGlyph.copy.assetName)
                                }

                                if ReaderAINameReviewSheet.hasDictionaryEntries(in: message.content) {
                                    Button {
                                        nameReviewTarget = ReaderAINameReviewSheet.Target(content: message.content)
                                    } label: {
                                        Label("Thêm vào VP / Name riêng", systemImage: "tag")
                                    }
                                }
                            }
                    } else if !message.isStreaming {
                        // Tin đã xong mà rỗng (phiên lưu trước 1.3.506): hiện rõ thay vì ẩn — ẩn là "mất tích".
                        Text("(Không có nội dung)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
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

                    // Quét tên riêng còn lượt vẫn lỗi sau vòng tự thử lại (1.3.527): nút ngay dưới đúng tin kết quả.
                    if let retry = nameScanRetry, retry.messageId == message.id, !isStreaming, !isBatchExtracting {
                        ReaderAINameScanRetryButton(failedCount: retry.failedCount) { retryFailedNameScanBatches() }
                    }
                }
                Spacer(minLength: 32)
            }
        }
        .padding(.horizontal, 12)
    }

}
