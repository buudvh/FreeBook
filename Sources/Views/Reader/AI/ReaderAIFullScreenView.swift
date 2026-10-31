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
    @State private var showingOptionsMenu: Bool = false // Ngăn kéo "…"
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
    /// Tự nạp tin cũ khi cuộn lên đầu (`+OlderMessages`): chỉ bật cho đúng phiên này sau lượt cuộn-xuống-cuối ban đầu.
    @State internal var olderMessagesArmedSessionId: UUID? = nil
    @State internal var isLoadingOlderMessages: Bool = false
    @State internal var isOlderMessagesSentinelNearTop: Bool = false

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
                                // Cuộn lên gần đầu thì tự nạp tin cũ hơn (thay nút "Tải thêm tin nhắn cũ hơn")
                                if currentSession.messages.count > visibleMessageCount {
                                    olderMessagesSentinel(proxy: proxy)
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
                        .coordinateSpace(name: Self.chatScrollSpace)
                        // Mở màn / đổi phiên ⇒ chờ lượt cuộn-xuống-cuối xong rồi mới cho tự nạp tin cũ.
                        .task(id: currentSession.id) { await armOlderMessagesAutoLoad(proxy: proxy) }
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

                // Thanh gợi ý thao tác nhanh — mờ và khoá khi có lệnh AI đang chạy (chat hoặc quét); Chế độ AI của Google
                // khoá riêng "Dịch mượt raw" (chỉ tóm lược, 1.3.609)
                ReaderAIQuickActionChipsView(
                    isDisabled: isStreaming || isBatchExtracting,
                    disabledActions: isGoogleAIModeSelected ? [.translateSmoothly] : []
                ) { actionType in
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
            // Tiêu đề trái theo chuẩn trang (`PageTitleModifier`): "Trợ lý AI" 22pt đậm, tên phiên một dòng nhỏ bên dưới.
            // Màn toàn màn không vuốt đóng được ⇒ giữ nút ⌄, đứng **sau** ⋯ (ngoài cùng bên phải).
            .navigationTitle("Trợ lý AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                }

                ToolbarItem(placement: .topBarLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Trợ lý AI")
                            .font(.system(size: PageTitleModifier.fontSize, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .accessibilityAddTraits(.isHeader)
                        Text(currentSession.title)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: { showingOptionsMenu = true }) {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Tuỳ chọn Trợ lý AI")

                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.down.circle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Đóng Trợ lý AI")
                }
            }
            .sideDrawerMenu(isPresented: $showingOptionsMenu, title: "Trợ lý AI") {
                SideDrawerActionRow("Tạo phiên mới", systemImage: "plus", action: startNewChat)
                SideDrawerActionRow("Trí nhớ truyện", systemImage: "brain") { showingMemorySheet = true }
                SideDrawerActionRow("Lịch sử chat", systemImage: "clock.arrow.circlepath") { showingSessionList = true }
                SideDrawerDivider()
                SideDrawerActionRow("Cài đặt AI", systemImage: "gearshape") { showingSettings = true }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    AISettingsView(isPresentedAsSheet: true)
                }
                .presentationDragIndicator(.visible)
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
                    },
                    onDeleteName: { key in
                        removeNameLine(key: key, fromMessage: target.messageId)
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
                            ClipboardCopier.copy(message.content)
                        } label: {
                            Label("Sao chép tin nhắn", image: AppGlyph.copy.assetName)
                        }

                        if ReaderAINameReviewSheet.hasDictionaryEntries(in: message.content) {
                            Button {
                                nameReviewTarget = ReaderAINameReviewSheet.Target(content: message.content, messageId: message.id)
                            } label: {
                                Label("Thêm vào VP / Name riêng", systemImage: "tag")
                            }
                        }
                    }
            } else {
                // Tin lỗi captcha của Chế độ AI của Google (1.3.609): nền đỏ nhạt + nút xác minh ngay dưới.
                let needsVerification = !message.isStreaming && GoogleAIModeVerifyButton.applies(to: message.content)
                VStack(alignment: .leading, spacing: 8) {
                    if message.isStreaming && message.content.isEmpty {
                        ReaderAIThinkingIndicatorView()
                    } else if !message.content.isEmpty {
                        AIMarkdownMessageView(content: message.content, isUser: false)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(needsVerification ? Color.red.opacity(0.15) : Color(UIColor.secondarySystemBackground))
                            .cornerRadius(16)
                            .contextMenu {
                                Button {
                                    ClipboardCopier.copy(message.content)
                                } label: {
                                    Label("Sao chép tin nhắn", image: AppGlyph.copy.assetName)
                                }

                                if ReaderAINameReviewSheet.hasDictionaryEntries(in: message.content) {
                                    Button {
                                        nameReviewTarget = ReaderAINameReviewSheet.Target(content: message.content, messageId: message.id)
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

                    if needsVerification {
                        GoogleAIModeVerifyButton()
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
