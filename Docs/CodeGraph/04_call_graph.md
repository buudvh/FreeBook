---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 7
---

# Đồ thị Lời gọi Hàm (Call Graph)

Tài liệu này mô tả chi tiết đồ thị lời gọi hàm (Call Graph) của các phương thức cốt lõi trong hệ thống FreeBook.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Ba đường gọi mới: gộp tiền tố chương sau, tải lẻ một chương, panel Dịch (1.3.334)

```
TTSNextChapterPrefixCache.request(key:…)
  ├─ missing = chunk chưa có trong cache
  ├─ tool == "google" && missing.count >= 2
  │    └─ startGoogleBatchSynthesis(key:indices:…)          (+GoogleBatch.swift)
  │         ├─ TTSReplacementManager.applyReplacements  ← bỏ chunk rỗng SAU khi thay thế
  │         ├─ TTSSynthesisIdentity.computeKey mỗi chunk → batchKey = "gbatch|k₀|k₁|…"
  │         ├─ batchIndices.count < 2  ⇒ quay lại startSynthesis từng chunk
  │         ├─ một token cho MỌI index; tasks[index] = cùng một Task
  │         └─ Task { TTSNextChapterPrefixSynthesizer.googleBatch(…) }
  │              ├─ TTSAudioSynthesisWorker.synthesizeParagraph(synthesisKey: batchKey, …)
  │              │    └─ RemoteTTSSynthesisCoordinator  → GoogleTTSService.synthesizeBatch(parts:)
  │              ├─ TTSBatchAudioPayload.encode / .decode
  │              └─ guard audios.count == texts.count  ⇒ throw nếu lệch
  │              → finishSynthesis(index:…) cho TỪNG index (giữ 3 lớp guard cũ)
  │              → catch is CancellationError: return
  │              → catch khác: recoverBatchFailure → startSynthesis lại CHỈ chunk còn nil
  └─ còn lại: startSynthesis(key:index:…) → TTSNextChapterPrefixSynthesizer.one(…)
```

```
ReaderChapterRowView (nút mũi tên xuống)
  └─ onDownload → ReaderChapterListView.downloadChapter(_:)      (+Download.swift)
       ├─ guard canDownloadChapters (= !isLocalTXTBook && ext != nil && localBook != nil)
       ├─ guard !isPlaceholder, !isCached, url không rỗng
       ├─ downloadingChapterIndices.insert(index)   → hàng đổi sang ProgressView
       └─ Task { defer { remove(index) } }
            ├─ ChapterContentRepository.configure(container:)
            ├─ ChapterStore.fetchChapter(bookId:index:url:)   ← host của ĐÚNG hàng chương
            ├─ ChapterContentRepository.load(ChapterContentRequest(forceRefresh: false))
            │    └─ tự enqueueWrite ⇒ KHÔNG gọi ReaderViewModel.loadChapterContentFromExtension
            └─ store.markCached(index:) + toast
```

```
ReaderView: nút "Dịch" (hoặc menu bôi đen)
  └─ openDefinitionPanel()                       (ReaderView+RuleTools.swift:45)
       ├─ closeOtherSelectionPanels(except: nil)
       ├─ refreshRuleTraces()        ← chạy TRƯỚC khi hiện, để dải chip không trống một frame
       └─ showingDefinitionSheet = true
            └─ definitionPanelOverlay(in:)        (ReaderView+DefinitionPanel.swift:15)
                 └─ ReaderDefinitionOverlayView(… ruleTraces, focusedRuleTraceID,
                      isRuleFeatureEnabled, hasAnyRuleSet, onRuleAction, onAddRule)
                      ├─ ruleMeaningRowView   (chỉ đọc; ruleNoticeText khi chưa có bộ/tắt/không khớp)
                      └─ ruleChipRowView      (nút + ở ĐẦU dải, rồi ScrollView chip)
                           └─ onRuleAction(trace, ReaderRuleAction) → handleRuleAction(_:_:)
  ✕ hoặc kéo xuống ⇒ isPresented = false
       └─ .onChange(of: showingDefinitionSheet) → handleDefinitionPanelClosed()
```

* **`selectedWordOffset` đổi trong lúc panel đang mở ⇒ `refreshRuleTraces()` chạy lại**, nên dời vùng chọn sang đoạn khác là dải chip đổi theo. Đây là chỗ thay cho việc mở lại màn Check rule.
* **`ReaderView.initializeReaderIfNeeded` và `BookDetailView.task(id:)` không còn gọi `BookTitleTranslationMigrator` trực tiếp**: cả hai gọi `BookTransactionCoordinator.refreshTitleTranslations(bookId:in:)`, coordinator mới gọi `migrator.refreshTranslations(for:)` rồi tự `save()` khi `didChange`.

## Đường gọi nạp trước Google sau khi gộp request (1.3.332)

```
updatePrefetchWindow()                       (mỗi lần đổi đoạn)
  ├─ pruneRemotePrefetchTasks(keeping:)      huỷ task KHÔNG còn phục vụ index nào trong cửa sổ
  └─ dispatchRemotePrefetch(for: N+1…N+k)
       ├─ tool != "google" hoặc < 2 đoạn thiếu
       │    └─ startPrefetchTask(for:) từng index         (đường cũ, cũng là đường của Ext TTS)
       └─ tool == "google"
            └─ makeGoogleBatch(for:)   ← bỏ đoạn text rỗng, dựng khoá "gbatch|<key₀>|<key₁>…"
                 └─ startGoogleBatchPrefetch(_:)
                      └─ TTSAudioSynthesisWorker.synthesizeParagraph(synthesisKey: batch.key, …)
                           └─ RemoteTTSSynthesisCoordinator.synthesize(key:…)   ← vẫn tuần tự hoá
                                └─ GoogleTTSService.synthesizeBatch(parts:)
                                     ├─ makeRequest(textParts: [String])
                                     ├─ withRetry { audioParts(from:) }     ← retry MỘT tầng
                                     └─ TTSBatchAudioPayload.encode([Data])
                      └─ decode → preloadedData[N+1…N+k]
                           lỗi khung / lỗi mạng → fallbackToPerParagraphPrefetch(_:)
```

* **`GoogleTTSService` còn một chỗ parse duy nhất**: `audioParts(from:)` trả **mọi** blob audio theo thứ tự; `synthesize` (một đoạn) chỉ là `.first` của nó. Trước 1.3.332 parser cứng ở `.first` nên không đọc được phản hồi nhiều part.
* **Khoá coordinator của lượt gộp là chuỗi nối khoá từng đoạn**, nên hai lượt gộp trùng nội dung tự dedupe bằng đúng cơ chế cũ, không thêm bảng tra nào.
* **`makeGoogleBatch` dựng text bằng đúng đường của `startPrefetchTask`** (`TTSReplacementManager.applyReplacements` → trim). Hai đường phải cho ra cùng một chuỗi, nếu không cùng một đoạn sẽ có hai audio khác nhau tuỳ đường nào chạy.
* **Chip Check rule**: `ReaderRuleTraceChip.onLongPress` → popup → `RuleAction.moveScope(destination)` → `ReaderView.handleRuleAction` → `moveRule(_:to:)` = `QuickTranslationRuleTransfer.copy` **rồi** `deleteRule` ở phạm vi nguồn. Copy thất bại thì không xoá gì; xoá thất bại thì báo rõ "rule đang ở cả hai nơi".

## Đường gọi Ext TTS sau khi có cache script (1.3.330)

```
TTSManager.startPrefetchTask / TTSChapterPrefetcher / TTSNextChapterPrefixCache
  ├─ ExtensionManager.getTTSRuntimeFingerprint(localPath:configJson:)   ← dựng synthesisKey
  │    └─ ExtTTSScriptCache.payload(...).fingerprint          (cache hit: 2 × stat)
  └─ ExtTTSService.synthesizeData(...)      ← retry 2 lượt, MỘT tầng duy nhất
       └─ ExtensionManager.ttsGenerate(...)
            ├─ ExtTTSScriptCache.payload(...)                 (cùng cache, cùng 2 × stat)
            └─ ExtTTSRuntime.generate(..., fingerprint:)
                 ├─ Identity == requestedIdentity ?  → dùng lại JSExecutor
                 └─ khác  → cancelCurrentExecution → JSExecutor mới → injectGlobals → prepareScript
```

* **Hai lối vào cùng đi qua một cache.** Trước lượt này `getTTSRuntimeFingerprint` và `ttsGenerate` mỗi bên tự đọc `plugin.json` + `tts.js` và tự `getCombinedConfigs`, tức **cùng một kết quả được tính hai lần** cho mỗi đoạn văn. Cache miss chỉ xảy ra khi `configJson` đổi hoặc một trong hai file đổi mốc sửa.
* **`ExtTTSScriptCache.payload` gọi ngược `ExtensionManager.getScriptPath`/`getCombinedConfigs`** — cố ý, để luật tìm file script (gốc extension → `src/`) và luật trộn config (default trong `plugin.json` ← `configJson` của người dùng) vẫn chỉ có **một** bản.
* **`Identity` so fingerprint, không so nội dung.** Cùng nghĩa như trước (fingerprint băm script + config + đường dẫn) nhưng bỏ được phép so chuỗi O(len(script)) mỗi đoạn.
* **Retry vẫn đúng một tầng**: `ExtTTSService.synthesizeData` (2 lượt). Cache **không** retry; nó `throw` thẳng để lượt retry ở trên quyết định.
* `ExtensionManager.resetTTSRuntime()` gọi `ExtTTSScriptCache.invalidateAll()` **trước** `ttsRuntime.reset()` — thứ tự này để lượt tổng hợp kế tiếp không dựng lại executor bằng payload cũ.

## Đường gọi của bộ sưu tập; `EspeakPhonemizer` còn hai lối vào (1.3.328)

```
nhấn giữ một cuốn sách (Kệ sách / Lịch sử / trong bộ sưu tập)
  └─ BookActionSheet
       ├─ phần bộ sưu tập  → BookCollectionCoordinator.addBook / removeBook / createCollection
       │                      (sheet TỰ xử lý — không đi qua onAction)
       └─ mọi mục còn lại  → onAction(BookSheetAction)
            └─ ShelfView.handleBookAction / CollectionDetailView.handle
                 ├─ mở navigation/sheet của chính màn đó (chi tiết, đổi nguồn, sửa thông tin, tác vụ)
                 └─ BookActionRunner.<thân việc>
                      ├─ togglePin / addToShelf / removeFromShelfOnly / removeFromHistory
                      │    └─ BookTransactionCoordinator (setPinned / setOnShelf / removeFromShelf / setHistory)
                      ├─ removeFromCollection → BookCollectionCoordinator.removeBook
                      ├─ deleteBook           → BookStorageManager.deleteBookAsync
                      ├─ retranslateChapterTitles → ChapterStore.updateTitleTranslations
                      └─ checkNewChapters     → NewChapterInboxManager.check → showNewChapterSummary
```

* **Ranh giới "ai làm gì" là cố ý**: sheet phát *ý định*, màn gọi lo *trình bày*, `BookActionRunner` lo *thân việc*. Phần bộ sưu tập là ngoại lệ duy nhất — nó không cần navigation nào nên xử lý tại chỗ, nhờ vậy danh sách bộ cập nhật ngay trong sheet.
* **`newChapterTarget` / `checkNewChapters` / `showNewChapterSummary` nay là static của `BookActionRunner`**; `ShelfView+NewChapters` uỷ quyền vào đó. Trước lượt này chúng là method của `ShelfView` nên màn Bộ sưu tập sẽ phải có bản thứ hai — chính là lớp lỗi "hai bản chạy lệch nhau" mà repo đang tránh.
* **Bất biến "trong bộ sưu tập ⇒ trên kệ" được cưỡng chế ở tầng coordinator, không ở call site**: `addBook`/`setMemberships` gọi `promoteToShelf`; `removeFromShelf`/`setOnShelf(false)`/`addBookToShelf(isOnShelf: false)` dọn `collections` + `isPinned`. Nghĩa là không call site nào phải nhớ luật này.
* **`EspeakPhonemizer` từ ba lối vào còn hai**: `phonemize` (Piper, giọng `vi`) và `phonemizeEnglish` (đổi giọng tạm rồi trả `vi` trong `defer`). `probeVoices` đã bị xoá cùng màn Thử phiên âm — phát biểu "ba lối vào" ở mục 1.3.30x bên dưới **không còn đúng**. Bất biến giữ nguyên: mọi lối đổi giọng đều trả lại `vi` trước khi nhả lock.
* `VietnameseTokenGate` còn đúng một lối vào công khai `shouldTransliterate`; `explain` (chỉ màn đã xoá gọi) đã bị bỏ.

## Pipeline tien xu ly sau khi co cong chu so (1.3.316)

```
processVietnameseText
  |- precomposed -> cleanText -> normalizeQuotesAndDashes
  |- hasDigit = e.rangeOfCharacter(from: .decimalDigits) != nil
  |
  |- if hasDigit:  formatNumbers, processUnitsRangeAndRatio, processYearRanges,
  |                processDates, processTime
  |- processRomanNumerals            <- NGOAI cong (lam viec tren chu)
  |- if !hasDigit: tinh lai hasDigit <- vi Roman SINH RA chu so (III -> 3)
  |- if hasDigit:  processCurrency, processPercentages, processPhoneNumbers, processDecimals
  |- processUnits                    <- NGOAI cong (co nhanh so viet bang chu)
  |- if hasDigit:  VietnameseOrdinalSpeller, processDigits
  |- whitespaceCollapse -> trim
```

* **Hai buoc ngoai cong la co ly do, khong phai bo sot.** Dat chung vao cong se lam mat so La Ma va mat nhanh "hai muoi km".
* **Thu tu tinh lai co bat buoc phai o sau `processRomanNumerals`**: neu tinh mot lan duy nhat o dau, van ban chi co so La Ma se bo qua het cac buoc phia sau.

## Hai duong goi moi (1.3.313)

```
TextPreprocessor.processVietnameseText
  |- … processUnits
  |- VietnameseOrdinalSpeller.apply        <- MOI, phai dung o day
  |- processDigits                          (doc moi chu so theo so dem)

RepositoryManagerView.onAppear
  |- auditInstalledExtensions()             <- MOI, chay TRUOC refreshAllRepositories
  |    |- ExtensionInstallAudit.plan(for:)          doc dia (plugin.json con khong)
  |    |- ExtensionTransactionCoordinator.applyInstallAudit(plan:in:)
  |         |- xoa hang: mat file + khong co nguon tai lai
  |         |- xoa localPath: mat file nhung thuoc kho
  |- refreshAllRepositories()

RepositoryManagerView.uninstallExtension(ext)
  |- ExtensionManager.uninstall(localPath:)          xoa thu muc
  |- isRegisteredExtension(ext) ? updateExtensionFolder(localFolder: "")
                                : deleteExtension(packageId:)   <- MOI
```

* **Thu tu `audit` truoc `refresh` la co y**: hang da mat file ma khong co nguon tai lai chi gay loi khi kho tra ve registry, nen don truoc roi moi dong bo.

## Duong lenh cua debug server (1.3.303)

```
VS Code  --ws://host:port  (subprotocol freebook-extdebug.v1)
  |- ExtensionDebugConnection.receiveMessage
       |- ExtensionDebugServer.route
            |- ExtensionDebugCommandRouter.handle
                 |- hello                -> appVersion, contractVersion, requiresPairing
                 |- pair                 -> PairingAuthority.requestPairing -> status .waitingForApproval
                 |     (nguoi dung bam)  -> Server.approvePairing -> PairingAuthority.approvePending
                 |                          -> gui type:"paired"
                 |- [da pair]
                      |- extensions.list -> ModelContext rieng -> [ExtensionDebugInstalledSnapshot]
                      |- run.start       -> (draft? StagingStore.draftDirectory : snapshot.localPath)
                      |                     -> ExtensionDebugRunner.start -> runId
                      |- run.cancel/get  -> Runner.cancel | Hub.events(for:)
                      |- events.subscribe-> Hub.stream() -> forward tung event ra socket
                      |- draft.stage     -> StagingStore.beginStage (kiem manifest TRUOC khi nhan byte)
                      |- draft.chunk     -> StagingStore.appendChunk (chi path da khai)
                      |- draft.finish    -> finishStage (checksum) -> ExtensionDraftValidator.validate
                      |- draft.install   -> Installer.changeSummary -> InstallGate.requestApproval
                      |                     (TREO) -> nguoi dung bam -> Installer.install
                      |- draft.rollback  -> InstallGate.requestApproval -> Installer.rollback
```

* **Hai cho treo cho nguoi that**, va ca hai deu nam *sau* khi lenh da hop le: pairing va install. Do la cho duy nhat trong toan app ma mot loi goi cho vo han - nen moi duong tat may (`stop()`, client disconnect) deu phai goi `InstallGate.cancelPending()`.
* **`run.start` khong co nhanh nao nhan path.** Che do `draft` chi doi `localPath` thanh thu muc staging *do server tu resolve* tu `packageId` + `revision`.
* Duong trace giu nguyen tu 1.3.302: `JSExecutor` -> sink -> hub; `events.subscribe` chi them mot consumer cua cung `AsyncStream`.

## Hai công tắc tiêu đề chương đi qua ReaderView chứ không tự ghi (1.3.299)

```
ReaderSettingsView.Toggle "Hiển thị tên chương trong nội dung"
  └─ Binding.set(newValue)
       ├─ showChapterTitle = newValue            ← @State của ReaderView, để Toggle vẽ đúng
       └─ onShowChapterTitleChanged(newValue)
            └─ ReaderView.applyShowChapterTitle          (ReaderView+Controls)
                 ├─ UserDefaults "showChapterTitle_<bookId>"
                 └─ ReaderViewModel.invalidateParagraphLayoutForCachedChapters
                      ├─ cached.translationToken = 0     (mọi chương ≠ chương đang hiện)
                      └─ refreshParagraphItems → processAndSaveChapter → buildCancellable
```

"Loại bỏ tiêu đề chương trùng trong nội dung" đi đúng đường trên qua `applyRemoveDuplicatedTitle` và khoá `removeDuplicatedTitle_<bookId>`.

Điểm cốt lõi: `processAndSaveChapter` đọc hai cờ **từ UserDefaults**, không từ `@State`. 1.3.298 chuyển hai toggle vào `ReaderSettingsView` nhưng bind thẳng vào `@State`, nên không nhánh nào ghi khoá và không nhánh nào dựng lại đoạn — công tắc đổi được hình mà không đổi nội dung. Hai closure trên khôi phục đúng chuỗi mà `toggleChapterTitleVisibility`/`toggleRemoveDuplicatedTitle` (đã xoá) từng chạy khi hai mục còn ở menu `ellipsis`.

## "Mở Cài đặt" phải đóng Reader trước khi đổi tab (1.3.299)

```
ReaderHeaderFooterOverlayView menu ellipsis → onOpenAppSettings
  ├─ dismiss()                                   ← đóng fullScreenCover của Reader
  └─ NotificationCenter "navigateToSettingsTab"
       └─ MainTabView.onReceive → selectedTab = 3
```

Observer ở `MainTabView` đã có từ 1.3.298 và vẫn nhận đúng notification; mảnh thiếu là `dismiss()`. Reader được trình bày bằng `fullScreenCover` (`ShelfView`, `ShelfSearchView`, `BookDetailView`) nên tab đổi **bên dưới** cover và người dùng không thấy gì xảy ra.

## Bộ phân loại có hai lớp (1.3.297)

```
ForeignScriptClassifier.classify(word)
  ├─ normalize                        (lowercase, bỏ macron, bỏ dấu)
  ├─ JapaneseLoanwordList.contains    ← LỚP 1: khớp là Nhật, điểm 99, dừng
  └─ chấm điểm                        ← LỚP 2: chỉ cho từ lạ, ngưỡng 4
       ├─ có l/q/v/x        → Anh (-99)
       ├─ segment thất bại  → Anh (-99)
       ├─ đuôi -ing/-tion…  −3
       ├─ cụm th/ck/st…     −2 mỗi cụm   (đã bỏ ou/ai/ei/oi khỏi danh sách này)
       ├─ dãy nguyên âm romaji ou/uu/ai/ei/oi/aa/ii/ee/oo  **+2 mỗi cái**
       ├─ âm đặc trưng tsu/ryu/sho…  +2
       ├─ sokuon            +2
       ├─ kết thúc nguyên âm +1
       └─ 'n' làm âm tiết riêng +1
```

Lớp 1 tồn tại vì lớp 2 **không thể** tách `sakura` khỏi `sonata` — hai từ giống nhau trên mọi dấu hiệu. Ngưỡng 4 (trước là 2) vì whitelist đã gánh ca phổ biến, nên lớp 2 được phép bảo thủ và nghiêng về tiếng Anh.

Thêm hai đường đo ở `TTSIPAProbeSection`: `fillFromVietnamese` (espeak `vi` → điền ô IPA thô, ca đối chứng tự kiểm chứng) và `runSymbolDiff` (dựng hai bộ ký hiệu `vi`/`en-us` rồi lấy phần chỉ có ở `en-us`).

## Đường đo IPA thô, tách khỏi tầng phiên âm (1.3.296)

```
TTSIPAProbeSection
  ├─ "Tổng hợp & nghe"
  │    └─ ONNXPiperEngine.synthesizeRawPhonemes(ipa, ...)   ← KHÔNG qua TextPreprocessor
  │         ├─ getRuntime                (dùng lại session đã cache)
  │         ├─ ipa → scalar → phonemeIdMap
  │         │    └─ thiếu? → PiperPhonemeInventory.downgrade → đếm, không bỏ im lặng
  │         ├─ ORTSession.run            (input/input_lengths/scales[/sid])
  │         └─ WAVEncoder → AVAudioPlayer
  └─ "Đếm ký hiệu ngoài từ vựng"
       └─ Task.detached                 (24 lượt espeak là lời gọi C có khoá)
            ├─ PiperPhonemeInventory(configURL:)
            └─ EspeakPhonemizer.phonemizeEnglish × 24 → missingScalars
```

Điểm cốt lõi: đường này **không** đi qua `TextPreprocessor` hay `IPAToVietnameseMapper`, nên nó tách được lỗi của **model** khỏi lỗi của **tầng phiên âm** — thứ mà mọi đường hiện có đều trộn lẫn.

## Chốt chống rỗng và cụm phụ âm (1.3.291)

```text
transliterateToken
  ├─ lookupWord                                    → thắng
  ├─ ForeignScriptClassifier ⇒ Nhật
  │    └─ transliterateRomaji → rỗng? ⇒ trả nguyên văn token
  └─ EnglishPhonemeTransliterator.detailed
       ├─ espeak(en-us) → IPA → IPAToVietnameseMapper
       │     assemble(units) → [String]            ← trả **mảng** âm tiết
       │       ├─ leading onset ⇒ "xơ"             (cụm đầu, không còn bị bỏ)
       │       ├─ âm tiết chính ⇒ "trít"           ("tr" hợp lệ nên giữ liền)
       │       └─ phụ âm cuối thừa ⇒ **bỏ**        (1.3.305; trước là âm tiết đệm "xơ")
       └─ rỗng? ⇒ EnglishTransliterator → rỗng? ⇒ nonEmpty(fallback: token gốc)

Xoá tất cả phiên âm:
  TTSDictionaryEditView menu → showingDeleteAllConfirmation
    └─ TTSDictionaryBulkActionsModifier.deleteAll()
         ├─ await TextPreprocessor.shared.deleteAllWords()  (ghi plist rỗng, xoá cache)
         └─ await onFinished() == loadDictionary()           (nạp lại danh sách)
```

* `VietnameseTokenGate` trả `(before, after)`; cổng chỉ mở khi **cả hai** > 0.

## Đường một token đi qua tiền xử lý TTS (1.3.290)

```text
TextPreprocessor.preprocess(text)                       [actor]
  0. JapaneseTransliterator.convertToRomaji             kana → romaji (ー → bỏ, đọc như âm ngắn)
  1. replaceDictionaryWords(.acronym) → (.word)         cụm từ, thắng trước mọi thứ
  2. vòng token:
       VietnameseTokenGate.shouldTransliterate(token, at: i, in: matches, source:)
         ├─ có dấu tiếng Việt        → giữ nguyên
         ├─ không phải âm tiết Việt  → phiên âm
         └─ âm tiết mơ hồ           → phiên âm chỉ khi có láng giềng lạ (±2 token)
       └─ transliterateToken
            ├─ lookupWord (từ điển phiên âm người dùng)  → thắng
            ├─ JapaneseTransliterator.isJapaneseRomaji
            │    └─ ForeignScriptClassifier.classify     whitelist ⇒ Nhật; còn lại điểm ≥ 4 ⇒ Nhật
            │         → JapaneseTransliterator.transliterateRomaji
            └─ EnglishPhonemeTransliterator.transliterate
                 ├─ EspeakPhonemizer.phonemizeEnglish    espeak_SetVoiceByName("en-us")
                 │    └─ defer: espeak_SetVoiceByName("vi")   ← Piper luôn cần giọng vi
                 ├─ IPAToVietnameseMapper.transliterate(ipa:)
                 └─ (rỗng) → EnglishTransliterator.transliterateWord   dự phòng
```

* **Ba call site tiếng Anh** trong `transliterateToken` (nhánh có dấu `-`/`.` và nhánh thường) đều đổi sang `EnglishPhonemeTransliterator`, nên không có đường nào còn gọi thẳng bộ luật chính tả trừ chính nhánh dự phòng.
* `EspeakPhonemizer` giờ có **ba** lối vào cùng chia sẻ một `NSLock` và một cờ khởi tạo: `phonemize` (Piper, giọng `vi`), `phonemizeEnglish` (đổi giọng tạm), `probeVoices` (màn thử nghiệm). Mọi lối đổi giọng đều trả lại `vi` trước khi nhả lock.
* Màn Thử phiên âm gọi đúng các hàm trên chứ không cài lại đường nào, nên nó phản ánh pipeline thật.

## Đọc romaji Nhật: gộp trường âm phải xảy ra trước khi cắt âm tiết (1.3.305)

```text
JapaneseTransliterator.transliterateRomaji(word)
  1. normalizeRomaji                       lowercased → bỏ macron (ō→o) → fold dấu
       └─ collapseLongVowels               ou→o, ei→e, aa/ii/uu/ee/oo → âm ngắn   ← lặp tới ổn định
  2. tách sokuon                           phụ âm đôi → 1 phụ âm + ghi vị trí
  3. greedySegment                         khớp 3→2→1 tại TỪNG vị trí; nil ⇒ trả nguyên văn
  4. romajiToViSyllable                    âm tiết romaji → âm tiết Việt
  5. nhập âm tiết                           'n' → coda; 'i' sau nguyên âm → bán nguyên âm cuối
  6. gắn sokuon                            coda k→c, s/t/d/z→t, p/b→p vào âm tiết TRƯỚC
  7. joined("-")                           rỗng ⇒ trả nguyên văn token
```

* **Thứ tự bước 1 trước bước 3 là bất biến, không phải tiện tay.** `greedySegment` khớp dài nhất *tại từng vị trí*, nên với "arigatou" nó ăn `to` ở vị trí 5 rồi bỏ lại `u` thành một âm tiết `ư` thừa — khoá `"ou"`/`"uu"` trong `romajiToViSyllable` (bản 1.3.291) **không bao giờ có cơ hội khớp**. Vì thế các khoá đó đã bị xoá và việc gộp chuyển vào `collapseLongVowels`. Thêm lại khoá trường âm vào bảng là lặp lại đúng lỗi cũ.
* `ai`, `oi`, `ui`, `au` **không** nằm trong `longVowelForms`: đó là nguyên âm đôi thật ("senpai", "kaze"), gộp là mất âm. Chúng đi qua **bước 5** thay vì bước 1: âm tiết `i` đứng sau một âm tiết kết thúc bằng nguyên âm khác `i`/`y` được nhập thành một rime (`pa`+`i` → `pai`, `ko`+`i` → `kôi`, `su`+`i` → `xưi`), không đọc rời thành hai tiếng.
* **Bước 5 và bước 6 dùng chung `mergedIndexOfSyllable`.** Vị trí sokuon tính trên mảng âm tiết *romaji*, còn coda phải gắn vào ô của mảng *đã nhập*; hai mảng không còn cùng độ dài nên phải có ánh xạ. Bản cũ tính lại bằng `findMergedIndex`, hàm đó chỉ biết luật `"n"` — thêm luật nhập thứ hai mà không sửa nó là sokuon gắn lệch âm tiết.
* `ya/yi/yu/ye/yo` → `da/di/du/dê/dô`. Tiếng Việt không có chữ nào đọc đúng /j/ ở phụ âm đầu; viết bằng bán nguyên âm `i` thì espeak-vi đọc `ia` thành nguyên âm đôi /iə/ nên "Yamato" ra ba âm tiết "i-a-ma-tô". Hàng yo-on (`kya`, `ryu`, `gyo`…) **giữ** chữ `i` vì ở đó `i` là dấu ngạc hoá bên trong âm tiết.

## Dựng âm tiết Việt từ IPA: ba luật hợp lệ hoá (1.3.305)

```text
IPAToVietnameseMapper.transliterate(ipa:)
  1. lọc stressMarks
  2. tokenize                    khớp 3→2→1, ưu tiên dài nhất (tʃ, eɪ, iː không bị xé)
  3. split                       maximal onset — nhả 1 phụ âm sang âm tiết sau
       └─ nucleus là nguyên âm đôi? ⇒ nhả **toàn bộ** cụm phụ âm      ← "april" ra ây + pɹəl
  4. assemble  → [String]
       ├─ legalOnset             cụm đầu: cặp cuối hợp lệ thì giữ liền ("tr"), còn lại thành âm tiết đệm "ơ"
       ├─ ə + l/ɫ ⇒ "ồ"  |  ə + n ⇒ "ình"     rime cố định, mang dấu huyền
       ├─ nucleus nguyên âm đôi ⇒ **bỏ** coda                          ← hết âm tiết để đẩy
       ├─ legalCoda              coda hợp lệ ĐẦU TIÊN; phần thừa bị bỏ
       └─ normalize              ă/â đứng một mình → ơ; coda tắc ⇒ dấu sắc; c/k, g/gh, ng/ngh
  5. joined("-")
```

* **Ba luật này tồn tại vì bảng nguyên âm và bảng coda tra *độc lập* nhau**, nên chúng có thể ghép ra rime không tồn tại. Trước 1.3.305 nó sinh ra `ơng` ("young" → `dơng`), `âyp` ("april" → `âyp-rơn`) và mọi âm tiết đóng bằng phụ âm tắc đều **không dấu** (`trit`, `tat`) — tiếng Việt không có âm tiết nào như vậy, nên espeak-vi đọc sai hoặc bỏ qua.
* `/ʌ/` → `â` chứ không phải `ơ`: `âng âp ât âc âm ân` đều hợp lệ, `ơng` thì không.
* **Dấu chỉ cần bảng một ký tự** (`acuteVowels`). Nhờ luật "nguyên âm đôi không nhận coda", mọi âm tiết cần đánh dấu đều có nucleus là nguyên âm đơn — không phải giải bài đặt dấu trên nguyên âm đôi.
* `normalize` xét nguyên âm trước/sau trên **chữ đã bỏ dấu thanh**; so trực tiếp với `"iêe"` như bản cũ thì `ế`, `í` trượt luật `k`/`gh`/`ngh`.
* **Phần thừa ở cuối bị bỏ, không thành âm tiết đệm** ("task" → `tát`, "text" → `téc`). Đây là đảo lại `trailingFiller` của 1.3.291 theo yêu cầu người dùng — đánh đổi: mất phụ âm cuối.
* `/j/` ở **onset** → `d`; hàng `j` của bảng `codas` vẫn là `i` (bán nguyên âm cuối của `ai`, `ây`).

## Con trỏ của ô nhập mẫu đi hai chiều (1.3.289)

```text
người dùng chạm/gõ trong ô nhập
  UITextView delegate
    ├─ textViewDidChange          → parent.text = ...        (pattern)
    └─ textViewDidChangeSelection → report(): NSRange UTF-16 → chỉ số ký tự
                                     → selectionStart/selectionLength
                                     → lastReportedRange = range   (chống echo)

nút token / thanh min-max / dải chip đổi selection
  QuickTranslationRuleEditorSheet.body → updateUIView(_:context:)
    ├─ view.text != text            → coordinator.apply(text:)
    └─ view.selectedRange != wanted → coordinator.apply(selection:)
         (bỏ qua nếu wanted == lastReportedRange: đó là echo của chính mình)

selectedTokenSegment(in:)   ← QuickTranslationRuleEditorSheet+Editing
  ├─ có vùng chọn  → token trùng khít vùng chọn
  └─ chỉ có con trỏ → token có start < caret ≤ end   (chứa hoặc kết thúc tại con trỏ)
```

* `insertIntoPattern` / `applyTokenSpec` / `deleteBackwardInPattern` đều kết thúc bằng `setPattern(_:caret:)` — luôn để lại **con trỏ**, không để lại vùng chọn, nên lượt gõ tiếp theo không thay mất phần vừa chèn.
* `reconcileSelection(after:)` chỉ còn kẹp biên. Heuristic "gõ tay ⇒ con trỏ về cuối" và cờ `isProgrammaticPatternEdit` của 1.3.288 **đã bỏ**: con trỏ giờ do ô nhập cấp nên không cần đoán nguồn thay đổi nữa.

## Nhập nhanh ở màn thêm/sửa rule (1.3.288)

```text
QuickTranslationRuleEditorSheet.body
  ├─ QuickTranslationRuleDraftAnalyzer.segments(of: pattern)      → [Segment] (chip)
  ├─ QuickTranslationRuleDraftAnalyzer.analyze(pattern:replacement:)
  │     └─ RecordStore.serialize → RuleParser.parse → RuleCompiler.compile
  │           └─ RuleCompiler.parseTemplate(replacement)  (internal từ 1.3.288)
  ├─ PatternStripView   → chạm chip  → selectionStart/Length = chip.range
  │                     → chạm vạch  → selectionLength = 0
  │                     → onDeleteBackward → deleteBackwardInPattern()
  ├─ TokenPaletteView   → onInsert("<n>") → insertIntoPattern() → setPattern(caret:)
  ├─ TokenLengthBar     → onChange(spec) → applyTokenSpec()     → setPattern(caret:)
  │                        (spec đọc bằng Analyzer.tokenSpec(of: segment.text))
  └─ CaptureChipsView   → onInsert(i)   → replacement += "{i}"

setPattern(caret:) → pattern + con trỏ mới
  └─ .onChange(of: pattern) → reconcileSelection(after:)   (kẹp biên)

.onChange(of: currentDraft) → DraftStore.store(draft, for: mode.id)
init                        → DraftStore.draft(for: mode.id)  → seed @State
Hủy / submit(.success)      → DraftStore.clear(id: mode.id)
```

* **Đường Reader không đổi cạnh nào**: `onAddRule`/`.edit` vẫn set `ruleEditorMode`, `saveRuleFromEditor` vẫn là closure `onSubmit`. Chỉ `.sheet(isPresented: $showingRuleGuide)` dời từ ZStack ngoài xuống panel Check rule.
* `insertIntoPattern` **thay** vùng đang chọn khi có chọn, chèn tại con trỏ khi không — cùng một hàm cho cả hai, nên không có đường nào bỏ sót việc cập nhật vùng chọn sau khi sửa mẫu.

## Màu preparing highlight dùng chung đường active highlight (1.3.278)

```text
ReaderView effectiveHighlightRange (active ?? preparing ?? search)
  └─ ParagraphCardView(highlightIsPreparing: ...)
       └─ ReaderTextView
            ├─ backgroundColor = theme.highlightUIColor
            └─ foregroundColor = theme.highlightTextUIColor nếu có
```

* `highlightIsPreparing` vẫn nằm trong diff/equality để UIKit repaint khi chuyển preparing → active, nhưng nó không còn đổi màu. Cả hai trạng thái dùng đúng màu highlight do config/theme hiện hành cung cấp.

## Reader yêu cầu widget TTS mở rộng trước khi bắt đầu nghe (1.3.277)

```text
Reader button headphones | FloatingSelectionMenu("Nghe")
  └─ ReaderView.startTTS(at:paragraphIndex:startTextOffset:resumeIdentity:)
       ├─ chuẩn bị TTSChapterInfo + content/snapshot
       ├─ TTSFloatingWidgetWindowManager.requestRevealOnNextShow()
       │    ├─ nếu container đã tồn tại → FloatingWidgetContainerViewController.reveal(animated:)
       │    └─ nếu chưa có container → giữ cờ shouldRevealOnNextShow
       └─ TTSManager.startSpeaking(...)
            └─ showFloatingWidget = true → AppLaunchRootView refreshState → showWidget()
                 └─ consume cờ reveal nếu cần
```

* Điểm gọi nằm ở Reader, không ở `TTSManager`, vì widget là View/UI concern. `TTSManager.startSpeaking` giữ nguyên API và vẫn chỉ phát state TTS.
* Cả hai đường người dùng yêu cầu đều đi qua cùng `startTTS(...)`: nút cạnh Reader và nút "Nghe" sau khi bôi đen. Không thêm đường gọi thứ hai ở menu bôi đen.

## Luồng highlight chuẩn bị trước audio TTS (1.3.276)

```text
TTSManager.speakCurrent()
  └─ publishPreparingParagraphState(index: currentParagraphIndex)       // trước dispatch engine
       └─ playbackSnapshot = TTSPlaybackSnapshot(
            highlightRange: nil,
            preparingParentParagraphIndex: paragraphs[index].paragraphIndex,
            preparingHighlightRange: paragraphs[index].range)
            └─ ReaderTTSStateReader.updateSnapshot()
                 └─ ReaderView.chapterContentView
                      └─ effectiveHighlightRange = active ?? preparing ?? search
                           └─ ParagraphCardView → ReaderTextView(highlightIsPreparing: true)

engine audio starts
  └─ commitAudibleParagraphState(index:)
       └─ publish active highlightRange/currentParentParagraphIndex
```

* `publishPreparingParagraphState` chỉ phát state trình bày. Nó **không** gọi `saveProgress`, không update Now Playing, không chạy prefetch side effect và không thay thế `commitAudibleParagraphState`.
* Tách `preparingHighlightRange` khỏi `highlightRange` là bắt buộc: nếu publish active highlight sớm, snapshot lúc audio thật bắt đầu có thể giống hệt snapshot cũ và guard dedupe trong `commitAudibleParagraphState` bỏ qua các side effect của đoạn nghe thật.
* Reader ưu tiên vệt tô theo thứ tự **active TTS → preparing TTS → search**. Vệt chuẩn bị chỉ áp dụng cho đúng `playingBookId`, `playingChapterIndex` và `preparingParentParagraphIndex` của đoạn đang render.

## Hai lối gọi mới từ menu bôi đen của Reader (1.3.274)

> **1.3.334**: nhánh "Rule" dưới đây **không còn**. Nút đó nay là "Tìm" (`searchSelectionOnGoogle`), còn `openRuleTracePanel`/`ReaderRuleTraceOverlayView` bị thay bằng `openDefinitionPanel` + hai hàng rule trong panel Dịch — xem mục đầu tài liệu. Nhánh "Gốc" giữ nguyên.

```text
FloatingSelectionMenu ("Gốc")
  └─ ReaderFloatingMenuOverlayView.onCopyOriginal   (clear selection + đóng menu)
       └─ ReaderView.openCopyOriginalPanel()                       [+RuleTools]
            ├─ updateEditorFromSelection()                         [+Selection]
            ├─ closeOtherSelectionPanels(except: .copyOriginal)
            └─ showingCopyOriginalSheet = true
                 └─ ReaderCopyOriginalOverlayView
                      nút Copy | ✕ | kéo xuống | tap ra ngoài
                        └─ ReaderView.commitCopyOriginal()   ← MỘT đường ra duy nhất
                             └─ UIPasteboard + ToastManager

FloatingSelectionMenu ("Rule")
  └─ ReaderFloatingMenuOverlayView.onInspectRules
       └─ ReaderView.openRuleTracePanel()                          [+RuleTools]
            ├─ refreshRuleTraces()
            │    └─ QuickTranslationRuleDiagnostics.diagnose(text: originalSentence, bookId:, selection:)
            │         ├─ QuickTranslationRuleEngine.collectFound(... includesDisabled: true,
            │         │                                          notesComplexRules: false)   × 2 bộ
            │         └─ QuickTranslationRuleEngine.select(from: eligible)
            └─ ReaderRuleTraceOverlayView
                 ├─ bấm ký tự  → snapToRule(coveringCharacterAt:)  → focus + chọn cả cụm
                 ├─ bấm chip   → focus(trace)
                 ├─ ấn giữ chip→ confirmationDialog → ReaderView.handleRuleAction(_:_:)
                 │                 ├─ QuickTranslationRuleDisableStore.setDisabled(_:pattern:scope:)
                 │                 └─ QuickTranslationRule{Store|BookStore}.deleteRule(pattern:)
                 ├─ nút +      → QuickTranslationRuleEditorSheet(.add(prefilledPattern:))
                 │                 └─ ReaderView.saveRuleFromEditor(pattern:replacement:scope:)
                 └─ đóng       → ReaderView.closeRuleTracePanel()
                                   ├─ applyTranslation()   ← chỉ khi didChangeRuleData
                                   └─ checkAndReleaseDeferredTranslationRefresh()
```

* **`diagnose` bắt buộc dùng lại `select` của engine**, không cài lại 6 tiêu chí ưu tiên ở chỗ thứ hai — nếu không màn chẩn đoán sẽ nói khác kết quả dịch thật. Vì vậy `Found` / `collectFound` / `select` đổi từ `private` sang `internal`; đó là thay đổi visibility **duy nhất** ở engine.
* **`diagnose` không được ghi trạng thái**: `notesComplexRules: false` để mở màn xem không bơm `RULE_TOO_COMPLEX` vào `QuickTranslationRuleStore.status`.
* Mọi thao tác đổi dữ liệu rule bật cờ `didChangeRuleData` rồi **chẩn đoán lại ngay** để dải chip và rule thắng cập nhật tại chỗ; chỉ khi đóng sheet mới dịch lại đoạn văn.
* `checkAndReleaseDeferredTranslationRefresh()` vẫn phải gọi kể cả khi không đổi gì: một thông báo từ điển có thể đã tới trong lúc sheet mở và đang bị `isAnySelectionOrOverlayActive` giữ lại (hai cờ mới đã được thêm vào predicate đó).

## Rule dịch Quick Translate: engine, màn hình quản lý và công tắc (1.3.269)

* **Chuỗi gọi mới, chèn vào giữa chuỗi dịch cũ** (`TranslateUtils.swift`):

```text
translateMeta / translateContent / translateChapterTitle
  → translateText(_:isMeta:bookId:applyingQuickTranslationRules:)      // cache key v4, thêm q:<enabled>:<generation>
    → performTranslation(_:bookId:applyingQuickTranslationRules:)
      → QuickTranslationRuleEngine.rewrite(_:bookId:)                  // MỚI — nil khi tắt / chưa có snapshot
        → QuickTranslationRuleStore.activeSnapshot
        → QuickTranslationLiteralIndex.candidates(in:)                 // (ruleIndex, [start]) sau prefilter
        → QuickTranslationDictionaryToken.resolve(bookId:)             // 1 lần/lượt, không phải 1 lần/token
        → QuickTranslationRuleMatcher.match(_:at:)                     // AST-walk, cap 4.000 bước
        → select(from:) → assemble(selected:…)                         // sort ưu tiên → greedy non-overlap → ghép
      → punctuationMapping → VietPhraseTokenizer.tokenize → resolveTokenMeaning → postProcessText
```

* **Đường span đổi nhánh, không đổi API ngoài**: `translateContentWithMapping` / `translateChapterTitleWithMapping` gọi `translationSpansApplyingRules(source:translated:bookId:)`; hàm này chỉ rẽ sang nhánh mới khi `rewrite(...)?.didRewrite == true`, ngược lại gọi đúng `buildTranslationSpans(original:translated:bookId:)` như trước. `JSExecutor` vẫn gọi `buildTranslationSpans` trực tiếp — Qt bridge không áp rule.
* **Hai lượt `rewrite` cho cùng một chuỗi là có thật** (một lần để dịch, một lần để dựng span), nên engine memo kết quả trong `NSCache` 64 entry theo khoá `generation|bookId|md5`; lượt thứ hai là cache hit chứ không chạy lại matcher.
* **Chuỗi vô hiệu hoá**: `QuickTranslationRuleStore.apply` → `TranslateUtils.clearCache()` (đã tự gọi `QuickTranslationRuleEngine.clearCache()`) + `TranslateUtils.clearChapterTitleCache()` + `TranslationManager.notifyDictionariesDidUpdate()` — đúng **một** notification, không tạo đường refresh Reader thứ hai.
* **Điểm gọi mới ngoài phân hệ dịch**: `AppLaunchRootView.onAppear` → `Task.detached` → `QuickTranslationRuleStore.prewarm()`; `BackupConfigArchiver.restore` → `QuickTranslationRuleStore.importRules(text:)`; `QuickTranslateRuleSettingsRows.onChange` → `TranslateUtils.clearCache()` + `notifyDictionariesDidUpdate()`.

## Nhánh nhắc "chưa đăng nhập Drive" và số truyện xoá thật (1.3.268)

* **Sửa lại phát biểu của 1.3.260 ở dưới**: đường tự động sao lưu **không còn** im lặng ở mọi `.skipped`. `AutoDriveBackupOutcome.skipped` nay mang `SkipReason`, và `MainTabView.runAutoDriveBackupIfDue` hiện toast ở **ba** nhánh: `.succeeded`, `.failed`, và `.skipped(.driveNotLinked)`. Chỉ `.skipped(.notDue)` im lặng.
* **Thân `runAutoDriveBackup` tách guard cũ làm hai**: `guard GoogleDriveConfiguration.isConfigured` (build không nhúng client id → `.skipped(.notDue)`, im lặng vì người dùng không làm gì được) → `guard isDriveSignedIn` với nhánh else mới: `force` → trả `.driveNotLinked` ngay; lượt tự động thì `DriveAutoBackupPolicy.shouldWarnDriveNotLinked()` → `markDriveNotLinkedWarned()` → `.driveNotLinked`, còn ngoài cửa nhắc thì `.notDue`. Nhánh này **không** gọi `markRun()` — đăng nhập xong là lượt sao lưu chạy được ngay, không phải chờ hết cooldown.
* **Hai hàm dọn bản cũ đổi kiểu trả về**: `pruneRemoteAutoBackups()`/`pruneLocalAutoBackups()` → `(removed: Int, incomplete: Bool)`. `incomplete` gộp cả lỗi `listBackups()` và lỗi xoá từng file, chảy vào `.succeeded(…, pruneIncomplete:)`; hai call site toast đọc nó qua `AutoDriveBackupOutcome.pruneNote` (hậu tố câu chữ dùng chung cho cả đường tự động và đường bấm tay) và đổi `type` sang `.info` khi dọn chưa xong.
* **Đường dọn truyện cũ**: cạnh `StaleBookCleanupCoordinator.run` → `BookStorageManager.deleteBooksAsync(bookIds:container:)` nay **lấy giá trị trả về** (`@discardableResult ... -> Int`, số bản ghi `Book` thật sự bị `delete` + `save`). `deletedCount == 0` → `.skipped` thay vì `.deleted(count: 0)`; toast và `AppLogger` đều dùng số này chứ không dùng `staleIds.count`, vì truyện vừa được TTS phát bị loại **bên trong** `deleteBooksAsync`, không phải ở `protectedBookIds()`.

## Đường tự dọn truyện cũ và đường quy đổi số chương tuỳ chọn (1.3.263)

* **Đường tự động dọn truyện lâu không đọc** (đối xứng hoàn toàn với đường tự động sao lưu Drive của 1.3.260): `MainTabView.body.task` → [`runStaleBookCleanupIfDue(container:)`](../../Sources/Views/MainTabView.swift#L108) → `StaleBookCleanupPolicy.shouldRun()` **thoát sớm trước cả khi ngủ** → `Task.sleep(startupDelayNanoseconds)` (**40 s**, dài hơn 25 s của lượt sao lưu) → `guard !Task.isCancelled` → `StaleBookCleanupCoordinator.runIfDue(container:)` → trả `Outcome` → **một** `ToastManager.shared.show` (chỉ ở `.deleted`/`.failed`; `.skipped` im lặng). Toast nằm ở View vì `Sources/Services/**` không được gọi `ToastManager`.
* **Thân `runIfDue`**: `StaleBookCleanupPolicy.shouldRun()` (kiểm lần thứ hai, vì 40 s trước đó một lượt khác có thể đã chạy) → `StaleBookCleanupPolicy.markRun()` **trước** phần việc → `run(container:)` → `StaleBookCleanupPolicy.cutoffDate(days:)` → `protectedBookIds()` → `staleBookIds(cutoff:protectedIds:container:)` → `guard !staleIds.isEmpty` → **một** `BookStorageManager.shared.deleteBooksAsync(bookIds:container:)` → `AppLogger`. Coordinator **không** có cạnh nào tới `ModelContext.delete`, `FileManager` hay `ChapterStore`: mọi việc xoá thật vẫn nằm trong `BookStorageManager` (DB → `.bin` → ChapterStore → cover → retry queue).
* **`protectedBookIds()`** gọi đúng hai nguồn trạng thái đang chạy: `TTSManager.shared` (`isPlaying || showFloatingWidget` ⇒ lấy `playingBookId` nếu khác rỗng) và `DownloadManager.shared.tasks` (mọi task `.pending`/`.running` ⇒ `task.bookId`). `BookStorageManager` cũng tự loại truyện đang phát TTS, nên đây là lọc **dư có chủ ý** — để số đếm báo cho người dùng khớp số truyện thật sự bị xoá.
* **`staleBookIds` là nhánh duy nhất chạm SwiftData** và chạy trong `Task.detached(priority: .utility)`: `ModelContext(container)` mới + `autosaveEnabled = false` → `context.fetch(FetchDescriptor<Book>())` **toàn bảng** → lọc trên RAM ba điều kiện (`!book.isLocalBook`, `!protectedIds.contains(book.bookId)`, `book.lastReadDate < cutoff`) → `map { $0.bookId }`. Không predicate chuỗi (bộ dịch SQLite iOS 17), không dùng context của MainActor.
* **Đường bấm tay trong Cài đặt**: `StaleBookCleanupSettingsView.task` → `refreshStaleCount()` → `StaleBookCleanupCoordinator.previewStaleCount(container:)` → `cutoffDate()` + `staleBookIds(...).count` (chỉ đếm, không xoá); `.onChange(of: inactiveDays)` gọi lại đúng hàm đó. Nút "Dọn ngay" → `confirmationDialog` → `runNow()` → `StaleBookCleanupCoordinator.runNow(container:)` → `markRun()` → cùng `run(container:)` (**bỏ qua** `shouldRun()`, tức bỏ cả nhịp chờ lẫn cờ bật/tắt) → map `Outcome` sang toast → `refreshStaleCount()`.
* **Đường số chương "Tuỳ chọn"**: picker chọn `.custom` (rawValue `-1`) chỉ mở `customLimitRow`; nút −/+ và `Slider` đều đi qua `clampCustomLimit` (kẹp `1...1000`) rồi ghi `customLimit`. Lúc enqueue: `startTask()` → `effectiveLimit` → `limitOption == .custom ? ChapterLimitOption(rawValue: clampCustomLimit(customLimit)) : limitOption` → `DownloadManager.enqueueTask(book:taskType:startFromCurrent:limit:translate:onlyExportCached:container:)` → `limitRaw: limit.rawValue`. Nghĩa là sentinel `-1` **không bao giờ** đi xa hơn sheet; tầng dưới chỉ đọc `task.limit.limitValue` ([DownloadManager.swift#L333](../../Sources/Services/Download/DownloadManager.swift#L333)) và mọi số ≤ 0 ở đó đều là "không giới hạn". Đường đọc lại từ DB: `initialize(container:)` → `ChapterLimitOption(rawValue: model.limitRaw)` — không còn `?? .all` vì init của struct không thất bại.
* **Cạnh bị đổi ở hộp thư thông báo**: mục menu huỷ của `NotificationInboxView` → `deleteRead()` (thay `deleteUnread()`) → `records.filter { !$0.isRead }` → `Task { NotificationInboxStore.replace(with:) }`. Vẫn **cố ý không có** cạnh `→ ToastManager.show` sau khi xoá: `show` là choke point ghi vào chính hộp thư này nên toast xác nhận sẽ sinh ngay một thông báo chưa đọc mới.

## Đường nhảy-tô kết quả tìm, đường tự tắt cuộn và đường dọn kho (1.3.261)

* **Chọn một kết quả tìm** (thay cạnh cũ của 1.3.258, phần trước `onSelect` không đổi): `ReaderSearchView` hàng kết quả → `onSelect(chapterIndex, paragraphIndex, trimmedQuery)` → `dismiss()` → `ReaderView.jumpToReaderSearchResult(chapterIndex:paragraphIndex:query:)`. Thân hàm theo đúng thứ tự: đặt `searchHighlight = ReaderSearchMatcher.Highlight(...)` → `isAutoScrollDisabled = true` → `ttsAutoScrollGeneration += 1` → huỷ `scrollTarget` nếu nó là `.ttsAuto` → **cùng chương** ⇒ `scrollTarget = ScrollTarget(...)`, **khác chương** ⇒ `requestChapter(at:paragraphIndex:source: .chapterList, persistProgress:)` (`persistProgress = false` khi TTS đang đọc chính truyện này — TTS sở hữu tiến độ).
* **Đường tô vệt, chạy mỗi lần render đoạn**: `ReaderView.chapterContentView(for:)` → `relativeHighlightRange ?? searchHighlightRange(for:chapterIndex:isTranslationEnabled:)` → (nhánh sau) `ParagraphCardView.displayText(for:isTranslationEnabled:)` → `ReaderSearchMatcher.firstHighlightRange(of:in:)` → `ParagraphCardView(highlightRange:)` → `ReaderTextView` nhánh `isHighlightChanged` (sửa attribute trên `textStorage`, **không** gán lại text nên không mất selection). Vệt TTS đứng trước `??` nên luôn thắng; **không** có cạnh nào tới `ReaderSelectionMapper` (`mapHighlight` đã xoá ở 1.3.81). Ba `guard` của `searchHighlightRange` (`highlight != nil`, cùng `chapterIndex`, `paragraphIndex == item.id`) làm mọi đoạn khác trả `nil` ngay, không tìm chuỗi.
* **Đường tự tắt cuộn theo highlight**: ngón tay kéo → `UIPanGestureRecognizer` trên `UIScrollView` (gắn bởi `ReaderUserScrollDetector.ProbeView.didMoveToWindow` → `Coordinator.attach(to:)`) → `Coordinator.handlePan` `.changed` → `|translation.y| >= 24` **và** `!didReportForCurrentDrag` → `onUserScroll()` → `ReaderView.handleUserScrollWhilePlaying()` → 4 `guard` (`!isAutoScrollDisabled`, `isTTSPlayingThisBook`, `!isRestoringReaderPosition`, `!showingFloatingMenu`) → `isAutoScrollDisabled = true` + `ttsAutoScrollGeneration += 1` + huỷ `scrollTarget` `.ttsAuto` + `AppLogger`. **Không** cạnh tới `ToastManager.show`.
* **Vì sao cú cuộn của TTS không đi qua đường trên**: `scrollToTTSHighlightIfNeeded()`/`requestTTSScrollIfNeeded(...)` → `scrollTarget` → `ScrollViewProxy.scrollTo` là thay đổi `contentOffset` **không có ngón tay**, nên recognizer không bao giờ chuyển sang `.changed`. Đây là lý do không quan sát `contentOffset`. Chiều ngược cũng đã khoá: hai hàm đó đều `guard !isAutoScrollDisabled` nên chỉ cần đặt cờ là mọi đường auto-scroll dừng.
* **Đường dọn tiện ích kho đã gỡ** (nối vào cuối lượt đồng bộ sẵn có, cả `addNewRepository` và `refreshAllRepositories` đều đi qua): `RepositoryManagerView.syncExtensions(for:with:)` → `guard !items.isEmpty` → `ExtensionSyncCommandBuilder.build(...)` → `ExtensionTransactionCoordinator.upsertExtensions(commands:in:)` (một `save()`) → **chỉ khi `.success`** → `Set(commands.map(\.packageId))` → `PruneRepositoryExtensionsCommand` → `ExtensionTransactionCoordinator.pruneRepositoryExtensions(command:in:)` → `guard !keepPackageIds.isEmpty` → fetch `Repository` theo `url` → lọc `repo.extensions` (`localPath.isEmpty && !keep.contains(packageId)`) → `context.delete` từng ext → **một** `save()` → `AppLogger` (chỉ log khi `removed > 0`).
* **Các đường không bị đụng tới**: `installExtensionAsync` → `upsertExtension`, `uninstallExtension`/`uninstallAllExtensions` → `updateExtensionFolder(localFolder: "")`, `deleteRepository` → `ExtensionManager.uninstall` + `deleteRepository`. Prune **không** gọi `ExtensionManager.uninstall` vì tiện ích đã cài không bao giờ nằm trong tập xoá; ext import từ zip có `repository == nil` nên không nằm trong `repo.extensions`.


## Lượt tự động sao lưu Drive + hai cạnh nhỏ ở Reader/thông báo (1.3.260)

* **Đường tự động sao lưu** (không ai bấm gì, đối xứng với đường tự động kiểm tra chương mới): `MainTabView.body.task` → `MainTabView.runAutoDriveBackupIfDue(container:)` → `DriveAutoBackupPolicy.shouldRun()` **thoát sớm nếu chưa tới lượt, trước cả khi ngủ** → `Task.sleep(startupDelayNanoseconds)` → `guard !Task.isCancelled` → `BackupCoordinator.runAutoDriveBackup(container:force: false)` → trả `AutoDriveBackupOutcome` → **một** `ToastManager.shared.show` (chỉ ở `.succeeded`/`.failed`; `.skipped` im lặng). Toast nằm ở View vì `Sources/Services/Backup/**` không được gọi `ToastManager`.
* **Thân `runAutoDriveBackup`** (chỗ duy nhất có `guard !isBusy`, dùng chung khoá với các lượt thủ công): kiểm `isConfigured` + `isDriveSignedIn` → `force || DriveAutoBackupPolicy.shouldRun()` → `markRun()` **trước** phần việc nặng (nên lượt lỗi cũng không thử lại ngay ở lần khởi động kế) → `setBusy(true)` + `defer { setBusy(false) }` → `BackupExportWorker.export(...)` ra `BackupPaths.makeAutoBackupFileName()` → `GoogleDriveUploader.upload(...)` → `pruneRemoteAutoBackups()` → `pruneLocalAutoBackups()` → `refreshLocal()` + `refreshDriveFiles()` → `AppLogger`. Không có đường nào ghi SwiftData.
* **Hai hàm dọn** đều lọc `BackupPaths.isAutoBackupFileName` **trước** rồi `.dropFirst(DriveAutoBackupPolicy.maxVersions)`: remote `GoogleDriveClient.listBackups()` → `sorted { createdAt > }` → `GoogleDriveClient.delete(fileId:)`; local `LocalBackupStore.list()` (đã mới-nhất-trước) → `LocalBackupStore.delete(_:)`. Lỗi xoá từng file được log rồi bỏ qua — không làm cả lượt thất bại, và bản vừa tải lên vẫn còn nên không có gì phải rollback. Bản do người dùng tạo/đổi tên/tải lên tay không khớp tiền tố nên **không bao giờ** bị đếm hay xoá.
* **Đường chạy tay từ màn cài đặt**: `DriveAutoBackupSettingsView.runNow()` → cùng `runAutoDriveBackup(container:force: true)` (bỏ qua cả cooldown lẫn cờ bật/tắt, nhưng vẫn cần đã đăng nhập Drive và `!isBusy`) → map outcome sang toast. Không có đường sao lưu tự động thứ hai.
* **Reader**: cạnh `menu ellipsis → onOpenReaderSearch` của 1.3.258 **đổi điểm phát**, thành `nút magnifyingglass ở header → onOpenReaderSearch`; phần sau (`.sheet { ReaderSearchView }` → `ReaderSearchMatcher.search` → `onSelect`) không đổi.
* **Trung tâm thông báo**: chạm một hàng toast → `NotificationInboxManager.markRead(record)` → `guard` bỏ qua nếu đã đọc → `Task { NotificationInboxStore.replace(with:) }` (không ghi đĩa khi không đổi gì). Mục menu huỷ → `deleteUnread()` → giữ lại phần `isRead` → `replace`. **Cố ý không có** cạnh `→ ToastManager.show` sau khi xoá: `show` lại gọi `NotificationInboxManager.record` nên sẽ sinh ngay một thông báo chưa đọc mới.
* **Khởi động**: `FreeBookApp.init()` → `NavigationBarAppearance.applyTitlelessBackButton()` (một lần, cạnh hai lời gọi `UITabBar.appearance()`). Không View nào gọi hàm này.

## Tìm trong Reader + choke point ghi thông báo (1.3.258)

* **Gỡ đồ thị tìm toàn văn 1.3.257**: mọi cạnh tới `ChapterSearchIndex.shared.*` bị cắt tại các owner (`ChapterPersistenceStore`, `ShelfView+BookImport`, `BackupChapterRestorer`, `ExportContentProvider`, 3 chỗ `removeBook` trong `BookStorageManager`) — logic quanh nó giữ nguyên, chỉ xoá lời gọi phái sinh.
* **Đường tìm trong Reader** (thuần RAM, không cạnh nào tới đĩa/mạng): menu `ellipsis` → `onOpenReaderSearch` → `ReaderView` present `.sheet { ReaderSearchView }`. Dữ liệu dựng **một** snapshot từ `ReaderViewModel.cache.cache` (chỉ chương `state == .loaded`) → `[ReaderSearchMatcher.Chapter]`. Gõ (debounce 250ms) → `ReaderSearchMatcher.search(query:in:maxHits:)` (khớp `translated` trước rồi `original`, 1 `Hit`/đoạn). Chọn kết quả → `onSelect(chapterIndex, paragraphIndex)`: cùng chương ⇒ `scrollTarget = ScrollTarget(...)`, khác chương ⇒ `requestChapter(at:paragraphIndex:source: .chapterList)` (tái dùng đúng cơ chế danh sách chương/TTS-sync).
* **Choke point ghi thông báo**: `ToastManager.show(message:type:)` gọi `NotificationInboxManager.shared.record(message:type:)` ở dòng đầu ⇒ **mọi** toast (info/success/error) đều vào log. `record` append vào `@Published records` rồi `Task` ghi qua `NotificationInboxStore` (actor, `.atomic`, cap 200). Cạnh preload: `MainTabView` startup Task → `NotificationInboxManager.shared.loadIfNeeded()`; badge đọc `unreadCount` + `NewChapterInboxManager.totalNewBooks`.

## Ba đường kiểm tra chương mới (1.3.256)

* **Đường tự động** (không ai bấm gì): `ShelfView.body.task` → `ShelfView.runAutoNewChapterCheck()` → `NewChapterInboxManager.loadIfNeeded()` (→ `NewChapterStore.all()`, chỉ đọc đĩa lượt đầu) → `prune(keeping: Set(allBooks.map(\.bookId)))` → `newChapterTargets` (`allBooks` đã sort `lastReadDate` giảm dần) → `autoCheck(targets:)` → `NewChapterCheckPolicy.shouldRunBatch()` **thoát sớm nếu chưa tới lượt** → lọc `shouldCheck(record:)` → `prefix(maxBooksPerBatch)` → `run(_:)`.
* **Đường refresh toàn bộ**: menu toolbar `"Kiểm tra chương mới"` → `ShelfView.checkAllNewChapters()` → `checkAll(targets:)` → `run(_:)`. Khác đường tự động ở đúng hai điểm: **không** hỏi `shouldRunBatch`/`shouldCheck`, và `announceEmpty: true` nên "Không có chương mới" cũng được báo.
* **Đường refresh một truyện**: context menu trên dòng truyện → `ShelfView.checkNewChapters(for: book)` → `newChapterTarget(for:)` (`nil` ⇒ toast lỗi, dừng) → `check(target:)` → `run([target])`.
* **Thân chung `run(_:)`** (chỗ duy nhất có `guard !isChecking`): với **từng** target tuần tự → `NewChapterProbe.probe(target:previous:)` → gom `Outcome` → cộng `BatchSummary` → `Task.sleep(interBookDelayNanoseconds)` giữa hai truyện → `NewChapterStore.save(batch)` **một** lượt ghi file → `NewChapterCheckPolicy.markBatchRun()` → trả `BatchSummary` → `ShelfView.showNewChapterSummary(_:announceEmpty:)` → **một** `ToastManager.shared.show`.
* **Bên trong `probe`** (nhánh gọi sâu nhất): `fetchTOC` → `BookDetailLoader.fetchFirstPageTOC` → *nếu* `pages.count > 1`: `≤ maxTOCPagesPerCheck` ⇒ `fetchRemainingPages` (`isPartial = false`), ngược lại ⇒ `fetchPageTOC(url: pages.last!)` (`isPartial = true`) → `dedupePreservingOrder` → `resolveBaseline` (mốc rỗng ⇒ `ChapterStore.fetchOrderedTOC(bookId:)`) → `applyDiff`. Không có cạnh nào tới hàm tải nội dung chương.
* **Đường tắt badge**: chạm dòng truyện → `NewChapterInboxManager.markSeen(bookId:)` → `NewChapterRecord.markSeen()` → `NewChapterStore.save(record)`; `!hasNew` thì thoát ngay, **không** ghi đĩa. Cạnh đọc: `MainTabView` và `NewChapterSettingsView` → `newChapters.totalNewBooks` (Combine, không có lời gọi nào ngược lại).

## Một tác vụ xuất: lấy chương → render → kiểm file → chia sẻ (1.3.253)

* **Enqueue**: `ShelfView.prepareTaskForBook(book, type: .exportTxt)` / `BookDetailView.prepareForTask(taskType: .exportTxt)` (chỉ để mở sheet) → `TaskOptionsSheet` → người dùng chọn `BookExportFormat` → `effectiveTaskType` = `format.taskType` → [`DownloadManager.enqueueTask(book:taskType:startFromCurrent:limit:translate:onlyExportCached:container:)`](../../Sources/Services/Download/DownloadManager.swift#L1). Cạnh cũ `DownloadTrackerView.exportFromCached → enqueueTask(.exportTxt)` **bị xoá** — nó đi qua sheet để chọn định dạng và thấy trước số chương thiếu (`ChapterStore.fetchOrderedTOC` → đếm `isCached && length > 0`).
* **Thân tác vụ** (`processTask`): `task.taskType.exportFormat` ≠ nil ⇒ `ExportRendererFactory.makeRenderer(for: BookExportRequest)` → một trong `TxtExportRenderer`/`EpubExportRenderer`/`Fb2ExportRenderer`/`MobiExportRenderer`. Mỗi chương: `ExportContentProvider.acquire(chapter:)` → (`BookBinManager.readChapterContent` **hoặc** `BookDownloadWorker.fetchChapterContent` → `String.cleanHTML()` → `BookBinManager.writeChapterContent` → `ChapterStore.upsertCachedChapter`) → nếu bật dịch thì `TranslateUtils` → `renderer.append(ExportChapterPayload)`. **Không** còn vòng thứ hai đọc lại `.bin` sau khi tải: đúng một lượt lấy chương phục vụ cả cache và bản xuất, và `ExportContentProvider` là cạnh dùng chung với tác vụ `Tải truyện`.
* **Kết thúc**: `renderer.finish()` → `ExportArtifact` → `guard artifact.exists` (không thì `throw .cannotCreateFile`) → `DownloadTaskOutcomeCalculator.exportSummary(plannedCount:renderedChapterCount:skippedUncachedCount:failedCount:)` → `markExportCompleted(taskId:artifact:summary:)` → `markCompleted` (ghi `exportFilePath` + `save()`) → `exportStage = .readyToShare` → `DownloadPresentationEventCenter.send(.showToast)` (chỉ khi thiếu chương) + `.send(.exportReady(filePath:bookTitle:))`.
* **Nhánh chia sẻ**: `.exportReady` → `AppLaunchRootView` (`for await` trên `DownloadPresentationEventCenter.stream`) → `ExportShareCoordinator.requestShare(filePath:bookTitle:)` → `UIActivityViewController`. Không tìm được VC đang hiển thị ⇒ giữ pending → `MainTabView.onChange(of: scenePhase)` (`.active`) → `flushPendingShare()`. Cạnh cũ `DownloadManager.presentShareSheet → UIApplication.shared.connectedScenes` **bị xoá** cùng `import UIKit`.
* **Nhánh lỗi/huỷ**: mọi đường thoát đi qua `renderer?.discard()` (renderer khai ngoài `do` nên `catch` với tới được) → `markFailed`/`markCancelled`. Renderer không có nội dung nào ⇒ `finish()` `throw .emptyExport`; `DownloadTaskOutcomeCalculator.calculateOutcome(isExport: true, …)` cho `.failed` khi `renderedChapterCount == 0`, còn > 0 chương ⇒ `.completed` **kèm** dòng tổng kết. Không có đường nào báo hoàn thành mà không có file trên đĩa.
* **Bên trong MOBI** (nhánh gọi sâu nhất): `append` → `ExportStagingFile(text)` … `finish()` → `commit()` file text tạm → `MobiHeaderBuilder.record0(...)` → `ExportStagingFile(.mobi)` → `copyTextRecords` (mỗi 4096 byte: `PalmDOC` record + vá `filepos` 10 chữ số) → `commit()` → `defer` xoá file tạm.

## Nhập truyện đa định dạng call graph (1.3.251)

* Chọn file → `ShelfView.importLocalBook(from:)` copy sang `temporaryDirectory/<uuid>.<ext>` (giữ đúng đuôi gốc) → bật `isParsingImport` → `Task.detached` → [`BookImportService.parse(_:)`](../../Sources/Services/Import/BookImportService.swift#L1) → `MainActor` gán `pendingImport` → `BookImportConfirmationSheet`.
* Bên trong `BookImportService.parse`: `BookImportFormat.detect(fileName:data:)` → **một** trong bốn nhánh:
  * `.txt` → `TextEncodingDecoder.decode` (hoặc `encodingOverride`) → `TxtBookParser.parse`.
  * `.html` → `TextEncodingDecoder.decodeDeclared` theo `XhtmlTextExtractor.declaredCharsetName(in:)` → `HtmlBookParser.parse` → `<mbp:pagebreak>` ≥ 2 mảnh → `XhtmlTextExtractor.headingSections` ≥ 2 → `XhtmlTextExtractor.plainText` + `TxtBookParser.parse` → 1 chương.
  * `.epub` → `EpubArchiveReader.read(fileUrl:)` (`BackupZipArchive.extract` → `container.xml` → OPF) → `EpubOpfParser.parse(opfURL:)` → `EpubNavParser.parseNcx(data:)`/`parseNav(html:)` → `EpubBookParser` chọn `tocIndex` (nhiều `Entry` cùng file có `fragment` → `XhtmlTextExtractor.anchorSegments`) → `spine` → `tocRules` (`TxtBookParser`).
  * `.mobi` → `MobiArchiveReader.read` (PalmDB → PalmDOC → MOBI → EXTH; `encryptionType != 0` ⇒ `throw .drmProtected`, HUFF/CDIC ⇒ `throw .unsupportedCompression`) → mỗi record `PalmDocDecompressor.stripTrailingEntries` + `decompress` → `MobiBookParser` decode theo codepage → `HtmlBookParser.parse`.
* "Phân tích lại" trên sheet → `ShelfView.reanalyzeImport(decodeID:ruleIDs:structure:tempFileUrl:fileName:)` → **cùng** `BookImportService.parse` với `Request` mang lựa chọn người dùng → `Result` cập nhật `parsed`/`autoDecodeID`/`matchedRuleIDs` của sheet. Không có đường parse thứ hai.
* "Nhập" → `performImport(parsed:fileName:tempFileUrl:)` giữ nguyên chuỗi ghi cũ, chỉ thêm một nhánh bìa: `parsed.coverData` → `ImageCacheManager.shared.saveCover(data:for:)` (giữ `coverUrl` rỗng), ngược lại `parsed.remoteCoverUrl` → `AddBookToShelfCommand.coverUrl`.
* Nhánh lỗi: `BookImportService.ImportError` → `catch` ở `importLocalBook` → xoá file tạm → tắt `isParsingImport` → `AppLogger` + `ToastManager.show(error.localizedDescription)`. Sách rỗng **không** được tạo vì mọi lỗi xảy ra trước `addBookToShelf`.

## Đường sửa từ điển, cập nhật mục lục và xuất TXT (1.3.250)

* **Sửa một từ (global)**: `ReaderDefinitionOverlayView.updateButtonView` → `onSaveDefinition` → `ReaderView.saveDefinition` → `TranslationManager.saveCustomEntry(word:meaning:isName:bookId: nil)` → `DictionaryTextFileStore.persist` → `DictionaryCache.invalidate` → **`reloadCustomDictionary(isName:)`** → `updateDeletedState` → `notifyDictionariesDidUpdate(bookId:scope:)` → `TranslateUtils.invalidateCache` → `.translationDictionariesDidUpdate` → `ReaderView.onReceive` → `scheduleCoalescedTranslationRefresh` → (150 ms) → `updateCachedTranslatedContent` → `refreshParagraphItems()`. Cạnh `loadAllDictionaries()` (→ 4× `DoubleArrayTrie.load` → `loadPhoneticMap` → `ChinesePhienAmWords.txt`) **đã bị xoá** khỏi đường này; nó chỉ còn ở khởi động, tải/thay từ điển chung và khôi phục backup.
* **Sửa một từ (riêng truyện)**: cùng đường nhưng nhánh `bookId != nil` chỉ còn cạnh `bookDicts.removeValue(forKey:)`; việc nạp lại đi đường lazy `getBookDictionaries(bookId:)` ở lần dịch kế tiếp. Không có cạnh reload nào.
* **Bỏ đường gọi kép**: `saveDefinition` không còn hai cạnh `→ updateCachedTranslatedContent` (gọi thẳng) và `→ scheduleCoalescedTranslationRefresh` (tường minh). Còn lại `→ applyTranslation()` → `→ checkAndReleaseDeferredTranslationRefresh()`, tức nếu notification tới **trước** khi overlay đóng (bị defer) thì cạnh này bung ra, còn nếu tới **sau** thì `.onReceive` schedule luôn. Cả hai thứ tự cho đúng **một** lần dựng lại chương.
* **Gợi ý ở ô nghĩa**: cạnh `body → suggestionChips` (computed, ~6× `findLongestMatch` + `getHanViet` mỗi lần evaluate) đổi thành cạnh **theo sự kiện**: `updateEditorFromSelection` / nhánh xoá định nghĩa / `onGetDictionaryMatches` → `refreshSuggestionChips(for:)` → `ReaderView.buildSuggestionChips(for:bookId:)` → `ReaderSelectionCoordinator.shared.getHanViet(for:)`, ghi vào `@State suggestionChips`. `ReaderDefinitionOverlayView` gọi `onGetDictionaryMatches` từ `ManageDefinitionsView(onChanged:)` — một *event*, không phải trong `body`.
* **Cập nhật mục lục**: `ChapterStoreDatabase.replaceFullTOC`/`upsertPage` → `fetchOrderedTOC` (một lần duy nhất) → **`ChapterTOCDiff.plan(existing:incoming:protectedTTS:bookId:)`** → rẽ ba: `.unchanged` trả về **trước** khi mở transaction, `.appendOnly(tailStart:)` chỉ `REPLACE` từ `tailStart` và bỏ cạnh pass xoá stale, `.full` như cũ. Cạnh `→ fetchOrderedTOC` **lần hai** và cạnh `→ computeDeterministicChecksum` → `fnv1aUpdate` bị xoá, thay bằng `→ countChapters(bookId:)` (`SELECT COUNT(*)`).
* **Caller mục lục**: `ReaderChapterListView+Refresh` không còn cạnh `→ fetchOrderedTOC` để tự so sánh; nó gọi `→ ChapterContentRepository.saveChapterList` rồi **đọc** `SaveTOCResult` (`inserted/updated/deleted == 0` ⇒ toast "Mục lục đã mới nhất"). `readerOldUrl` lấy qua `→ fetchRange(bookId:startIndex:count: 1)`. `BookDetailView+Extensions.reloadBookData` gom 4 cạnh `await MainActor.run` thành một và chỉ giữ cạnh `→ updateBookMetadata` khi field thật khác, `→ refreshLocalTOCSnapshots()` khi `didChangeTOC`. `fetchCountAndChecksum` bị thay bằng `countChapters` ở cả ba caller: `BackupChapterRestorer`, `BookDetailView+TOCPreparation`, `ReaderView`.
* **Xuất TXT**: mỗi chương trước đây đi `updateProgress → updateTaskInDB → ModelContext(container) → fetch(FetchDescriptor<DownloadTaskModel>()) → save()`. Nay `updateProgress` → `updateTaskInDB(taskId:coalesce:)` → `taskStoreContext()` (một context dùng lại) → `fetchTaskModel(taskId:in:)` (predicate theo `id` + `fetchLimit = 1`) → `save()` **chỉ khi** hết cửa sổ coalesce. Cạnh hop MainActor chỉ để hỏi cancel bị xoá (`Task.isCancelled` là đủ vì mọi đường huỷ đều `handle.cancel()`).
* **Ghi file TXT**: cạnh `txtAccumulator += …` → một lần `write` ở cuối đổi thành `TxtExportFileWriter.append(_:)` mỗi chương → `finish()` (rename `.txt.part` → `.txt`) ở nhánh thành công, `discard()` ở **mọi** nhánh huỷ/lỗi trước `markFailed`/`markCancelled`. `BookBinManager.readChapterContent` → `binFilePath(for:)` (2× `sha256Hex`, 2× `validatePathSafety`, `migrateLegacyFileIfNecessary`) nay đi qua `resolvedBinURL(for:)` với cache `resolvedBinURLs`, nên cả vòng lặp chỉ trả giá một lần; `deleteBinFile` xoá entry cache.
* **Sửa thông tin truyện**: cạnh `BookDetailView.ellipsisMenu → showingEditInfo → .sheet → BookInfoEditView` và `onDismiss → refreshDisplayedBookInfo()` **đã bị xoá**. Đường mới: `ShelfView` (context menu của **cả** tab Kệ sách và Lịch sử) → `editingInfoBook = book` → **một** `.sheet(item:)` → `BookInfoEditView(bookId:title:author:coverUrl:)` → `BookTransactionCoordinator.updateBookInfo`; cập nhật hiển thị đi đường `@Query`, không còn cạnh refresh tay nào.

## Đường copy từ điển và đường dựng widget trình duyệt (1.3.244)

* Đường copy (8 tổ hợp, **hai** đích cuối): `DictionaryHubView` (chủ `bookId`) → `DictionaryListView(type:bookId:contextBookId:)` → `DictionaryEntryRow` (Menu) → `onTransfer(destinationType, target)` → `DictionaryListView.copyEntry(_:to:target:)` (`+Transfer`) → `DictionaryEntryTransferAction.copy(...)` → **hoặc** `DictionaryCache.shared.upsertEntry(key:value:type:)` (đích chung custom) **hoặc** `TranslationManager.shared.saveCustomEntry(word:meaning:isName:bookId:)` (đích riêng). Không có cạnh nào tới bộ nạp `.dat` — đường ghi built-in **không tồn tại** trong đồ thị.
* `transferContextBookId` là `bookId ?? contextBookId`: ở danh sách riêng thì chính scope của nó, ở danh sách chung thì sách đang mở màn Từ điển. Khi cả hai `nil` (không thể xác định sách), `DictionaryEntryRow` gọi `onMissingContext()` → `reportMissingTransferContext()` → toast lỗi, **không** phát cạnh nào tới tầng ghi. Không có cạnh nào tới book picker, tới `TTSManager` hay tới "sách mở gần nhất".
* Đường tìm kiếm truyện đích: `BookShareTargetSheet` → `BookSearchBarView` (`@Binding searchQuery`) → computed `filteredBooks` → `ShelfBookSearchMatcher.matches(query:title:titleTrans:author:authorTrans:)`. Cạnh này là *thêm mới* trước `List`, không chen vào đường chọn đích (`dictionaryModeDialog` → callback cũ) — đường chọn đích không đổi chữ nào.
* `ShelfSearchView.searchBarView` nay chỉ còn một cạnh: `→ BookSearchBarView(text:onCommit:)`, với `onCommit` giữ nguyên `SearchHistoryStore.addQuery(_:to:)`.
* Đường mở trình duyệt: `VisibleBrowserTabManager.openTab(...)` → `openContainer(initialActiveId:)` → **rẽ theo `VisibleBrowserSettings.opensMinimized`**: `presentContainerView(initialActiveId:)` (như cũ) hoặc `prepareContainerMinimized()` → `TabbedVisibleBrowserViewController.loadViewIfNeeded()` → `viewDidLoad` → `reloadTabs()` → `displayChildViewController(activeItem.loader.viewController)`. Nhánh thu nhỏ **không** gọi `present(_:animated:)` ở đâu cả. `dismissContainer()` ở nhánh re-present cũng đi qua `openContainer(initialActiveId:)` nên tôn trọng cùng cài đặt.
* Đường nháy: `VisibleBrowserTabManager.notifyStateChanged()` → `stateDidChangeNotification` → `VisibleBrowserPulseMonitor.evaluate()` → `setPulsing(_:)` → `@Published isPulsing` → `VisibleBrowserReopenButton.onChange` → `isDimmed` → `.opacity`. `evaluate()` chỉ tự gọi lại qua **một** `Timer` one-shot hẹn đúng phần thời gian còn thiếu tới 10 s; không có cạnh polling nào.
* Đường hiện/ẩn window widget: cùng notification → `BrowserFloatingWidgetWindowManager.refreshState()` → `showWidget()`/`hideWidget()`; thêm ba cạnh từ `AppLaunchRootView` (`.onAppear`, `onChange(of: translationManager.isInitialized)`, `onChange(of: browserPresentation.snapshot.showReopenButton)`). Cạnh cũ `AppLaunchRootView → VisibleBrowserReopenButton` (trong `ZStack`, `zIndex(9998)`) **đã bị xoá** — widget không còn nằm trong cây view của app.
* Đường kéo/thả: `UIPanGestureRecognizer → BrowserFloatingWidgetContainerViewController.handlePan` → ghi `widgetContainerView.center` trực tiếp (`.changed`), rồi `.ended` → `VisibleBrowserReopenViewModel.handleDragEnd(...)` → `FloatingWidgetGeometry.nearestEdge/clampedCenterY` → `updateLayout(animated: true)`. `UITapGestureRecognizer → handleTap` → `VisibleBrowserTabManager.reopenContainer()`, guard `!viewModel.isDragging`; `shouldRecognizeSimultaneouslyWith` trả `false` nên tap và pan không cùng nổ.
* TTS widget: `FloatingWidgetViewModel.handleDragEnd` và `FloatingWidgetContainerViewController.restingCenter/clampedY` đổi **nội dung** sang gọi `FloatingWidgetGeometry.*`; tập cạnh vào/ra của hai type này không đổi và công thức tương đương từng phép toán.

## Cạnh invalidate bị thiếu giữa `ReaderViewModel` và `ReaderView` (1.3.243)

* Trước 1.3.243 **không có** cạnh nào từ `ReaderViewModel.objectWillChange` về `ReaderView`. `ReaderViewModel` là `ObservableObject` nhưng `ReaderView` giữ nó ở `@State` (`ReaderView.swift:196`), mà `@State` chỉ lưu tham chiếu — nó không subscribe publisher. Vì vậy `pendingNavigationIndex`, `navigationCommit`, `loadState`, `navigationFailure` đổi giá trị mà **không** kích hoạt update pass nào.
* Hệ quả trên đồ thị gọi: `ReaderView.nextChapter/prevChapter → requestChapter → (pendingNavigationIndex = N)` là một nhánh **chết ở giữa** — không dẫn tới `singleChapterReaderView` cho tới khi một nguồn invalidate *khác* nổ: `ttsState` (`@StateObject`) publish, một `@State` khác của `ReaderView` đổi, một trong bốn `.onReceive` NotificationCenter, hoặc `@Query`. Log thiết bị 2026-08-22 đo khoảng chờ đó là 0.6–4.3 s.
* Cùng lý do: `.onChange(of: vm.navigationCommit)` (→ `applyNavigationCommit`) chỉ được so sánh trong một update pass, nên nó cũng chờ chung sự kiện vô can đó. Dòng `[ReaderPerf] NavRealize reason=commit` **không** chứng minh có pass — nó phát từ `ReaderViewModel.commitNavigation` (`ReaderViewModel.swift:672`), không phải từ view.
* Cạnh mới: `ReaderViewModel.objectWillChange → ReaderViewModelInvalidationRelay.objectWillChange → ReaderView` (`@StateObject`). Đăng ký tại `ensureViewModel` ngay sau `viewModel = newViewModel`, huỷ tại `.onDisappear`. Không lọc theo thuộc tính: mọi `@Published` của view model nay đều invalidate Reader, đúng như `@ObservedObject` sẽ làm.
* Không cạnh nào khác đổi: cổng bắt tay skeleton (1.3.242), `scheduleDeepLandingScroll`, nhịp chờ 32 ms, `ReaderScrollCoordinator` giữ nguyên — chúng chỉ *bây giờ mới* chạy đúng nhịp vì đã có pass để chạy.

## Cổng bắt tay skeleton nằm giữa hai subtree chương (1.3.242)

* Cạnh mới trong render gate của `singleChapterReaderView`: `ZStack → ReaderView.isChapterSubtreeRenderable(_:)` (khai ở `ReaderView+LoadingView.swift`). Nhánh `singleChapterScrollView` chỉ được chọn khi hàm này trả `true`; ngược lại đi nhánh `chapterInlineLoadingView`.
* `chapterInlineLoadingView.onAppear` nay có **hai** việc: ghi `skeletonHandshakeIndex = index` (cạnh dữ liệu nuôi cổng ở trên) rồi mới `recordSkeletonPresented(index:)`. `singleChapterScrollView.onAppear` cũng thêm `renderedChapterIndex = chapter.index` trước `recordChapterPresented(index:)`.
* Hai nhánh skeleton cũ (`pendingNavigationIndex != displayedChapterIndex` và fallback "chưa loaded") **gộp thành một** nhánh `else`, mang `.id("chapter-skeleton-\(presentationIndex)")` để đổi chương liên tiếp vẫn tạo cạnh `onAppear` mới.
* Không cạnh nào ở `ReaderViewModel`, `ReaderScrollCoordinator` hay `ReaderEnergyDiagnostics` đổi; nhịp chờ 32 ms và `scheduleDeepLandingScroll` giữ nguyên.

## Next/Prev nhập vào cùng một cửa với danh sách chương (1.3.241)

* Cạnh gọi `stepChapterHonoringTTS → ReaderViewModel.stepChapter` và `→ ReaderViewModel.requestChapter` **không còn**. Thay bằng một cạnh duy nhất: `nextChapter/prevChapter → stepChapterHonoringTTS → ReaderView.requestChapter(at:…) → ReaderViewModel.requestChapter(index:…)`. `ReaderViewModel.stepChapter` đã xoá khỏi `Sources/` (không còn caller nào).
* `ReaderView.requestChapter(at:…)` nay là điểm hợp lưu của **cả bốn** đường: `.nextButton`, `.previousButton`, `.chapterList`, `.ttsSync` (cả notification `navigateReaderToPlayingChapter`). Nó cũng là nơi phát `ReaderEnergyDiagnostics.recordNavigationTap(index:source:)`.
* Cạnh mới ở đường hạ cánh: `applyNavigationCommit → scheduleDeepLandingScroll` (trong `ReaderView+Controls.swift`) → `DispatchQueue.main.asyncAfter(0.15)` → ghi `scrollTarget` → `.onChange(of: scrollTarget)` → `attemptScroll → ReaderScrollCoordinator.attemptScroll`. Coordinator không đổi chữ nào.
* Hai cạnh instrumentation mới: `chapterInlineLoadingView.onAppear → recordSkeletonPresented(index:)` và `singleChapterScrollView.onAppear → recordChapterPresented(index:)`.

## Đường Next/Prev khi TTS đang phát & log `[ReaderPerf]` (1.3.240)

* `nextChapter()`/`prevChapter()` của `ReaderView` không còn gọi `viewModel?.stepChapter(by:)` trực tiếp: cả hai rút về một dòng gọi `stepChapterHonoringTTS(by:source:)` ở `ReaderView+Controls.swift`. Helper clamp chỉ số đích như cũ, nhưng khi chương đích **đúng là chương TTS đang phát của sách này** (`snapshot.isPlaying`, `playingBookId == bookId`, `playingChapterIndex == target`, `currentParentParagraphIndex >= 0`, `!isAutoScrollDisabled`) thì gọi thẳng `viewModel?.requestChapter(index:paragraphIndex:source:persistProgress:)` với đoạn TTS đang đọc; mọi trường hợp còn lại vẫn đi `stepChapter` (tức `paragraphIndex: -1`). `stepChapter` không đổi vì còn phục vụ đường khác.
* Hệ quả trên `ReaderScrollCoordinator.attemptScroll`: target hạ cánh mang `paragraphIndex >= 0` nên nó chọn neo `paragraph-N-P` (`anchor: .center`) ngay lượt dựng đầu tiên, thay vì `chapter-N` (`.top`) rồi vài giây sau bị `requestTTSScrollIfNeeded` bắn thêm một cú `scrollTo` sâu thứ hai.
* Đường commit RAM đổi hình dạng: `requestChapter` → (hit cache) → `memoryCommitTask = Task { @MainActor … await Task.yield() … commitNavigation(request, origin: .memory) }`, tức `commitNavigation` không còn nằm trong stack của cú bấm.
* Bốn call site log mới, tất cả sau cổng cờ đã latch (không đọc `UserDefaults` trên hot path):
  - `ReaderViewModel.commitNavigation` → `[ReaderPerf] Nav index=… paragraph=… origin=… source=… commitMs=…`, mốc bắt đầu đặt ở đầu `requestChapter`.
  - `ReaderViewModel.loadChapterContentFromExtension` → `[ReaderPerf] RepoLoad index=… origin=… ms=…` quanh `ChapterContentRepository.shared.load`.
  - `ReaderScrollCoordinator.attemptScroll` → `ReaderEnergyDiagnostics.recordScrollAttempt` → `[ReaderPerf] Scroll chapter=… paragraph=… reason=… anchor=…`.
  - `.onAppear` của card đoạn trong `ReaderView` → `recordParagraphRealized()`, in ra ở lần commit kế tiếp dưới dạng `[ReaderPerf] NavRealize index=… cards=…`.

## Reader selection/scroll & energy-diagnostics call graph (1.3.239)

* Đường selection (mới): `ReaderUITextView` báo `textViewDidChangeSelection` → nếu `selectedRange.length > 0` thì `Coordinator.setupScrollObservation(for:)` **cài KVO** trên `textView.parentScrollView.contentOffset` rồi `publishSelection(range, minY, maxY, force: true)`; nếu `length == 0` thì `teardownScrollObservation()` + `publishSelection(NSRange(location: NSNotFound, length: 0), nil, nil, force: true)`. `updateUIView` **không còn** gọi `setupScrollObservation` — cạnh `updateUIView → setupScrollObservation` (chạy mỗi paragraph, mỗi lượt cập nhật) đã bị xoá.
* Đường cuộn khi đang có selection: KVO → `handleSelectionOrScrollUpdate()` → `guard selectedRange.length > 0` → `NSMaxRange <= textView.textStorage.length` → `selectionGlobalMinMaxY(textView:textRange:)` → `publishSelection(...)` → (nếu qua dedup 0.5 pt) `parent.onSelectionChange` → `ReaderView.onSelectionChangeInParagraph`. Trước đây mỗi frame cuộn đều tới được `onSelectionChange`; giờ dedup chặn tại `publishSelection` nên `@State` của `ReaderView` chỉ ghi khi vị trí selection thực sự đổi.
* `triggerCustomDefine` cũng đi qua `publishSelection(..., force: true)` để giữ đúng hành vi publish một lần bất kể dedup.
* Huỷ observer: `dismantleUIView` và `Coordinator.deinit` vẫn `offsetObservation?.invalidate()`; thêm đường huỷ chủ động qua `teardownScrollObservation()` từ delegate selection.
* `ReaderEnergyDiagnostics` (file mới `Views/Reader/Components/ReaderEnergyDiagnostics.swift`): `ReaderView.onAppear` → `beginReaderSession()` → đọc `AppLogger.shared.isLoggingEnabled` **một lần** (getter này chạm `UserDefaults`, không được gọi trên hot path). Mọi `record*` (`recordUIViewUpdate`, `recordHighlightMutation`, `recordGeometryRebuild`, `recordThemeRebuild`, `recordExplicitSizeInvalidation`, `recordContentSizeInvalidation`, `recordTTSScrollTarget`, `recordTTSScrollSkippedVisible`, `recordTTSScrollExecuted`, `recordParagraphFrameUpdate`) và `flush(reason:)` mở đầu bằng `guard isEnabled`, nên khi log tắt các cạnh gọi từ `ParagraphTracker.updateFrame`, `ReaderScrollCoordinator`, `ReaderView+LoadingView`, `ReaderTextView.updateUIView` dừng ngay ở một phép so bool. `updateWindow` chỉ đọc `ProcessInfo.systemUptime` mỗi 64 event để kiểm mốc 60 s; `emitSummary` mới đọc trực tiếp và dựng `String(format:)` 24 tham số.
* `completeReaderPositionRestore` không còn cạnh `→ ParagraphTracker.removeAll()`; các call site còn lại của `removeAll()` là `onDisappear`, `onChange(of: chapterIndex)`, đường navigate, `applyNavigationCommit`, `reloadCurrentChapterFromMenu`.

## Next-chapter prefix audio call graph (1.3.234)

* `TTSManager.updatePrefetchWindow()` → `requestRemoteNextChapterPrefixIfNeeded(windowCount:inChapterTargetCount:)` → `requestNextChapterPrefix(capacity:)` → `TTSNextChapterPrefixCache.request(...)` (chỉ nhánh Google/Ext; guard `tool != "system"`, `tool != "nghitts"`).
* `TTSManager.updateNghiPrefetchWindow()` → `requestNghiNextChapterPrefixIfNeeded(currentIndex:blockedIndices:)` → `TTSManager.selectNghiOptionalRefillCandidate(...)` → `calculateNghiCachedTime()` → `requestNextChapterPrefix(capacity:)`. Được gọi **sau** nhánh `return` của slot bắt buộc `N+1` và sau `nextChapterPrefetcher.promoteAudioIfNeeded(...)`. Capacity = `maxTotalAudioPayloads - heldPayloads`, chỉ khi `cachedTime` chưa đủ ngưỡng.
* `TTSManager.calculateNghiCachedTime()` → `nextChapterPrefixContiguousDuration(matching:)` → `TTSNextChapterPrefixCache.contiguousDuration(matching:from:)`. Đây là cạnh khiến watermark cached-time đo được chuỗi phát **vượt biên chương**; nó chỉ cộng khi chunk 0 chương kế đã `.audioReady` (chuỗi liên tục) và key trùng tuyệt đối.
* `requestNextChapterPrefix(capacity:)` → `nextChapterPrefixContext()` đọc `nextChapterPrefetcher.currentState`; chỉ trả bối cảnh ở `.synthesizingAudio`/`.audioReady`, và với `nghitts` thì chunk hoá qua `NghiUtteranceSegmenter.expand(_:maximumLength: key.chunkLength)`.
* `TTSNextChapterPrefixCache.request` → `startSynthesis` → `TTSNextChapterPrefixCache.synthesize` (nonisolated static) → một trong ba: `PiperTTSService.synthesize(priority: .optionalReserve)` | `TTSAudioSynthesisWorker.synthesizeParagraph(priority: .nextChapter, offset: index, prefetchDelayMs: prefetchDelayMs)` → `GoogleTTSService.synthesize` | `... → ExtTTSService.synthesizeData`. Nhánh remote đi qua đúng bước `sleep(offset × max(300, prefetchDelayMs))` của worker nên tôn trọng cấu hình giãn request; nhánh Nghi không có bước này. Kết thúc quay về `finishSynthesis` trên MainActor (guard `generation` + `activeKey` + token theo index). Nhánh lỗi gọi `TTSManager.evaluateRefillError(_:currentAttempts:maxAttempts: 2)` để quyết định block/thử lại — dùng chung `classifyTTSError` với refill NghiTTS, không có retry task riêng.
* `TTSManager.applyNextChapter(...)` → `mergeNextChapterPrefixAudio(for:)` → `makeNextChapterKey(for:)` + `TTSNextChapterPrefixCache.consume(matching:)` → so `PreparedChunk.finalText` với `TTSReplacementManager.applyReplacements(paragraphs[index].text)` → ghi `preloadedData`/`preloadedDurations` (bỏ qua index đã có, `>= paragraphs.count`, hoặc text không khớp). Sau đó đường phát bình thường (`playAudioData` → `commitAudibleParagraphState`, hoặc `NghiAudioPlayerQueue.onTransition` → `commitAudibleParagraphState`) phát highlight từ `paragraphs[index]` như mọi chunk khác. Chạy **sau** `clearCurrentParagraphPrefetchCache()` và sau khi `preloadedData[0]` được gán, **trước** `continueStartSpeaking`.
* `TTSManager.pause()` → `cancelNextChapterPrefixWork()` → `cancelPendingWork()` (hủy task, giữ chunk đã xong).
* `TTSManager.clearAllTTSCaches()` → `resetNextChapterPrefixCache()` → `reset()`; đường này được `stopPlayback`, `tool.didSet` và `selectedVoice.didSet` dùng chung qua `clearPrefetchCache()`.

## All-source novel-search filtering call graph (1.3.225)

* `SearchView.performSearch` (all sources) → `searchableExtensions` (`activeExtensions.filter(type != "tts")`) → initialize `sourceStates` → task group calls `ExtensionManager.search` only for non-TTS extensions.
* `searchAllSourcesResultsView` and each `Xem thêm` destination consume the same filtered collection, preventing a TTS group or nested TTS search from being created.

## Local TXT translation and chapter-search call graph (1.3.224)

* Confirm import → `ShelfView.performImport` creates the Book on MainActor → detached task maps `ParserChapter` to `ChapterMetadataSnapshot(title,titleTrans,...)` → `ChapterStore.replaceFullTOC` persists both titles → per-chapter cache writes reuse the same snapshots.
* Reader chapter search → `BackgroundSearchWorker.searchChapters` → `ChapterStore.searchChapters(bookId:query:)` → SQLite OR-matches original and translated title; `isTranslationEnabled` is consulted only after matching to choose the displayed title.
* BookDetail local TOC search OR-matches `StoredChapterSnapshot.title/titleTrans` (and the SwiftData fallback matches `Chapter.title/titleTrans`) without consulting the translation toggle.

## TXT import confirmation handoff call graph (1.3.223)

> Từ 1.3.251: `isParsingTXT` → `isParsingImport`, `TXTImportConfirmationSheet` → `BookImportConfirmationSheet`, `importTxtBook` → `importLocalBook`. Handoff wait-layer → sheet không đổi.

* Parse nền thành công → `MainActor` gán `pendingImport` trong khi `isParsingTXT` vẫn bật → SwiftUI trình bày `TXTImportConfirmationSheet` → sheet `onAppear` đặt `isParsingTXT = false`.
* Parse thất bại → xóa file tạm → `MainActor` tắt `isParsingTXT` → log file + Toast. Hủy/xác nhận sheet tiếp tục đi qua `cancelImport`/`performImport` hiện có.

## Shelf/History translation and original chapter progress call graph (1.3.222)

* Author row: `BookListItemView.body` → `displayedAuthor` → toggle tắt trả `item.author`; toggle bật gọi `TranslateUtils.translateAuthorHanViet(item.author)`.
* Reader progress: `progressSnapshot` → `originalChapterTitle(at:)` → `CachedChapter.originalTitle` / `onlineChapters[index].name` → `ReadingProgressStore.persist` → `Book.currentChapterTitle`. `chapterTitle(at:)`/`CachedChapter.title` vẫn chỉ thuộc đường hiển thị.
* Dịch lại TOC: `ShelfView.retranslateChapterTitles` → dịch từ `StoredChapterSnapshot.title` → `ChapterStore.updateTitleTranslations`; không còn gọi `BookTransactionCoordinator.updateCurrentChapterTitle` — hàm này sau đó hết caller và đã bị xoá ở 1.3.235.

## TTS replacement rule add/upsert call graph (1.3.221)

* `ReaderView.AddTTSReplacementSheet.onAdd` hoặc `TTSReplacementManagerView.saveRule` (nhánh thêm) → tạo `TTSReplacementRule` → `TTSReplacementManager.addRule(_:)` → tạo bản sao danh sách → `removeAll(pattern == newRule.pattern)` → `append(newRule)` → publish danh sách cuối → `saveRules()`.
* `addRule(_:)` trả `.replaced` nếu ít nhất một rule cũ bị xóa, ngược lại trả `.added`; Reader dùng kết quả để chọn nội dung Toast, còn màn quản lý bỏ qua kết quả nhờ `@discardableResult`.

## Sơ Đồ Luồng Gọi Hàm (Call Graph v4.1/v5.0)

1. **Luồng Khởi Chạy Ứng Dụng & Nhận Sự Kiện Toast**:
   `FreeBookApp.swift` -> `AppLaunchRootView.task`
     ├── Lắng nghe `TTSPresentationEventCenter.shared.stream` -> `ToastManager.shared.show(...)`
     └── Lắng nghe `DownloadPresentationEventCenter.shared.stream` -> `ToastManager.shared.show(...)`

2. **Luồng Ghi SwiftData qua Transaction Coordinators**:
   - `ShelfView` / `BookDetailView` -> `BookTransactionCoordinator.shared.addBookToShelf(command:in:)` -> `ModelContext.save()`
   - `BookDetailView` -> `BookTransactionCoordinator.shared.updateBookMetadata(...)` / `setCurrentChapterIndex(...)`
   - `RepositoryManagerView` -> `ExtensionTransactionCoordinator.shared.upsertExtension(command:in:)` / `touchRepositoryLastUpdated(...)`

3. **Luồng Phân Trang & Tìm Kiếm Chương Đọc**:
   `ReaderView` -> `ReaderViewModel`
     ├── `ReaderChapterListPageFetcher` -> `BackgroundPagingWorker.fetchPage(bookId:minLogicalIndex:maxLogicalIndex:isTranslationEnabled:)`
     └── `BackgroundSearchWorker.searchChapters(bookId:query:isAscending:isTranslationEnabled:)` -> `ChapterStore.shared.searchChapters(bookId:query:)`

4. **Luồng NghiTTS khi đoạn sau tiền xử lý không thể đọc**:
   `TTSManager.scheduleNghiRefill()` -> `PiperTTSService.synthesizeWithDuration(...)` -> `TextPreprocessor.preprocess(...)`
     ├── Có nội dung đọc được -> `ONNXPiperEngine.synthesizeWithDuration(...)`
     └── Rỗng/chỉ dấu câu -> `PiperTTSService.makeSilenceSpec(...)` -> `WAVEncoder.encodePCM16(...)`
   - Lỗi prefetch tạm thời -> `evaluateRefillError(...)` -> retry backoff 1 giây (`Task.sleep`, tối đa 2 lần) -> `updateNghiPrefetchWindow()`.
   - Lỗi không retry hoặc đủ hai attempt -> đánh dấu index bị block -> chọn ứng viên prefetch khác.
<!-- GENERATED END -->
