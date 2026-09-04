---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T14:10:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 9
---

# Hướng dẫn Quy định Lập trình (Coding & Architecture Rules)

Tài liệu này tổng hợp các quy tắc lập trình, quy định bảo trì và kiến thức kỹ thuật chi tiết của dự án FreeBook.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Batched Google TTS prefetch: invariants (1.3.332)

1. **Only the prefetch window is batched; the paragraph the user is waiting for is not.** `updatePrefetchWindow` covers `N+1…N+k`; the current paragraph keeps its own single-part request because one round trip alone (~370 ms) beats waiting for a bigger one.
2. **A batch is still one coordinator job.** Route every remote synthesis through `RemoteTTSSynthesisCoordinator`; do not call `GoogleTTSService` directly from a prefetch path. Multiple mp3 blobs travel as one `Data` via `TTSBatchAudioPayload` — that framing exists specifically so the coordinator does not have to become generic.
3. **Never send an empty part, and always verify the count.** The API silently drops blank parts, which shifts every later index onto the wrong audio. `makeGoogleBatch` filters, `synthesizeBatch` rejects, and the returned count must equal the sent count or the call must throw.
4. **Batch text must be produced the same way as single-paragraph text** (`TTSReplacementManager.applyReplacements` then trim). Two code paths that build the text differently will synthesise two different audios for the same paragraph depending on which one ran.
5. **Retry stays inside `GoogleTTSService`** (`withRetry`, 2 attempts). `TTSManager` must not wrap another retry loop around a batch; a failed batch falls back to per-paragraph requests instead.
6. **Register a batch task under every index it serves, and cancel by task identity, not by index.** The window slides one paragraph at a time, so index-based cancellation kills a batch that is still needed for the remaining indices.
7. **Only Google batches.** Ext TTS calls `execute(text, voice)` in JavaScript — one paragraph per call. Do not invent a batching protocol for extensions.
8. **Scope changes on a rule are copy-then-delete, in that order.** `QuickTranslationRuleTransfer.copy` stays a copy (it is shared with the dictionary's Chuyển button); the delete lives at the call site. Writing the destination first means a mid-way failure leaves the rule intact rather than losing user-authored data, and the "exists in both places" outcome must be reported, not hidden.
9. **Shelf tab indices go through `ShelfTab`, never bare integers.** The order is Downloads → Bộ Sưu Tập → Kệ Sách → Lịch Sử; `SearchView` posts `rawValue` and `ShelfView` rejects values that do not map to a case.

## Ext TTS script cache, icon cache, repo refresh: invariants (1.3.330)

1. **`ExtTTSScriptCache` is the only reader of `tts.js` and the only place that merges TTS config.** Do not re-add a direct `String(contentsOf:)` in `ttsGenerate` or a second SHA256 in `getTTSRuntimeFingerprint`: those two paths reading disk independently is how a `synthesisKey` from one revision could end up caching audio produced by another.
2. **Cache validity is `(configJson, plugin.json modDate, script modDate)` — all three.** `plugin.json` decides the script *filename*, so watching only the script lets a renamed entry point serve the old file forever.
3. **`resetTTSRuntime()` invalidates the cache before resetting the runtime.** Reversing the order leaves a window where the next synthesis rebuilds the executor from a stale payload.
4. **`ExtTTSRuntime.Identity` compares the fingerprint, never the script text.** Comparing `scriptContent` is an O(len(script)) string compare on every paragraph, and the fingerprint already covers script + config + path.
5. **Ext TTS owns no files.** It returns `Data` only. Do not reintroduce temp-file staging: the deleted PCM path wrote one file per paragraph and needed a lock plus an explicit cleanup list to undo it. If a PCM path is ever needed again, decode in memory and apply normalisation **once**.
6. **Retry stays in exactly one layer** — `ExtTTSService.synthesizeData` (2 attempts). The cache must `throw` straight through, and `TTSManager` must not wrap another retry loop.
7. **Automatic repository refresh goes through `RepositoryRefreshPolicy`; manual refresh does not.** A refresh is one registry request per repo *plus* one `plugin.json` request per not-installed extension, so an ungated `.onAppear` sweep is ~95 requests for a 100-extension repo. `markRefreshed()` may only be called when at least one repo actually updated — otherwise one offline visit silences the next 6 hours.
8. **`ExtensionIconImageCache` keys on `(path, modDate)` and caches misses too.** Most extensions ship no `icon.png`; without negative caching every redraw stats and fails again. Never key on path alone — reinstalling an extension must show the new icon.
9. **Prefer `ExtensionIconView` over `AsyncImage` for extension icons.** It reads the local `icon.png` first, so installed extensions never hit the network and still render offline. Keep the type-specific fallback (`waveform` for TTS) for rows that have neither a local path nor an icon URL.
10. **Compute a filtered/sorted list once per view update.** `filteredExtensions` runs four `filter` passes plus a `sorted` using `localizedCompare`; calling it separately from a counter, an `isEmpty` check and a `List` multiplies the most expensive part of the redraw by three.

## Book collections: invariants (1.3.328)

These are **binding** for any change touching `BookCollection`, `Book.isPinned`, the Shelf tabs, or the long-press sheet:

1. **A book in a collection is always on the shelf.** Every path that adds membership must set `isOnShelf` (`BookCollectionCoordinator.promoteToShelf`), and every path that clears `isOnShelf` must empty `Book.collections` and clear `isPinned` (`BookTransactionCoordinator.removeFromShelf`, `setOnShelf(false)`, `addBookToShelf(isOnShelf: false)`). The invariant is enforced in the coordinators so no call site has to remember it.
2. **Removing from a collection never removes from the shelf, and deleting a collection never deletes books.** `deleteRule: .nullify` on both ends of the N-N relationship is load-bearing — `.cascade` here means deleting real books. `deleteCollection` also clears `books` by hand before `context.delete` because this is the easiest thing in the feature to get wrong.
3. **The type is `BookCollection`, never `Collection`.** A module-level `Collection` shadows `Swift.Collection` and silently changes what every later generic constraint means.
4. **New SwiftData properties stay additive with defaults.** There is no `VersionedSchema`/`SchemaMigrationPlan`, and `ModelContainer` init failure is `fatalError`, so a non-additive schema change ships an app that cannot launch.
5. **Collection membership and pin state are written only through coordinators.** Views read with `@Query` and handle the returned `Result`; `check_architecture.py` already watches `.isPinned =` for `SCOPED_VIEWS`, and it matches those views **by path substring**, so any new file with `ShelfView` in its path inherits the ban.
6. **Shelf tab indices are a cross-screen contract.** `ShelfView` tabs are Downloads 0, Kệ Sách 1, Bộ Sưu Tập 2, Lịch Sử 3, and `SearchView` posts that integer as `userInfo["shelfTab"]` on `sourceChangedNavigateToShelf`. Both the notification name and the value are bare literals: change one end and navigation silently lands on the wrong tab.
7. **Do not wrap a shelf row in a `Button` and add a long-press on top.** Releasing after the long press still fires the button, which opens the Reader behind the sheet. Use `onTapGesture` + `onLongPressGesture`.
8. **Pin-first ordering is two `filter` passes, not one `sorted`.** `sorted(by:)` is not stable in Swift, so comparing two keys in one pass reshuffles books inside each group; `pinned + unpinned` preserves the `lastReadDate` order the `@Query` already established.
9. **Backup gains entries, never a `BackupScope` case.** Collections and `isPinned` ride along with the mandatory `.books` scope via `library/collections.json`. New non-optional keys in `BackupPayload` records must be `Optional` (or get a hand-written `init(from:)`): Swift's synthesized decoder ignores property defaults, so a plain new key breaks every older archive. Restore is a **merge** — collections matched by case-insensitive name, members attached only when the book exists locally.

## Supersedes: transliteration verification no longer lives in the app (1.3.328)

* **The 1.3.290 bullet "Verification for this subsystem lives in the app … `TTSTransliterationTesterView` + `TransliterationGoldenSet`" and the 1.3.290 instruction to "re-run `TransliterationGoldenSet` from the Thử phiên âm screen" no longer apply.** Both the screen and the golden set were deleted on request; `EspeakPhonemizer.probeVoices` and `VietnameseTokenGate.explain` went with them.
* **What remains is listening.** The only in-app check for a phoneme table or threshold change is "Thử giọng đọc" (`NghiTTSTextToolView`) — type text, hear it. There is no automated gate: `check_architecture.py` only counts lines and `validate_links.py` only compares hashes. State plainly in the changelog when a transliteration change was not listened to.
* **The rest of the 1.3.290/1.3.291 transliteration invariants stand unchanged** (never return empty, never delete sounds to satisfy phonotactics, restore the espeak voice to `vi`, all espeak access through `EspeakPhonemizer`, don't grow a word blacklist, group regex alternations, collapse long vowels before segmentation, `/j/` splits onset/coda). Where those bullets cite the golden set as the record of a listening decision, treat the bullet itself as the record.
* **Japanese `u` renders as `u`, not `ư` (1.3.328).** `ku su tsu tu nu hu fu mu ru gu zu du bu pu` and bare `u` all use Vietnamese `u`. `ư` is /ɨ/ — unrounded — and espeak-vi speaks it as a different vowel ("Naruto" → *na-rư-tô*). Value collisions this creates (`tsu`/`tu` → `chu`, `zu` → `du`) are harmless: only dictionary **keys** must be unique.

## Quy chuẩn cho đường cài mới của debug server (1.3.325)

Bốn luật này bắt buộc với mọi thay đổi chạm nhánh `draft.install`:

* **File trước, bản ghi sau — không đảo.** Copy vào `extensions/<packageId>/` xong mới ghi hàng `Extension`. Hàng SwiftData trỏ vào thư mục không tồn tại là lỗi im lặng ở mọi màn đang `@Query`; thư mục mồ côi thì `ExtensionInstallAudit` thấy được và lần cài sau tự sao lưu rồi thay.
* **`packageId` là danh tính do *app* suy từ `plugin.json`, không phải giá trị client gửi.** Client gửi id chỉ để làm khoá vùng staging. Ba đường cài (repo sync, import zip, cài từ debug) phải cho **cùng một** id với cùng một cái tên — sửa luật ở một chỗ thì phải sửa cả `ExtensionSyncCommandBuilder.packageId(forName:)`, `ExtensionManager.installFromLocalZip` và `ExtensionDraftMetadata.slug(forName:)`, nếu không thư viện sẽ có hai hàng cho một extension.
* **Ghi SwiftData chỉ ở router, chỉ qua `ExtensionTransactionCoordinator`, và chỉ bằng `ModelContext` dựng mới từ container.** `ExtensionDraftInstaller` phải giữ nguyên vai "chỉ đụng file" — nó là actor nền và không được giữ `ModelContext`.
* **Mọi nhánh ghi vào dữ liệu người dùng đều phải qua `ExtensionDebugInstallGate`, và `Kind` phải nói đúng việc sắp làm.** Thêm một nhánh ghi mới mà tái dùng `Kind` cũ là làm người bấm hiểu sai thứ họ đồng ý; đường cài mới bắt buộc kèm tên đọc từ `plugin.json` vì `packageId` một mình không đủ để quyết định.

## Quy chuan cho debug server (1.3.303)

Nam luat nay bat buoc voi moi thay doi cham `Debug/Server/` hoac `Debug/Staging/`:

1. **Khong bao gio bo qua cua xac nhan tren thiet bi.** Token dung chi cho phep *xin* pair; `isPaired` chi `true` sau `approvePending()`. `draft.install`/`draft.rollback` phai di qua `ExtensionDebugInstallGate`. Them mot lenh nao ghi de du lieu nguoi dung thi lenh do cung phai di qua cong nay.
2. **Khong nhan path tu client.** Lenh chi duoc mang `packageId`, `entrypoint`, input va `relativePath` **da khai trong manifest**. Cam them field nao nhan `URL`, path tuyet doi, hay source JavaScript raw vao `run.start`.
3. **Moi duong tat may phai `InstallGate.cancelPending()`.** Do la cho duy nhat trong app co continuation treo vo han; thieu mot duong la `Task` cua router treo ca phien.
4. **`ExtensionDraftStagingStore` la cho duy nhat tao/xoa file trong `extension-drafts/`.** Khong ai khac duoc ghi vao do, va no khong duoc ghi ra ngoai do.
5. **`src/protocol.ts` la mirror cua `ExtensionDebugProtocol.swift` + `ExtensionDebugEvent.swift`.** Sua mot ben phai sua ben kia cung luot. App la tham quyen cuoi cung ve manifest, entrypoint va contract; client chi validate hinh dang de bao loi som.

Doi `Envelope`, them `CommandType` hay `ErrorCode` la doi contract v1 => nang `ExtensionDebugProtocol.version` va `ExtensionDebugEvent.contractVersion`, khong them im lang.

## Quy chuẩn cho trace debug extension (1.3.302)

Bốn luật này là **bắt buộc** với mọi thay đổi chạm phân hệ debug extension:

1. **`ExtensionDebugEventSink.emit` không được blocking.** Nó bị gọi từ thread đang chạy JavaScript (trong `@convention(block)` của JavaScriptCore) và từ callback `URLSession`. Cấm `await`, cấm I/O, cấm giữ khoá qua một lời gọi khác. Đó là lý do sink là `final class` + `NSLock` chứ không phải `actor` — mọi việc nặng thuộc `ExtensionDebugEventHub`.
2. **Redact ở phía tạo event, không ở phía gửi.** `ExtensionDebugEvent` được coi là đã sạch từ lúc khởi tạo. Không thêm hàm nào vào `ExtensionDebugRedactor` để nhận header, cookie, request/response body, nội dung chương, `configJson` hay localStorage — việc **không có hàm** là chốt an toàn, không phải thiếu sót.
3. **Trace không được phụ thuộc `AppLogger`.** Không đọc `isLoggingEnabled`, không tail `app_logs.txt`. `AppLogger.init` tự tắt log mỗi lần khởi chạy nên log file không dùng được làm giao thức debug; đó là lý do phân hệ này tồn tại.
4. **`ExtensionDebugEntrypoint.jsArguments` là bản sao của contract `execute(...)` ở `ExtensionManager`.** Sửa một bên phải sửa bên kia cùng lượt. Hai chỗ dễ sai đã có sẵn: `search` truyền `page` dưới dạng `String`, và `toc` chỉ resolve URL khi extension **không** khai script `page`.

Thêm `case` vào `ExtensionDebugEvent.Category` là đổi contract v1 ⇒ nâng `ExtensionDebugEvent.contractVersion`, không thêm im lặng.

## TTS transliteration: no-drop invariants (1.3.291)

* **No transliterator may return an empty string.** If a word cannot be rendered, return the original token verbatim. The only downstream guard is chunk-level (`PiperTTSService.isUnspeakable`), so an empty token is silently missing audio, which users hear as dropped words.
* **Never satisfy Vietnamese phonotactics by deleting sounds.** Clusters Vietnamese cannot spell must become additional filler syllables (`+ "ơ"`), not be truncated. `IPAToVietnameseMapper.assemble` returns `[String]` for exactly this reason.
* **Japanese long vowels render short, on purpose.** `ー`, `ou`, `ei` collapse to the short vowel because Vietnamese has no vowel length and doubling makes Piper insert a syllable break. This is a listening decision recorded in the golden set — do not "correct" it back to Hepburn without listening.
* **The ambiguous-syllable gate requires foreign neighbours on both sides.** One-sided context transliterated Vietnamese words; prefer a missed transliteration over mangled Vietnamese.
* **Bulk dictionary actions have one owner.** `TTSDictionaryBulkActionsModifier` performs the delete itself and only reports completion; views must not re-implement "delete all".

## TTS transliteration invariants (1.3.290)

* **espeak voice must always be restored to `vi`.** Any entry point that calls `espeak_SetVoiceByName` with another language must restore `vi` in a `defer` **inside the same `NSLock` critical section** before returning. Piper synthesis assumes Vietnamese phonemes; a leaked voice change corrupts every later utterance and the symptom surfaces long after the cause.
* **All espeak access goes through `EspeakPhonemizer`.** Do not call `libespeak_ng` from anywhere else: the initialization flag, the lock and the voice invariant live in that one type. New needs get a new entry point there, not a second engine owner.
* **Do not "fix" transliteration by growing the word blacklist.** Recognizing Japanese romaji versus English is a scoring problem in `ForeignScriptClassifier`; the set of English words that happen to segment into valid romaji syllables is unbounded, so an exclusion list can only ever chase the last report. Adjust signals or `japaneseThreshold`, and re-run `TransliterationGoldenSet` from the Thử phiên âm screen.
* **Transliterator output must be legal Vietnamese orthography.** The result is fed back into espeak (`vi`) for Piper, so onset/coda combinations that Vietnamese does not allow are silently mispronounced. `IPAToVietnameseMapper.legalOnset`/`legalCoda`/`normalize` are the only place that guarantee this; new phoneme entries must pass through them rather than emitting raw strings.
* **Rule cascade order in `EnglishTransliterator` is load-bearing.** `sRules` → `rRules` → `tRules` run on the *same progressively rewritten* string, so a rule that collapses a digraph (`ck`, `sh`) must not run before the suffix rules that need that digraph. Any new rule must state which stage it belongs to and why.
* **Regex alternation must be grouped.** `"\bcr|pr|gr"` anchors only the first branch; always write `"\b(?:cr|pr|gr)"`. This class of bug silently rewrote mid-word clusters for a long time.
* **Never overwrite `non-vietnamese-words.plist` wholesale.** It holds both the downloaded base dictionary and user-added pronunciations. Downloads must merge with local entries winning.
* **Japanese long-vowel collapsing happens before syllable segmentation, never as table entries.** `greedySegment` matches longest-first *at each cursor position*, so a `"ou"`/`"uu"` key in `romajiToViSyllable` can never win against the `"to"` that starts one character earlier — "arigatou" segmented to `to` + `u` and spoke a spurious `ư` syllable for a full release while the table looked correct. Collapse in `JapaneseTransliterator.collapseLongVowels` (called from `normalizeRomaji`) and keep the reading table free of long-vowel keys. `ai`/`oi`/`ui`/`au` must stay out of `longVowelForms`: those are real diphthongs and collapsing them drops a sound.
* **A nucleus and a coda that are individually legal can still form an illegal rime.** `IPAToVietnameseMapper` looks the two up in separate tables, so nothing stops it emitting `ơng`, `âyp`, or a stop-final syllable with no tone mark — none of which exist in Vietnamese, and all of which reached espeak-vi for a full release. Three rules hold the line and each one carries the others: diphthongs (`ây ai oi ao ia ua iu`) take **no** coda, a coda in `p t c ch` **forces** the acute tone, and `/əl/`/`/ən/` are fixed rimes. `acute` only handles a single-character nucleus — that is safe *only because* the diphthong rule runs first, so relaxing the diphthong rule silently stops adding tone marks. Any new vowel or coda entry must be checked against the rime it can produce, not just against its own table.
* **`/j/` maps to `d` at the onset and `i` at the coda, and the two must not be unified.** At the onset Vietnamese has no letter for /j/, and writing `i` makes espeak-vi read a diphthong (`ia` → /iə/) so the word gains a syllable; at the coda `i` *is* the offglide of `ai`, `ây`. Same split applies to `ya/yu/yo` in `JapaneseTransliterator`. Accept that `d` reads /z/ in the default `vi` voice: a wrong consonant is a smaller error than a wrong syllable count.
* **Verification for this subsystem lives in the app**, not in `Tests/`: `TTSTransliterationTesterView` + `TransliterationGoldenSet`. Changing a phoneme table or a threshold without re-running the golden set is not a verified change. Cases the team has decided not to fix yet stay in the set marked `ĐỎ` with the reason, rather than being deleted or quietly retargeted.

## TTS preparing highlight color invariant (1.3.278)

* Preparing highlight and active TTS highlight must use the same configured Reader highlight colors: `theme.highlightUIColor` for background and `theme.highlightTextUIColor` for foreground when available. Do not add a separate alpha, fallback color, or hard-coded preparing color.
* `highlightIsPreparing` remains useful only as render/diff state and must not imply a distinct visual palette or progress ownership.

## TTS widget reveal-from-Reader invariants (1.3.277)

* Hành động nghe khởi phát từ Reader phải yêu cầu widget TTS mở rộng ban đầu qua tầng View (`TTSFloatingWidgetWindowManager.requestRevealOnNextShow()`), không qua `TTSManager`. `Services/TTS` không được phụ thuộc `Views/TTSWidget` hoặc biết `WidgetMode`.
* `FloatingWidgetViewModel` vẫn mặc định `.peeking`; không đổi default mode toàn app chỉ để phục vụ Reader. Reveal ban đầu là cờ một lượt ở window manager và phải được consume khi container sẵn sàng.
* Reveal từ Reader dùng lại `FloatingWidgetViewModel.reveal()` và auto-hide hiện có. Muốn ghim widget mở lâu hơn phải là yêu cầu riêng, không lẫn vào request "mở rộng ban đầu".

## TTS preparing highlight invariants (1.3.276)

* `TTSPlaybackSnapshot.preparingParentParagraphIndex` và `preparingHighlightRange` là **presentation-only state** cho đoạn sắp nghe trước khi audio thật bắt đầu. Không dùng chúng để lưu tiến độ đọc, update Now Playing, claim `ReadingProgressStore`, mở rộng prefetch window hay đánh dấu synthesis thành công.
* Active highlight vẫn chỉ được publish qua `commitAudibleParagraphState(index:)` khi audio đã bắt đầu/scheduled đúng đoạn. Không publish `highlightRange` active sớm trong `speakCurrent()`; guard dedupe của snapshot có thể làm lượt commit audible bị bỏ qua và mất side effect.
* Reader phải ưu tiên highlight theo thứ tự active TTS → preparing TTS → search. Preparing highlight chỉ hợp lệ khi `playingBookId`, `playingChapterIndex` và `preparingParentParagraphIndex` khớp đoạn đang render; Reader sách khác phải nhận `nil` qua projection reader.
* Preparing range dùng cùng hệ toạ độ UTF-16 tương đối với dòng cha như `TTSParagraph.range`. Không map lại qua `ReaderSelectionMapper` và không tạo hệ toạ độ thứ ba.

## Một nguồn duy nhất cho file riêng truyện; tắt rule bằng file theo phạm vi (1.3.274)

* **Danh sách file riêng truyện chỉ được khai ở một nơi**: `Sources/Services/Translation/Extensions/TranslationManager+BookScopedFiles.swift` (`bookScopedDictionaryTextFiles`, `bookScopedDictionaryBinaryFiles`, `bookScopedRuleFiles`, `bookScopedMigrationFiles`). `BackupPaths` và luồng đổi nguồn của `SearchView` phải đọc hằng từ đó. Thêm tên file riêng truyện mới mà khai ở nơi khác (hoặc thêm danh sách `["VietPhrase.txt", …]` thứ ba) là tái tạo đúng loại bug im lặng "file không vào backup và không đi theo truyện khi đổi nguồn" mà 1.3.274 vừa dọn.
* **Bật/tắt rule dịch tuyệt đối không được sửa file rule.** Rule đang tắt vẫn nằm trong `snapshot.rules` (bật lại được, giữ `sourceLine`); chỉ có **mẫu** của nó nằm trong file tắt (`translate/QuickTranslateRulesDisabled.txt` chung / `translate/books/<bookId>/QuickTranslateRulesDisabled.txt` riêng). Khoá của file tắt là **mẫu** (phần trước dấu `=`), không phải `sourceLine` — số dòng đổi sau mỗi lần thêm/xoá. `QuickTranslationRuleDisableFile` là hàm thuần trên `String` (không chạm `FileManager`); chỉ `QuickTranslationRuleDisableStore` được ghi file tắt, và hết mẫu thì **xoá file** thay vì để file rỗng.
* **Ngữ nghĩa tắt theo phạm vi** (`QuickTranslationRuleDisableStore.Snapshot.isDisabled(pattern:scopeRank:)`): rule của bộ riêng chỉ chịu file tắt riêng; rule của bộ chung chịu file tắt chung (mọi truyện) **hoặc** file tắt riêng của truyện đang đọc. Tắt ở bộ chung = tắt cho mọi truyện; muốn dùng lại ở đúng một truyện thì thêm mẫu vào bộ rule riêng của truyện đó.
* **`scopeRank` là tiêu chí ưu tiên thứ 5 của `QuickTranslationRuleEngine.select`** (sau độ dài match, trước `sourceLine`; rule bộ riêng = 0 thắng bộ chung = 1). Mọi nơi cần trả lời "rule nào thắng" (màn Check rule qua `QuickTranslationRuleDiagnostics`, ô Thử nhanh qua `preview`) phải dùng lại đúng `collectFound` + `select` của engine — không cài lại thứ tự ưu tiên ở chỗ thứ hai — và không được để màn soi ghi trạng thái (`notesComplexRules: false`) hay bỏ qua file tắt; nếu không nó nói khác kết quả dịch thật.
* **Mọi invalidation khi đổi dữ liệu rule** (bật/tắt/thêm/sửa/xoá/chuyển, phạm vi nào cũng vậy) gói vào đúng một `TranslationManager.notifyDictionariesDidUpdate(bookId:scope: .config(bookId:))` — không thêm tên NotificationCenter mới, không thêm `disableRevision`/`revision` vào cache key (đường invalidation đã đủ: engine `clearCache()` + bump generation đúng phạm vi). Ghi file thất bại ⇒ không bump, không notify, trả lỗi lên View để toggle quay về trạng thái cũ.
* **Định danh nghiệp vụ của Quick Translation rule là `pattern` (vế trái dấu `=`), không phải `sourceLine`** — số dòng đổi sau mỗi lần thêm/xoá. File rule được canonical first-wins nên `pattern` là duy nhất trong snapshot; `QuickTranslationRuleTrace.id` xác định theo scope/pattern/location, không phải `UUID()` mới mỗi lượt. Thêm/sửa/xoá chung và riêng đều đi qua `QuickTranslationRuleRecordStore`.

## Tắt bàn phím là hành vi toàn app, có đúng một chủ (1.3.266)

* **Không thêm `.onTapGesture { hideKeyboard() }` (hay `background` bắt tap) cho từng màn để tắt bàn phím.** Hành vi "bấm ra ngoài ô nhập thì bàn phím tắt" do `KeyboardDismissGesture` (`Sources/Common/Utils/`) phủ ở tầng `UIWindow` cho mọi màn. Thêm ở màn lẻ là tạo điểm điều khiển thứ hai cho cùng một hành vi, và thường kèm tác dụng phụ ăn mất touch của nút bên dưới.
* **Vẫn được tắt bàn phím tường minh** khi đó là *lệnh* của người dùng — nút "Xong", đóng overlay, submit form: dùng `View.hideKeyboard()` (`Common/Extensions/View+Keyboard.swift`). Ranh giới: recognizer nền xử lý tap vào vùng trống; lệnh tường minh xử lý phần còn lại.
* **Nếu phải sửa `KeyboardDismissGesture`, giữ ba thiết lập sau** — mỗi cái chặn một lỗi cụ thể: `cancelsTouchesInView = false` (không thì nút/hàng `List` mất touch), `shouldRecognizeSimultaneouslyWith → true` (không thì pan của scroll view và tap chọn hàng bị chặn), và `shouldReceive touch` bỏ qua ô **đang nhập được** (không thì bấm vào chính ô đang gõ lại tắt bàn phím). Thêm loại ô nhập mới thì sửa trong `isEditableTextInput` bằng `as?` + cờ `isEnabled`/`isEditable`, **không** so tên class.
* **Chỉ cài lên `UIWindow` ở level `.normal`.** Cài lên window của toast/TTS widget/widget trình duyệt (quanh level `.alert`, hit-test passthrough) là vô ích và gây nhiễu; bàn phím nằm ở window hệ thống riêng nên vốn không đi qua đây.
* **Recognizer chỉ được tồn tại trong quãng bàn phím đang hiện (1.3.323).** `keyboardWillShowNotification` cài, `keyboardWillHideNotification` gỡ — **không** được "cài một lần rồi để đó cho gọn". `handleTap` gọi `endEditing(true)`, và lệnh đó buộc **first responder bất kỳ** trong window resign, kể cả `UITextView` chỉ đọc của Reader hay `WKContentView` của web view đang giữ vùng bôi đen ⇒ mất vùng chọn ở đúng nhịp thả tay, hay gặp nhất với vùng bôi **ngắn** (tap chỉ fail khi ngón di chuyển quá ngưỡng, không phải khi giữ lâu). Bộ lọc `shouldReceive` không thay được hàng rào này: nó không phân biệt được "tap vào chữ" với "vừa bôi đen xong rồi thả tay". `uninstall()` phải quét **mọi** window, không lọc `windowLevel`/`isHidden` như lúc cài, nếu không window đã ẩn sẽ giữ lại recognizer mồ côi.

## Next-chapter prefix audio invariants (1.3.234)

* Cửa sổ prefetch đoạn văn **vẫn bị chặn ở biên chương**: `updatePrefetchWindow` và `updateNghiPrefetchWindow` không bao giờ tạo index vượt `paragraphs.count` của chương đang phát. Phần thiếu ở cuối chương được lấp bằng **chunk đầu của chương kế** do `TTSNextChapterPrefixCache` sở hữu, chứ không bằng cách mở rộng không gian index của `preloadedData`.
* `TTSNextChapterPrefixCache` chỉ giữ chunk index `>= 1`. Chunk 0 của chương kế vẫn thuộc `TTSChapterPrefetcher` (nó có đường claim in-flight riêng khi chuyển chương). Prefix chỉ được yêu cầu khi state của prefetcher đã là `.synthesizingAudio` hoặc `.audioReady`, nhờ đó chunk 0 luôn vào hàng đợi trước ở cùng hoặc cao hơn mức ưu tiên.
* **Trần bộ nhớ không đổi** — prefix chỉ *tái phân bổ* các slot đang trống, và mỗi engine dùng đúng đơn vị đo của chính nó:
  - **Google/Ext — theo `preload_size`/`googlePrefetchCount`**: `capacity = max(0, count - inChapterTargetCount - 1)` với `count = max(1, min(10, currentPrefetchCount))`. Vì `inChapterTargetCount + 1 (chunk 0) + capacity == count`, **độ sâu buffer phía trước luôn bằng đúng `count` chunk kể cả khi đi qua biên chương**, và tổng payload vẫn `<= count + 1` như lúc ở giữa chương.
  - **NghiTTS — theo watermark cached-time**: prefix là phần kéo dài của **cùng một** `cachedTime`. `calculateNghiCachedTime()` cộng thêm chuỗi chunk prefix **liên tục ngay sau chunk 0** của chương kế, nên chuỗi phát liên tục được đo **vượt qua biên chương**. Khi chương hiện tại đã hết ứng viên (`selectNghiOptionalRefillCandidate == nil`) mà `cachedTime < nghittsSafeCachedTimeThreshold`, prefix được nạp tiếp cho đủ ngưỡng; đạt ngưỡng thì dừng nạp và **giữ** chunk đã có (không thu hồi). Số chunk bị chặn bởi phần còn trống của `NghiSynthesisPolicy.maxTotalAudioPayloads` (5), tính bằng `preloadedData.count + (hasPreparedNext ? 1 : 0) + (reservesNghiAudioSlot ? 1 : 0)` — phép đếm này cố ý **thiên về bảo thủ** (có thể đếm trùng một payload) để không bao giờ vượt trần.
  - Khi chương hiện tại vẫn còn ứng viên, prefix bị thu hồi về 0 (`capacity: 0`) — chương đang phát luôn được ưu tiên trước.
* Prefix đi qua đúng coordinator của engine ở **mức ưu tiên thấp nhất** (`.optionalReserve` cho Nghi, `.nextChapter` cho remote) và **không** có vòng retry riêng ở tầng manager.
* **Mọi cấu hình chunk/pacing của cửa sổ đoạn văn đều được áp cho prefix**:
  - *Số ký tự mỗi phân đoạn*: đã nằm trong `key.chunkLength` (với extension là `max_length` từ JSON config). Remote tiêu thụ DTO đã chunk hoá bởi `TTSBackgroundProcessor.processChapter(chunkLength: key.chunkLength)`; Nghi chunk lại bằng `NghiUtteranceSegmenter.expand(_:maximumLength: key.chunkLength)`.
  - *Khoảng giãn giữa các request remote*: `TTSAudioSynthesisWorker.synthesizeParagraph(offset: index, prefetchDelayMs: prefetchDelayMs)` — cùng cơ chế `sleep(offset × max(300, prefetchDelayMs))` như prefetch trong chương (`googlePrefetchCount`/`prefetchDelayMs` của Google, `extPrefetchDelay_<tool>` của extension). NghiTTS không có cấu hình này nên không áp; nó được điều tiết bằng watermark + `PiperSynthesisCoordinator`.
  - Ngoại lệ có chủ ý: **chunk 0** chương kế (do `TTSChapterPrefetcher.startAudioSynthesis` sở hữu) vẫn dùng `offset: 0, prefetchDelayMs: 0` vì đó là slot bắt buộc cần có sớm nhất; chỉ các chunk prefix đầu cơ mới bị giãn.
* **Highlight của prefix hoạt động y hệt chunk thường, và không thể lệch.** Highlight do `commitAudibleParagraphState` phát ra từ `paragraphs[index].range`/`paragraphs[index].paragraphIndex` của chương **đã áp dụng**, hoàn toàn độc lập với nguồn gốc của byte audio; đường phát chunk từ cache vẫn gọi `commitAudibleParagraphState` (remote: `playAudioData` sau `player.play()`; Nghi: `NghiAudioPlayerQueue.onTransition`/`onScheduleHandoff` với `item.paragraphIndex`). Điều kiện duy nhất là audio ở `index` phải là audio của đúng `paragraphs[index]`, và nó được cưỡng chế **hai lớp**: (1) `consume(matching:)` yêu cầu `TTSPreparedNextChapterKey` trùng tuyệt đối; (2) `mergeNextChapterPrefixAudio` còn so `PreparedChunk.finalText` với `applyReplacements(paragraphs[index].text)` đã trim — lệch thì bỏ chunk đó (log `textMismatch`) và chương mới tổng hợp lại như bình thường. Nhờ lớp (2), mọi trường hợp DTO bị dựng lại (fallback load, force-refresh nội dung) đều an toàn dù key không đổi.
* Mọi chunk gắn với đúng một `TTSPreparedNextChapterKey`. `consume(matching:)` chỉ trả dữ liệu khi key trùng tuyệt đối; key được dựng lại tại `applyNextChapter` từ `TTSChapterInfo` của chương vừa áp dụng, nên đổi giọng/pitch/chunkLength/cờ dịch/từ điển giữa lúc nạp trước và lúc chuyển chương luôn làm dữ liệu cũ bị loại thay vì phát sai cấu hình.
* Chunk hoá của prefix dùng `key.chunkLength` (không dùng giá trị hiện hành của manager) để index luôn nhất quán với chính key mà nó được lưu dưới.
* **Chống lặp và chống ghi trễ, dùng lại đúng cơ chế của cửa sổ đoạn văn**:
  - Mỗi task prefix mang một token theo index; `finishSynthesis` chỉ ghi khi khớp cả `generation`, `activeKey` **và** token — tương ứng `removePrefetchTask(for:taskGen:)` của prefetch trong chương, tránh task cũ đã bị `trim` hủy xóa mất entry của task mới.
  - Lỗi được phân loại bằng **chính** `TTSManager.evaluateRefillError(_:currentAttempts:maxAttempts: 2)` (single source với refill NghiTTS): non-retryable hoặc hết 2 attempt thì index bị block tới khi `reset()`; audio rỗng bị block ngay từ attempt đầu; `CancellationError` không tính attempt và không log.
  - Prefix **không** có retry task/backoff riêng: attempt kế tiếp chỉ xảy ra ở lần đánh giá cửa sổ tiếp theo.
* Pause hủy tổng hợp prefix đang bay nhưng **giữ** chunk đã xong và trạng thái lỗi (`cancelPendingWork`); stop, đổi `tool` và đổi `selectedVoice` giải phóng toàn bộ qua `clearAllTTSCaches` → `resetNextChapterPrefixCache`.

## Normative Architecture Rules (Refactor v4.1/v4.2/v5.0)

* **Physical File Line Limit**: New Swift files created during refactoring must stay <= 400 physical lines. Legacy files exceeding 400 lines are tracked in `Scripts/architecture_allowlist.json` and must ratchet downward.
* **One Primary Type Per File**: Each Swift file must declare exactly one primary type (class, struct, enum, or actor).
* **SwiftData Write Coordinators**: SwiftUI Views must not perform direct `modelContext` write mutations (`insert`, `delete`, `save`). All write transactions are owned by domain transaction coordinators (`ExtensionTransactionCoordinator`, `BookTransactionCoordinator`) accepting immutable Command DTOs/IDs.
* **Services Layer Boundaries**: `Sources/Services/` must not import `SwiftUI` and must not invoke `ToastManager.shared` directly. The `SERVICE_SWIFTUI_IMPORT` check exempts only files whose name ends with `WebViewLoader.swift` (currently `WebViewLoader.swift` and `VisibleWebViewLoader.swift`); as of this revision no Services file imports SwiftUI at all, so the exemption is a standing allowance rather than an active carve-out.
* **Presentation Event Center**: UI presentation events (toasts) emitted by background services use thread-safe `AsyncStream` event centers (`TTSPresentationEventCenter`, `DownloadPresentationEventCenter`) with `AppLaunchRootView` as the sole UI presentation subscriber.
* **VBook JS Runtime Boundaries**: Extraction operations use short-lived `JSExecutor` instances; only `ExtTTSRuntime` may persist a long-lived runtime. All extension calls must preserve `execute(...)`, `runAsync`, global API injections (`Html`, `Engine`, `Response`, `fetch`), and root vs `src/` script path resolution.
* **Logging and Observability**: Log via `AppLogger.shared` with structured tags; do not use raw `print`. Never log secrets, full chapter payloads, or sensitive user data.
* **Security**: Enforce `validatePathSafety(for:)` on all physical file operations. Validate external URLs and input data at extension boundaries. Never expose API keys.
* **Test Layer Removed (1.3.235, user-directed)**: tầng test không còn tồn tại — `Tests/` và target `FreeBookTests` đã bị xoá khỏi repo và `project.yml`. Không tạo lại thư mục `Tests/` hay target test khi người dùng chưa yêu cầu rõ ràng. Xác minh tính đúng dựa trên đọc code, build trên macOS và hai script tĩnh (`validate_links.py`, `check_architecture.py`); không được viện dẫn test làm bằng chứng.
* **UI Views & Event Handlers**: SwiftUI Views must perform zero direct file I/O or SwiftData mutations. `@Query` reads are permitted for reactive presentation only; user actions must dispatch command DTOs to Coordinators.
* **Code Placement Naming Matrix**:
  - `View`: SwiftUI visual interface element under `Sources/Views/`
  - `ViewModel`: `@MainActor` state model binding View to Services/Coordinators
  - `Coordinator`: Domain transaction or flow manager handling multi-step processes or persistence
  - `Repository`: Single source of truth data access layer for domain entities
  - `Store`: Specialized low-level persistence engine (e.g., `ChapterStore`, `ReadingProgressStore`)
  - `Service`: Core business logic or platform interface under `Sources/Services/`
  - `Engine`: Low-level execution engine (e.g., `JSExecutor`, `ONNXPiperEngine`)
  - `Adapter`: Platform or framework bridge layer
  - `Worker`: Background unit of work actor/task (e.g., `BackgroundPagingWorker`)
  - `DTO` / `Command`: Immutable value types representing transactions or payloads
  - `Snapshot`: Immutable thread-safe copy of entity state for cross-isolation transport
  - `Mapper` / `Formatter`: Pure functional converter between models or text formatting

* **Add-Code Checklist**:
  1. Primary directory placement: `Sources/App`, `Sources/Common`, `Sources/Models`, `Sources/Services`, `Sources/Views`.
  2. Dependencies: Views -> ViewModel/Coordinator -> Services/Repositories -> Models. Views MUST NOT import SwiftData or perform direct `modelContext` write mutations.
  3. Physical Line Limit: Max 400 lines for new files; legacy allowlisted files must ratchet down.
  4. Exactly 1 primary type per file.
  5. Services must not import SwiftUI (exemption matches file names ending `WebViewLoader.swift`) or invoke ToastManager.shared.
  6. Không tạo lại `Tests/` hay target test (tầng test đã bị xoá ở 1.3.235).
  7. CodeGraph docs must be updated factually and validated with `validate_links.py`.

## Thermal State Invariants (Phase 0.1)

* `ProcessInfo.ThermalState` is diagnostic/logging-only for NghiTTS and does not cancel or suppress audio refill or next-chapter prefetch.

## NghiTTS safeCachedTimeSeconds prefetch and contiguous scheduler invariants (1.3.116)

* `nghittsSafeCachedTimeSeconds` is a user-configurable, persistent NghiTTS duration setting (`UserDefaults` key `"nghittsSafeCachedTimeSeconds"`, default 8.0s, allowed 4.0...20.0s, UI step 1.0s). Old installations without the key fallback to 8.0s without error.
* `cachedTime` counts only the contiguous playable audio chain at the current playback rate: current player remaining time + prepared $N+1$ + sequential preloaded $N+2...$, stopping at the first missing gap. Chapter $K+1/0$ is counted only when every remaining chunk in chapter $K$ is ready and $K+1/0$ audio is ready.
* Immediate successor $N+1$ and chapter $K+1/0$ are mandatory slots. When `cachedTime < nghittsSafeCachedTimeSeconds`, optional reserve chunks ($N+2, N+3$) are synthesized sequentially up to at most 2 optional reserve items. Max 5 logical audio payloads total (current + $N+1$ + 2 optional + $K+1/0$).
* When `cachedTime >= nghittsSafeCachedTimeSeconds`, refill stops and one cancellable deadline sleep task (`nghiWakeTask`) is scheduled to wake when `cachedTime` is predicted to cross the threshold. No polling loops.
* `PiperSynthesisCoordinator` uses a 4-level priority queue (`demand = 4` > `immediateSuccessor = 3` > `nextChapterMandatory = 2` > `optionalReserve = 1`). Exact synthesis keys coalesce duplicate requests, promote pending priority, and claim in-flight ONNX inference on demand.
* Pause cancels queued speculative requests (`cancelPendingRequests()`) while allowing an active ONNX inference to complete and cache. While paused, audio does not autoplay or chain further speculative refill.
* Thermal state (`ProcessInfo.ThermalState`) is diagnostic/logging-only for NghiTTS and does not cancel or suppress audio refill or next-chapter prefetch.
* Changing `nghittsSafeCachedTimeSeconds` during active playback reschedules `nghiWakeTask` and re-evaluates refill immediately without clearing valid preloaded audio or interrupting playback. Opening/closing Settings when ONLY `nghittsSafeCachedTimeSeconds` changed does not stop/restart playback, rebuild paragraphs, or clear preloaded audio.

## Chapter repository memory and cancellation invariants (1.3.114)

* `ChapterContentRepository` is the sole shared chapter-content cache and must bound normalized documents by both recency and estimated memory cost: at most 12 entries and 12 MiB. A single document larger than the cost budget bypasses shared RAM caching but is still returned to its caller and may remain persistent on disk.
* A memory warning clears only reusable repository RAM snapshots. Documents already retained by Reader/TTS, in-flight subscriber state, and persistent chapter content remain valid.
* One in-flight chapter operation may serve multiple Reader/TTS subscribers. Canceling a subscriber must resume only that waiter with `CancellationError`; the underlying operation is canceled only after its final waiter leaves. Force refresh supersedes the prior operation and cancels all of its waiters.
* Cancellation from the final waiter must propagate through persistent lookup and extension execution. Once fetched content has passed the final cancellation checkpoint and entered shared memory, its background persistence write must not be canceled by Reader dismissal.
* `TTSManager` must own fallback auto-advance work. Stop, engine/session replacement, or a newer chapter advance cancels the prior task; canceled/superseded work must not stop playback as an ordinary load failure or commit stale chapter state. If repository force-refresh supersedes only the shared load while playback itself remains active, auto-advance may reattach once to the replacement operation.

## TTS presentation energy invariants (1.3.112)

* The floating TTS cover must remain static during sustained playback; a continuously scheduled `TimelineView` or display-rate decorative animation is forbidden. Expanded/peeking mode changes must reuse the parent-owned decoded image and must not start a new cover load.
* App root, Shelf, Reader, and floating widget must not observe the entire `TTSManager` when they render only a subset of its state. Projection readers publish deduplicated snapshots, and Reader highlight state must collapse to inactive when the playing `bookId` does not match its scoped book.
* Lock Screen book title, chapter title, translation result, and artwork are static metadata keyed by book/chapter/cover/translation generation. Only one static metadata task may be active; paragraph transitions update only timeline, progress, speed, and playback state.
* NghiTTS model preparation is lazy: app initialization may warm the model only when `tool == "nghitts"`; selecting another engine cancels pending warm-up.

## TTS highlight coordinate invariants (1.3.81, supersedes 1.3.80)

* `TTSParagraph.range` is expressed in UTF-16 offsets of the **displayed** string (`TTSLineEntry.translatedText` — the translated line when VietPhrase is on, the original line when it is off) and is **relative to its parent line**, not absolute within the chapter. `TTSParagraph.sourceRange` is the range mapped back onto the original text.
* Reader and TTS share one coordinate space by construction: `TTSBackgroundProcessor.processChapter` translates **line by line first**, then rebuilds through `reconstructContentPreservingLineIDs` → `ChapterTextNormalizer.normalizeProcessedContent`, so the TTS `normalizedContent` and Reader's `ParagraphItem` list describe the same string.
* Therefore `ReaderView` passes `ttsState.snapshot.highlightRange` **directly** to `ParagraphCardView` → `ReaderTextView` with no remapping. Correctness is enforced by identity guards (`playingBookId`, `playingChapterIndex`, `currentParentParagraphIndex`), not by coordinate translation.
* `ReaderSelectionMapper.mapHighlight`, `mappedRangeUsingOriginalSpans`, and `proportionalHighlightFallback` were removed in 1.3.81 because the pipeline no longer produces a coordinate mismatch. **Do not reintroduce them and do not wrap the highlight range in any mapper.**
* `ReaderSelectionMapper` retains only the reverse direction for user selection: `mapSelection(_:in:isTranslationEnabled:bookId:)` maps a selection on the displayed string back onto the original text for dictionary lookup. Stored `translationSpans` take precedence; the sentence/token heuristic is fallback-only when spans are empty or do not cover the selection.
* Range validity checks guard against crashes only; they must never be relied on as correctness of alignment.

## Reader/TTS normalized-text invariants (1.3.15)

* `ChapterTextNormalizer` is the only component allowed to canonicalize chapter newlines, remove blank lines, assign paragraph IDs, and calculate UTF-16 ranges.
* `ChapterTextLine.id` is the **raw line index and counts blank lines**, so paragraph IDs are sparse and are never array offsets: `"Một\n\nHai"` yields ids `[0, 2]`. `ParagraphItem.id` and `TTSParagraph.paragraphIndex` inherit that property; always look up by `id`. The chapter-title chunk uses `-1` on both sides.
* `ChapterTextLine.utf16Range` is computed over the string **before** blank lines are dropped, so it must not be used to slice `NormalizedChapterText.content`.
* `ChapterDocument` is created once by `ChapterContentRepository`; Reader and TTS builders must consume its normalized lines without re-splitting or re-numbering.
* TTS chunks may split a line but must retain the parent `ChapterTextLine.id`; replacement output must be non-empty before extension synthesis.
* TTS owns progress while playing. Reader snapshots are ignored during TTS ownership and all checkpoints flush through `ReadingProgressStore` off the MainActor.
* TOC navigation carries an immutable `ReaderRoute.chapterIndex`; filtering and sorting must never convert an original chapter index into a filtered-row offset.
* `ChapterContentRepository` is the only chapter-content loader: memory -> SwiftData -> extension. Non-empty normalized content read via `BookBinManager` based on `Chapter.offset`, `Chapter.length`, and `Chapter.isCached` is authoritative. The production `Chapter` model does not store the text content directly in the database.
* **Sandbox File Security**: All operations on physical files (like cover images or chapter `.bin` files) must perform security validation (`validatePathSafety(for:)`) to ensure files are located inside the application support directory, preventing path traversal attacks.
* **Atomic Database-First Deletion**: When deleting a book, the database model modifications must be committed (via `ModelContext.save()`) successfully before starting the background cleaning task of physical files on a detached background thread.
* **UserDefaults-Backed Deletion Retry**: Failed physical file deletions must be queued in a background retry queue saved in `UserDefaults` (`failed_file_deletions_queue`) and drained on app launch (`drainRetryQueue()`), with a maximum limit of 3 retries per file to prevent resource leaks.
* Reader and TTS may share chapter documents/in-flight loads, but playback/navigation sessions remain isolated by `bookId`, chapter identity, and TTS `sessionID`; a Reader for another book must never prepare or seek the active TTS session.
* Fetched chapter content enters shared memory before background persistence. Reader dismissal must flush, not cancel, pending chapter writes.

## Reader paragraph invariants (1.3.14)

* Split original chapter content before translation. Each original line, including an empty or trailing line, must produce exactly one translated line and one `ParagraphItem` with the same stable index.
* All selection and translation offsets exchanged with UIKit must use UTF-16 `NSRange` semantics.
* The definition editor must resolve `chapterIndex + paragraph id` and use `ParagraphItem.original` as its only source text; translated text may only be used to map the selected range.
* Exact stored spans take precedence. The historical sentence/token heuristic is fallback-only when span coverage is missing or invalid.

## 1. Thứ tự Ưu tiên Thẩm quyền (Priority of Authority / Source of Truth Hierarchy)

Thứ tự ưu tiên thẩm quyền của tài liệu và mã nguồn khi xảy ra xung đột thông tin được định nghĩa theo cấp bậc sau:
1.  **`Docs/CodeGraph/rules.md`** (Normative Specification / The current approved technical specification. Unless explicitly changed by the user or project maintainers, AI must treat it as the authoritative technical standard).
2.  **`Source Code`** (Actual Implementation / Triển khai thực tế - những gì code đang thực thi).
3.  **`Docs/CodeGraph/*`** (Descriptive Documentation / Tài liệu mô tả - những gì tài liệu mô tả về mã nguồn).
4.  **Các tài liệu khác** (Other documentation).

> [!NOTE]
> **This authority order is only used to resolve conflicts between artifacts. It does not define the normal development workflow.**
> *(Thứ tự ưu tiên thẩm quyền này chỉ được sử dụng khi xảy ra xung đột giữa các tài liệu hoặc mã nguồn. Nó không định nghĩa hay thay thế quy trình phát triển thông thường).*

*   **Bản chất**: `rules.md` là tài liệu quy phạm (những gì dự án cần tuân thủ), trong khi `Docs/CodeGraph/*` là tài liệu mô tả (những gì mã nguồn đang thực thi hiện tại).
*   **Quy trình xử lý sai lệch (Deviation Handling)**: AI phải thực hiện quy trình sau khi phát hiện sự sai lệch:
    *   **Xác minh**: Kiểm tra xem sai lệch là **chủ ý thiết kế mới** (intentional change) hay là **lỗi lập trình** (stale/bug).
    *   **Lỗi / Sai lệch**: Tiến hành sửa đổi `Source Code` để tuân thủ quy chuẩn trong `rules.md`.
    *   **Quy tắc cũ / Thay đổi kiến trúc**: Cập nhật `rules.md` trước (chỉ khi bản thân quy chuẩn kỹ thuật của dự án thay đổi) để ghi nhận quy tắc mới $\rightarrow$ Đồng bộ `Source Code` (nếu cần) $\rightarrow$ Cập nhật `Docs/CodeGraph/*` tương ứng để phản ánh trạng thái thực tế mới.
    *   **Yêu cầu trực tiếp từ người dùng (User-directed change)**: Nếu người dùng hoặc maintainer yêu cầu thay đổi tính năng, kiến trúc hoặc quy tắc (chỉ áp dụng khi yêu cầu của người dùng có sửa code):
        1. Thực hiện thay đổi theo yêu cầu trên **Source Code**.
        2. Đánh giá xem thay đổi đó có làm thay đổi quy chuẩn của dự án (**`rules.md`**) hay không.
        3. Nếu có, cập nhật **`rules.md`**.
        4. Cuối cùng cập nhật **`Docs/CodeGraph/*`** để phản ánh trạng thái mới.
    *   **Trường hợp không rõ (UNKNOWN)**: Nếu AI không đủ bằng chứng để xác định liệu sai lệch là chủ ý hay lỗi, **bắt buộc phải đánh dấu UNKNOWN** và yêu cầu người dùng xác nhận thay vì tự suy đoán.
    *   **Không tự ý sửa**: Tuyệt đối không tự ý sửa `Source Code` chỉ để khớp với `rules.md` khi chưa xác minh `rules.md` vẫn là quy tắc hiện hành.

*   **Lưu ý**: Đa số các tính năng thông thường (ordinary features) không cần sửa `rules.md`.

*   **Ví dụ minh họa (Examples)**:
    *   *Code khác CodeGraph* $\rightarrow$ Cập nhật CodeGraph.
    *   *Code khác rules.md vì rules.md cũ* $\rightarrow$ 1. Cập nhật rules.md; 2. Đồng bộ Source Code (nếu cần); 3. Cập nhật Docs/CodeGraph/* để phản ánh trạng thái mới.
    *   *Code khác rules.md do bug* $\rightarrow$ Sửa Source Code để tuân thủ rules.md.
    *   *Người dùng yêu cầu thay đổi tính năng/kiến trúc* $\rightarrow$ 1. Sửa Source Code; 2. Đánh giá và cập nhật rules.md (nếu đổi quy chuẩn); 3. Cập nhật Docs/CodeGraph/*.

---

## 2. Quy tắc Bảo trì CodeGraph (Maintenance Rules)

*   **Không tạo lại toàn bộ (No Full Regeneration)**: Chỉ phân tích và chỉnh sửa các tài liệu bị ảnh hưởng trực tiếp bởi thay đổi code. Giữ nguyên các tài liệu khác.
*   **Bảo vệ ghi chú của con người (Preserve Human Edits)**:
    *   Mọi nội dung tự động sinh bởi AI nằm trong khối comment bắt đầu bằng `GENERATED_START` và kết thúc bằng `GENERATED_END` (không chứa khoảng trắng để tránh xung đột parser).
    *   AI chỉ được phép chỉnh sửa nội dung bên trong vùng này.
    *   **Tuyệt đối không** ghi đè, xóa hoặc sửa đổi bất kỳ nội dung nào nằm ngoài vùng này.
*   **Đồng bộ khi Rename / Delete / Move file**:
    *   If a Swift file is renamed, moved, or deleted, the AI must update all relative path references in `Docs/CodeGraph/` and remove orphan references.

---

## 3. Quy tắc Kích hoạt Cập nhật (Trigger Rules)

CodeGraph bắt buộc phải được đồng bộ hóa lập tức khi có bất kỳ thay đổi nào sau đây:
*   Thêm file mới, xóa file hoặc di chuyển/đổi tên file Swift.
*   Thay đổi Public API của các Manager, Service, hoặc ViewModel.
*   Thay đổi định nghĩa Protocol.
*   Thay đổi mối quan hệ phụ thuộc (Dependency) giữa các thành phần.
*   Thay đổi Máy trạng thái (State Machine) điều khiển TTS, Tải xuống, hoặc Đọc truyện.
*   Thay đổi quan hệ sở hữu đối tượng (Ownership Graph).
*   Thay đổi luồng điều hướng màn hình (Navigation).
*   Thay đổi cấu trúc mô hình SwiftData (`@Model`).
*   Thay đổi cấu hình Audio Pipeline (`AVAudioEngine`, `AVAudioSession`) hoặc TTS Pipeline.

---

## 4. Kiến thức Dự án & Cấu trúc Thư mục (Project Knowledge)

### 4.1. Cấu trúc thư mục mã nguồn
Dự án FreeBook được tổ chức theo cấu trúc phân tầng nghiêm ngặt:
*   **Common (`Sources/Common`)**: Chứa các thành phần dùng chung cho toàn dự án.
    *   `Extensions/`: Các phần mở rộng (Extensions/Helpers) dùng chung (`String+HTML.swift`, `View+Keyboard.swift`, `String+Crypto.swift`...).
    *   `Services/`: Các Service/Manager dùng chung cho toàn bộ ứng dụng (`ImageCacheManager.swift`, `ToastManager.swift`...).
*   **Models (`Sources/Models`)**:
    *   `Database/`: All SwiftData persistable model classes (`Book`, `Chapter`, `Extension`, `Repository`, `DownloadTaskModel` — the `ModelContainer` schema in `FreeBookApp.swift` registers all five).
    *   `Dictionaries/`: All translation lookup data structure classes (`DoubleArrayTrie`, `TextDictionary`, `SearchEngine`).
*   **Views (`Sources/Views`)**: Tổ chức thành các thư mục con theo module chức năng độc lập:
    *   `Shelf/ShelfMain/`: Chỉ chứa kệ sách chính (`ShelfView.swift`).
    *   `Discovery/`: Tab Khám phá (`DiscoveryView.swift`).
    *   `BookDetail/`: Chi tiết sách (`BookDetailView.swift`).
    *   `Search/`: Tìm kiếm truyện (`SearchView.swift`).
    *   `Reader/`: Trình đọc truyện (`ReaderView.swift` và các view phụ trợ).
    *   `TTSWidget/`: Floating widget điều khiển giọng đọc trên trình đọc.
    *   `Dictionary/`: Tra cứu từ điển (`DictionaryHubView.swift`, `DictionaryListView.swift`...).
    *   `Download/`: Quản lý tiến trình tải sách (`DownloadTrackerView.swift`, `TaskOptionsSheet.swift`).
    *   `Extensions/`: Quản lý extension, chia làm các thư mục con `Config/`, `Store/`, `Manager/`.
    *   `Settings/`: Cấu hình hệ thống, chia làm các thư mục con `Main/`, `Search/`, `TTS/`.
    *   `Common/`: Các view phụ trợ dùng chung (`BypassWebView.swift`, `DocumentPicker.swift`, `BookCoverView.swift`...).
*   **Services (`Sources/Services`)**: Tổ chức thành các thư mục con theo mảng dịch vụ chức năng:
    *   `TTS/`: Dịch vụ phát âm TTS.
        *   Thư mục gốc `TTS/`: Các bộ điều khiển và định nghĩa dùng chung (`TTSManager.swift`, `EspeakPhonemizer.swift`, `WAVEncoder`...) và thư mục `Preprocessing/`.
        *   `NghiTTS/`: Chứa client NghiTTS và lõi Piper offline (`ONNXPiperEngine.swift`, `PiperTTSService.swift`, `ModelStore.swift`).
        *   `Siri/`: Chứa dịch vụ phát âm native Siri (`SiriTTSService.swift`).
        *   `Ext/`: Chứa dịch vụ phát âm qua Extension JS (`ExtTTSService.swift`).
    *   `Extensions/`: Engine chạy extension javascript.
        *   `Engine/`: Core thực thi JS (`JSExecutor.swift`, `JSDom.swift`, `JSCrypto.swift`).
        *   `Manager/`: `ExtensionManager.swift`.
    *   `Translation/`: Dịch thuật tự động.
        *   `Manager/`: `TranslationManager.swift`.
        *   `Utils/`: `TranslateUtils.swift`, `DictionaryCache.swift`.
    *   `Download/`: `DownloadManager.swift`, `BookDownloadWorker.swift`, `DownloadTaskOutcomeCalculator.swift`.
    *   `Logging/`: `AppLogger.swift`.

### 4.2. JavaScript Core Runtime & VBook Extensions Integration
*   **Script Entrypoint**: Tên hàm bắt đầu thực thi bên trong toàn bộ các tệp JavaScript (`search.js`, `detail.js`, `toc.js`, `chap.js`, `genre.js`, `home.js`) phải là `execute(...)`, được gọi bất đồng bộ qua `runAsync` trong `ExtensionManager.swift`.
*   **Script File Path Resolution**: Các tệp JS script có thể đặt ở thư mục gốc của extension hoặc trong thư mục `src/`. `ExtensionManager` sẽ quét cả hai vị trí này.
*   **Injected Global JS Objects**: Các đối tượng global được inject vào `JSContext`:
    *   `Html`: Parser cầu nối DOM (`Html.parse(...)`, `element.attributes()`, `elements.isEmpty()`, `elements.map()`).
    *   `console`, `Console`, `print`, `Log`: Chuyển hướng `log` ra console in logs (`AppLogger`).
    *   `fetch`: API tải mạng đồng bộ/bất đồng bộ kèm `response.statusText`, `url`, `headers`, `header()`, `blob()`, `request`.
    *   `Response`: `Response.success(data)` và `Response.error(message)`.
    *   `Engine`: Headless browser giả lập (`Engine.newBrowser()`, `newVisibleBrowser()`).
    *   `Qt`: Quick Translator bridge (`Qt.translate(text, to, extras)`) và các tiện ích mã hóa.
    *   `localStorage`, `cacheStorage`, `localConfig`, `localCookie`: Hệ thống lưu trữ và cấu hình tiện ích mở rộng.
    *   `UserAgent`, `Crypto`, `Script`, `Http`: Các bộ công cụ giả lập môi trường VBook Android & WebKit.

---

## 5. Các Quy định Lập trình chi tiết (Coding Rules)

### 5.1. SwiftData Rules
*   **Tên**: Không sử dụng bộ lọc chuỗi trên Predicate trong `@Query`
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Tránh viết các câu lệnh truy vấn lọc chuỗi trực tiếp trong Predicate của SwiftUI `@Query`. Thay vào đó, hãy query toàn bộ danh sách và thực hiện lọc trên RAM bằng computed property.
*   **Lý do**: Bộ dịch truy vấn SQLite của SwiftData trên iOS 17 gặp lỗi dịch câu lệnh chuỗi gây ra kết quả không chính xác hoặc lỗi biên dịch.
*   **Ví dụ đúng**:
    ```swift
    @Query private var allExtensions: [Extension]
    private var activeExtensions: [Extension] {
        allExtensions.filter { !$0.localPath.isEmpty && $0.isEnabled }
    }
    ```
*   **Ví dụ sai**:
    ```swift
    @Query(filter: #Predicate<Extension> { !$0.localPath.isEmpty && $0.isEnabled })
    private var activeExtensions: [Extension]
    ```

### 5.2. Architecture Rules
*   **Tên**: Không import SwiftUI vào các lớp nghiệp vụ Manager / Service
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Tầng Manager và Service tuyệt đối không được import framework `SwiftUI` hay giữ tham chiếu đến giao diện (View).
*   **Lý do**: Đảm bảo tính độc lập của logic nghiệp vụ, phục vụ unit testing dễ dàng và ngăn chặn rò rỉ bộ nhớ.
*   **Ví dụ đúng**:
    ```swift
    // Trong Sources/Services/Translation/Manager/TranslationManager.swift
    import Foundation
    public final class TranslationManager: ObservableObject { ... }
    ```
*   **Ví dụ sai**:
    ```swift
    import SwiftUI
    public final class TranslationManager: ObservableObject {
        var statusLabelView: Text? // Vi phạm kiến trúc
    }
    ```

### 5.3. Concurrency Rules
*   **Tên**: Sử dụng ModelContext riêng biệt cho tác vụ chạy nền (Background Tasks)
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Mọi thao tác ghi hoặc cập nhật thực thể SwiftData trong các tác vụ nền phải tạo một `ModelContext` mới từ `ModelContainer` dùng chung và không dùng chung context với MainActor.
*   **Lý do**: Tránh lỗi tranh chấp dữ liệu và lỗi crash truy cập sai luồng của SwiftData.
*   **Ví dụ đúng**:
    ```swift
    private func executeTask(_ task: DownloadTask, container: ModelContainer) async {
        let bgContext = ModelContext(container)
        let allBooks = (try? bgContext.fetch(FetchDescriptor<Book>())) ?? []
        try? bgContext.save()
    }
    ```
*   **Ví dụ sai**:
    ```swift
    private func executeTask(_ task: DownloadTask, container: ModelContainer) async {
        let allBooks = (try? viewModel.modelContext.fetch(FetchDescriptor<Book>())) ?? []
        try? viewModel.modelContext.save()
    }
    ```

### 5.4. SwiftUI Rules
*   **Tên**: Lưu bookmark tiến độ đọc truyện khẩn cấp khi chuyển nền
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: View chính của trình đọc phải lắng nghe sự kiện thay đổi trạng thái của app (`scenePhase == .background`) để lưu bookmark vị trí đọc hiện tại ngay lập tức.
*   **Lý do**: Hệ điều hành iOS có thể chấm dứt ứng dụng chạy ngầm bất cứ lúc nào để giải phóng RAM, gây mất bookmark của người đọc nếu không lưu kịp thời.
*   **Ví dụ đúng**:
    ```swift
    .onChange(of: scenePhase) { _, newPhase in
        if newPhase == .background {
            viewModel?.saveProgressImmediately()
        }
    }
    ```
*   **Ví dụ sai**:
    ```swift
    .onDisappear {
        viewModel?.saveProgressImmediately()
    }
    ```

### 5.5. Audio Rules
*   **Tên**: Tránh chặn Main Thread bằng Semaphore khi tải WebView ngầm
*   **Loại quy tắc**: **Recommended Rule**
*   **Mô tả**: Không sử dụng `DispatchSemaphore` chờ đồng bộ trên Main Thread khi chạy `WKWebView` để bypass Cloudflare hoặc nạp web động.
*   **Lý do**: Gây hiện tượng Deadlock vĩnh viễn vì WKWebView yêu cầu chạy trên Main Thread nhưng Main Thread lại bị Semaphore khóa cứng.
*   **Ví dụ đúng**:
    ```swift
    func loadWebView(url: URL) async -> String {
        return await withCheckedContinuation { continuation in
            loader.load(url: url) { html in
                continuation.resume(returning: html)
            }
        }
    }
    ```
*   **Ví dụ sai**:
    ```swift
    let semaphore = DispatchSemaphore(value: 0)
    DispatchQueue.main.async {
        loader.load(url: url) { html in
            semaphore.signal()
        }
    }
    _ = semaphore.wait(timeout: .now() + 5.0) // Gây Deadlock vĩnh viễn trên Main Thread
    ```

### 5.6. TTS Rules
*   **Tên**: Dọn dẹp cửa sổ trượt prefetch audio của đoạn văn
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Bộ đệm audio đoạn văn là `preloadedData` (dữ liệu WAV/MP3) đi kèm `preloadedDurations`; mọi index nằm ngoài cửa sổ trượt hiện hành phải bị loại bỏ. Cửa sổ khác nhau theo engine:
    *   Google/Ext (`updatePrefetchWindow`): giữ `[N, N + count]` với `count = max(1, min(10, currentPrefetchCount))` — `currentPrefetchCount` lấy từ `googlePrefetchCount` (2-10) hoặc `preload_size` của extension.
    *   NghiTTS (`updateNghiPrefetchWindow`): giữ đoạn hiện tại `N`, đoạn kế `N + 1` (slot bắt buộc), tối đa `NghiSynthesisPolicy.maxOptionalReserveItems` (2) optional reserve từ `N + 2`, cộng audio chương kế do `TTSChapterPrefetcher` giữ riêng.
*   **Lý do**: Buffer âm thanh thô tiêu tốn rất nhiều bộ nhớ RAM, nếu không dọn dẹp sẽ gây crash app vì cạn bộ nhớ (OOM).
*   **Ví dụ đúng**:
    ```swift
    let cacheKeepIndices = Set(Array(N...(N + count)))
    for idx in preloadedData.keys where !cacheKeepIndices.contains(idx) {
        preloadedData.removeValue(forKey: idx)
        preloadedDurations.removeValue(forKey: idx)
    }
    ```
*   **Ví dụ sai**:
    ```swift
    preloadedData[index] = data // Không bao giờ giải phóng
    ```

### 5.7. Extension Rules
*   **Tên**: Phân tách vòng đời JSExecutor bóc tách, Ext TTS và Tải truyện (Download)
*   **Loại quy tắc**: **Normative Rule**
*   **Mô tả**:
    * Các tác vụ bóc tách nội dung ngắn hạn (`search`, `detail`, `toc`, `home`, `genre`) tiếp tục tạo `JSExecutor` ngắn hạn và giải phóng sau mỗi lần chạy.
    * Ext TTS được phép dùng một `ExtTTSRuntime` actor giữ `JSExecutor` lâu dài cho extension/config đang hoạt động vì TTS gọi cùng script theo từng chunk.
    * Tác vụ tải/xuất truyện của `DownloadManager` sử dụng duy nhất một `BookDownloadWorker` actor cho mỗi sách để giữ `JSExecutor` chạy tuần tự cho toàn bộ các chương của tác vụ đó, hỗ trợ ngắt hủy request tức thì và giải phóng khi hoàn tất.
*   **Lý do**: Bóc tách đơn lẻ cần cô lập trạng thái; Ext TTS và Download cần tránh tạo và bootstrap lại `JSContext` hàng trăm lần liên tục cho cùng một sách.
*   **Ví dụ đúng**:
    ```swift
    public func chap(url: String) async throws -> String {
        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        return try await executor.runAsync(...)
    }

    actor ExtTTSRuntime {
        private var executor: JSExecutor? // Dùng tuần tự cho TTS hiện tại
    }

    actor BookDownloadWorker {
        private var executor: JSExecutor? // Dùng tuần tự cho tác vụ tải/xuất sách hiện tại
    }
    ```
*   **Ví dụ sai**:
    ```swift
    public final class ExtensionManager {
        private let sharedExecutor = JSExecutor() // Dùng chung không kiểm soát cho mọi loại script
    }
    ```

### 5.7.1. Remote TTS Scheduling Rules
* `prefetchDepth` là số chunk muốn giữ trong cache, không phải số request được chạy đồng thời.
* Mọi tổng hợp Google/Ext, kể cả đọc đoạn được chọn và audio chương kế tiếp, phải đi qua `RemoteTTSSynthesisCoordinator` với tối đa một operation đang hoạt động.
* Thứ tự ưu tiên bắt buộc là `current > prefetch > nextChapter`; request cùng key phải được gộp để không tổng hợp trùng.
* Remote TTS prefetch tuần tự 1 worker và không bị điều tiết hay hủy bởi `thermalState`. Extension TTS tự động áp dụng `preload_size` và `max_length` từ JSON config (ẩn trên UI); Google TTS hiển thị `googlePrefetchCount` (2-10 đoạn), Stepper `chunkLength` (50-500 ký tự) và `prefetchDelayMs` (tối thiểu 300ms).
* Mô hình 2 Worker chuyên trách độc lập cho Trình nghe TTS: Worker 1 (`TTSChapterTextWorker`) kích hoạt nạp trước DTO chữ chương $K+1$ khi $N \ge \text{count}/2$ hoặc $\text{remainingParents} \le 3$; Worker 2 (`TTSAudioSynthesisWorker`) tổng hợp âm thanh MP3/PCM vào bộ đệm RAM.
* Đối với Google/Ext, retry chỉ được sở hữu bởi service, tối đa hai attempt tổng cộng cho mỗi synthesis; `TTSManager` không được bọc thêm vòng retry cho Remote TTS.

### 5.7.2. NghiTTS Energy Rules
* NghiTTS synthesis phải tiếp tục đi qua `PiperSynthesisCoordinator` với tối đa một inference đang chạy.
* ORT/XNNPACK mặc định chỉ dùng một worker; không tăng thread count theo số core vì nghe lâu là sustained workload.
* `NghiSynthesisPolicy` là nguồn duy nhất cho watermark cached-time (`defaultSafeCachedTimeThreshold = 8.0`, dải `safeCachedTimeThresholdRange = 4.0...20.0`) và `maxOptionalReserveItems = 2`; không lặp các hằng số này trong manager/prefetcher. Policy này **không** chứa cooldown hay thermal eligibility — đừng thêm vào.
* Thermal state là diagnostic-only cho toàn bộ TTS (Nghi và Remote): nó chỉ cập nhật `TTSManager.currentThermalState` cho telemetry và làm nhãn trong energy log. Không được dùng `.serious`/`.critical` để hủy, điều tiết hay thu hẹp refill, prefetch, hoặc audio chương kế.
* Refill N+1 đang chạy phải được playback demand tái sử dụng; không được hủy rồi tổng hợp trùng cùng đoạn.
* Audio chương kế của NghiTTS do `TTSChapterPrefetcher` sở hữu và chỉ được promote khi chuỗi chunk còn lại của chương hiện tại đã đủ; nó không phải một slot refill của cửa sổ đoạn văn.
* Kết quả sau `TextPreprocessor` không còn ký tự có thể đọc phải được `PiperTTSService` chuyển thành WAV/PCM khoảng lặng hợp lệ. Luồng streaming phải phát đúng một terminal chunk và không chuyển chuỗi rỗng vào ONNX/eSpeak.
* NghiTTS refill được phép retry tại `TTSManager` vì đây là chính sách cửa sổ prefetch, không phải retry nội bộ engine: tối đa hai attempt tổng cộng cho mỗi session/chapter/paragraph (`evaluateRefillError(maxAttempts: 2)`), retry backoff 1 giây, lỗi model/engine/request không retry bị block ngay.
* Trong thời gian chờ backoff, scheduler không được tạo refill thay thế (`canScheduleNghiRefill` chặn khi còn `nghiRefillRetryTask`). Retry task phải xác thực session/chapter/generation, xóa reference của chính nó trước khi gọi lại prefetch, và bị hủy/reset khi stop, đổi session hoặc chuyển chương.
* `CancellationError` không được ghi failure state, log như synthesis failure hoặc lên lịch retry. Index đã block chỉ bị bỏ qua ở prefetch; foreground/on-demand synthesis vẫn giữ quyền thử lại.

### 5.8. Memory Rules
*   **Tên**: Tránh giữ strong reference `self` trong callback âm thanh ngầm
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Dùng `[weak self]` ở các callback schedule buffer hoặc các block xử lý luồng âm thanh ngầm.
*   **Lý do**: Tránh tạo ra strong reference cycle giữ chặt `TTSManager` hoặc View Model trong bộ nhớ RAM, gây rò rỉ bộ nhớ.
*   **Ví dụ đúng**:
    ```swift
    player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
        DispatchQueue.main.async {
            guard let self = self, self.isPlaying else { return }
            self.nextParagraph()
        }
    }
    ```
*   **Ví dụ sai**:
    ```swift
    player.scheduleBuffer(buffer, at: nil, options: []) {
        self.nextParagraph()
    }
    ```

### 5.9. Logging Rules
*   **Tên**: Ghi log ngoại lệ chi tiết của JS Engine ra tệp logs
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Toàn bộ thông tin crash, exception của JS phải được lưu vào file `app_logs.txt` trong thư mục `applicationSupportDirectory` (không phải `Documents`). `AppLogger.init` set `isLoggingEnabled = false` mỗi lần khởi chạy và tự xóa file khi vượt 5 MB, nên phải bật lại trong Settings mới thấy log mới.
*   **Lý do**: Nhà phát triển ứng dụng cài app qua LiveContainer test trực tiếp trên iOS vật lý, không thể debug qua Xcode Console.
*   **Ví dụ đúng**:
    ```swift
    context.exceptionHandler = { context, exception in
        let desc = exception?.toString() ?? ""
        AppLogger.shared.log("❌ JSContext Exception: \(desc)")
    }
    ```
*   **Ví dụ sai**:
    ```swift
    context.exceptionHandler = { context, exception in
        print("❌ JSContext Exception: \(exception)")
    }
    ```

### 5.10. Performance Rules
*   **Tên**: Giới hạn lưu tiến độ đọc (Debounce DB Save)
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Chỉ thực hiện lưu DB tiến độ khi người dùng dịch chuyển ít nhất 3 đoạn văn trở lên và áp dụng trì hoãn lưu 3 giây (`Task.sleep`).
*   **Lý do**: Giảm tần suất ghi đĩa I/O của SwiftData liên tục khi người đọc cuộn trang nhanh, tránh làm đơ/lag UI.
*   **Ví dụ đúng**:
    ```swift
    if abs(newProgress.paragraphIndex - last.paragraphIndex) >= 3 {
        dbSaveTask?.cancel()
        dbSaveTask = Task {
            try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
            repository.saveProgress(newProgress)
        }
    }
    ```
*   **Ví dụ sai**:
    ```swift
    repository.saveProgress(newProgress)
    ```

### 5.11. Testing Rules
*   **Tên**: Kiểm tra chéo toàn bộ liên kết tài liệu phân tích (Cross Validation)
*   **Loại quy tắc**: **Recommended Rule**
*   **Mô tả**: Đảm bảo số lượng file quét trùng khớp với thư mục, không có markdown link bị hỏng, và tất cả UNKNOWN đều ghi rõ nguyên nhân.
*   **Lý do**: Tối ưu hóa bộ tài liệu phân tích để AI assistant có thể hiểu sâu sắc mà không bị đi vào các liên kết chết.
*   **Ví dụ đúng**: Chạy script quét link kiểm tra trước khi hoàn thiện tài liệu.
*   **Ví dụ sai**: Bỏ qua bước kiểm tra liên kết sau khi viết markdown.

### 5.12. Coding Rules
*   **Tên**: Save path plugin gốc vào `downloadUrl` khi đồng bộ repo
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Lưu trực tiếp thuộc tính `path` từ `plugin.json` của repo vào `downloadUrl` của model `Extension`.
*   **Lý do**: Đảm bảo link tải zip của plugin chính xác và thống nhất.
*   **Ví dụ đúng**:
    ```swift
    extension.downloadUrl = item.path
    ```
*   **Ví dụ sai**:
    ```swift
    extension.downloadUrl = "https://raw.githubusercontent.com/.../plugin.zip"
    ```

---

## 6. Quy định mở rộng về Chất lượng Code (AI Expanded Policies)

### 6.1. Quy tắc Biên dịch & An toàn Concurrency (Compile & Concurrency Rules)
- **Compile Rule**: Mọi thay đổi mã nguồn phải cố gắng giữ khả năng biên dịch thành công của dự án. Tránh tuyệt đối các lỗi về thiếu ký hiệu (missing symbols), vi phạm Actor isolation (`@MainActor`), xử lý sai luồng SwiftData (phải dùng background context riêng) và vòng lặp tham chiếu mạnh (retain cycles/strong reference).
- **UNKNOWN Rule**: Khi xây dựng các đồ thị phân tích (Call Graph, State Machine, Ownership Graph, Dependency, Event Graph), nếu phương pháp phân tích tĩnh (static analysis) không thể chứng minh hoặc xác thực một mối quan hệ/đường gọi cụ thể (ví dụ: callback, dynamic dispatch, dynamic event), bắt buộc phải đánh dấu mối quan hệ đó là `UNKNOWN` hoặc `PARTIAL` kèm theo lý do cụ thể, tuyệt đối không được tự ý suy đoán dựa trên kinh nghiệm.

### 6.2. Quy trình Validation & CodeGraph Refresh Policy
- **Validation Failure Policy**: Chạy `python Docs/CodeGraph/validate_links.py`. Nếu kịch bản phát hiện bất kỳ lỗi nào (như tệp manifest không khớp, liên kết chết, sai định dạng front matter hoặc GENERATED comment), AI bắt buộc phải sửa lỗi và chạy lại; không được báo cáo hoàn thành khi validation chưa PASS 100%.
- **Doc Routing Policy (manifest `schemaVersion: 2`)**: Mỗi doc khai `sourcePatterns` (glob tương đối gốc repo) là phạm vi mã nguồn nó chịu trách nhiệm mô tả, cộng `staleOn`:
  * `staleOn: "structure"` — doc chỉ bị stale khi *tập* file khớp pattern thay đổi (thêm/xoá/đổi tên). Dùng cho doc mô tả bản đồ file và số liệu tổng: `00_index.md`, `02_file_graph.md`, `09_dependency_rules.md`, `14_complexity_report.md`.
  * `staleOn: "content"` — doc bị stale khi tập file thay đổi *hoặc* nội dung file trong phạm vi thay đổi. Dùng cho doc mô tả hành vi: `01_project.md`, `03`–`08`, `10`–`13`, `rules.md`.
  * **Coverage Rule (hai điều kiện, validator FAIL kèm tên file nếu vi phạm)**: (1) mọi file `Sources/**/*.swift` phải khớp `sourcePatterns` của ít nhất một doc; (2) mọi file phải được ít nhất một doc `staleOn: "content"` phủ — nếu một file chỉ nằm trong doc `structure` thì sửa nội dung nó sẽ không làm doc nào stale, đúng lỗ hổng khiến "đổi logic mà tài liệu không đổi". `11_subsystems.md` phủ toàn bộ `Sources/Services/**` + `Sources/Views/**` để giữ điều kiện (2); thêm thư mục mã nguồn mới thì phải mở rộng pattern của doc phụ trách.
  * Sửa `sourcePatterns` là thay đổi hợp đồng routing: chạy `--bootstrap` để tính lại toàn bộ hash, và chỉ dùng cờ này cho đúng mục đích đó.
- **Manifest Hash Policy**: `structureHash` là SHA-256 của *tập đường dẫn* khớp `sourcePatterns` (đổi khi thêm/xoá/đổi tên file); `sourceHash` là SHA-256 của đường dẫn + nội dung đã chuẩn hoá LF (đổi khi sửa logic); `generatedHash` là SHA-256 của nội dung giữa cặp marker GENERATED đã chuẩn hoá LF. Ba hash này chỉ được ghi lại qua validator, không sửa tay.
- **Doc Review Policy**: Sau thay đổi source, chạy `--explain` (thêm `--since REF` để so với một commit) để biết doc nào bị stale và vì sao, rồi ghi nhận từng doc:
  * `--accept DOC…` — doc đã được sửa. Validator **từ chối** nếu vùng GENERATED của doc đó không đổi, nên không thể "bless" hàng loạt mà không thực sự viết lại tài liệu.
  * `--no-change-needed DOC…` — đã đọc doc, kết luận nội dung vẫn đúng với code mới. Lựa chọn này được ghi vào `reviewMode`/`reviewedAt`/`reviewedCommit` để có audit trail; đây là cách hợp lệ duy nhất để bỏ qua một doc bị stale.
  * `--update-hashes` — accept mọi doc có vùng GENERATED đã đổi, sau đó **FAIL** nếu còn doc stale (liệt kê doc còn lại). Nó không còn là lệnh xoá sạch tín hiệu stale như trước.
  * `DOC` nhận `08`, `08_lifecycle.md` hoặc đường dẫn đầy đủ.
- **Full CodeGraph Refresh Policy**: Khi phát sinh các thay đổi mang tính cấu trúc lớn, tái cấu trúc thư mục dự án hoặc chỉnh sửa đồng loạt trên khoảng 20 file mã nguồn Swift trở lên, AI phải đề xuất hoặc thực hiện làm mới toàn bộ hệ thống CodeGraph (Full CodeGraph Refresh) để đảm bảo tính đồng bộ hoàn toàn.

### 6.3. Thiết kế Kiến trúc & Tối ưu hóa Hiệu năng (Performance & Memory Rules)
- **Architecture Decision Rule**: Ưu tiên tối đa việc tái sử dụng các lớp Manager, Service và ViewModel sẵn có trong dự án (ví dụ: `TTSManager`, `ExtensionManager`, `DownloadManager`, `TranslationManager`). Tránh tạo ra duplicate logic hoặc tự ý xây dựng lại các kiến trúc thiết kế mới song song nếu không có yêu cầu cụ thể từ người dùng.
- **Logging Rule**: Mọi log runtime trong mã nguồn Swift hoặc engine JS phải sử dụng tiện ích `AppLogger` để ghi trực tiếp vào tệp logs `app_logs.txt` trong thư mục `applicationSupportDirectory` của thiết bị. Không sử dụng hoặc phụ thuộc vào Xcode Console (do môi trường chạy thực tế là LiveContainer trên iOS vật lý không thể đính Xcode). `AppLogger.log` tự gọi `print` bên trong — luật "không `print`" là không gọi trực tiếp ở nơi khác.
- **Performance & Memory Rules**:
  * Tránh khởi tạo lại thực thể `AVAudioEngine` nhiều lần không cần thiết.
  * NGHI-TTS playback must run strictly via `AVAudioPlayer` double-buffering queue (`NghiAudioPlayerQueue`). `AVAudioEngine` node streaming path must not be used.
  * Technical split chunks (`TTSBoundaryKind.technicalChunk`) must not append `paragraphPauseDuration` (0.5s) silence; paragraph silence applies only to `.paragraphEnd` or `.chapterEnd`.
  * Scheduled handoff transitions must call `commitParagraphState` without re-invoking `speakCurrent()` to prevent double-play bugs.
  * Tránh truy vấn (fetch) SwiftData dư thừa; ưu tiên sử dụng RAM cache (`ChapterCache`, `bookDicts`).
  * Đảm bảo hủy các `Task` chạy ngầm ngắt quãng (`Task.sleep`, prefetch tasks), gỡ bỏ `NotificationCenter` observers khi View hoặc ViewModel deinit để triệt tiêu nguy cơ rò rỉ bộ nhớ (retain cycle).

---

## 7. Checklist Tự kiểm tra trước khi Hoàn thành (AI Review Checklist)

Trước khi kết thúc lượt và thông báo hoàn thành, AI bắt buộc phải tự đánh giá mã nguồn và tài liệu theo checklist sau:
- [ ] **Compile**: Mã nguồn sửa đổi biên dịch thành công, không vi phạm Actor isolation, không lỗi threading SwiftData?
- [ ] **Architecture**: Tái sử dụng components cũ tối đa, tránh tạo logic trùng lặp, giữ vững Clean Architecture?
- [ ] **Extension**: Giữ nguyên tính tương thích ngược, không đổi API của tiện ích mở rộng nếu không được yêu cầu?
- [ ] **TTS & Audio**: Dọn dẹp `preloadedData`/`preloadedDurations` đúng cửa sổ trượt của từng engine (Google/Ext `[N, N + count]`, NghiTTS `N` + `N+1` + tối đa 2 optional reserve), tránh retain cycle?
- [ ] **Validation**: Chạy `validate_links.py --explain`, xử lý mọi doc bị stale bằng `--accept` (đã sửa) hoặc `--no-change-needed` (đã xem, vẫn đúng), rồi chạy read-only PASS 100%; cập nhật `manifest.json` và `CHANGELOG.md` thành công?
<!-- GENERATED END -->
