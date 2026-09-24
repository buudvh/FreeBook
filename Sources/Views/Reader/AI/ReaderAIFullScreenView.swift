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
    @State internal var showingMemorySheet: Bool = false
    @State internal var availableProfiles: [AIProviderProfile] = []
    @State internal var selectedProfileId: String = ""
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

                            ForEach(currentSession.messages) { message in
                                messageRow(message)
                                    .id(message.id)
                            }

                            // Bảng tên riêng từ Batch Extraction nếu có
                            if !batchExtractedNames.isEmpty && !isBatchExtracting {
                                ReaderAINameReviewCardView(
                                    names: $batchExtractedNames,
                                    onSave: { itemsToSave, isName, isMerge in
                                        saveNamesToDictionary(itemsToSave, isName: isName, isMerge: isMerge)
                                    },
                                    onDelete: { deletedId in
                                        batchExtractedNames.removeAll(where: { $0.id == deletedId })
                                    }
                                )
                                .padding(.horizontal, 12)
                            }

                            // Mốc neo đáy để cuộn chính xác, chống giật/đen màn hình
                            Color.clear
                                .frame(height: 1)
                                .id("bottomScrollAnchor")
                        }
                        .padding(.vertical, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: currentSession.messages.count) { _, _ in
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("bottomScrollAnchor", anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Thanh gợi ý thao tác nhanh
                ReaderAIQuickActionChipsView { actionType in
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

                        Button(action: { showingMemorySheet = true }) {
                            Image(systemName: "brain")
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
            .sheet(isPresented: $showingMemorySheet) {
                BookAIMemorySheet(bookId: bookId)
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
                AIRuntimeCoordinator.shared.isFullScreenPresented = true
                initializeSession()
            }
            .onDisappear {
                AIRuntimeCoordinator.shared.isFullScreenPresented = false
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
                    .background(Color.blue)
                    .cornerRadius(16)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.content
                        } label: {
                            Label("Sao chép tin nhắn", systemImage: "doc.on.doc")
                        }
                    }
            } else {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                    .font(.system(size: 14))
                    .padding(.top, 4)

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
                                    Label("Sao chép tin nhắn", systemImage: "doc.on.doc")
                                }
                            }
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

                    if let msgIndex = currentSession.messages.firstIndex(where: { $0.id == message.id }),
                       let extracted = currentSession.messages[msgIndex].extractedNames, !extracted.isEmpty {
                        ReaderAINameReviewCardView(
                            names: Binding(
                                get: { currentSession.messages[msgIndex].extractedNames ?? [] },
                                set: { currentSession.messages[msgIndex].extractedNames = $0 }
                            ),
                            onSave: { itemsToSave, isName, isMerge in
                                saveNamesToDictionary(itemsToSave, isName: isName, isMerge: isMerge)
                            },
                            onDelete: { deletedId in
                                currentSession.messages[msgIndex].extractedNames?.removeAll(where: { $0.id == deletedId })
                            }
                        )
                    }
                }
                Spacer(minLength: 32)
            }
        }
        .padding(.horizontal, 12)
    }
}
