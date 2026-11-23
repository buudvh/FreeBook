# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.1046] - 2026-11-23

### feat: vtts — đóng giọng Google Dịch vào app (Có sẵn trong app, cạnh Ngọc Huyền)

Anh Bửu: "thêm giọng google và ipa nữa" — sau khi Javis báo rủi ro (tiếng thầy lấy qua endpoint không chính thức của Google Dịch, repo công khai ⇒ có thể bị yêu cầu gỡ) và đề nghị chỉ đóng Ngọc Huyền.

- **Model**: `Vendor/vtts/assets/vtts/vtts-googledich-m-k4.q8.vtts` (2 580 320 byte) = `M-vocos-p-bi.q8.vtts` của chuỗi `gg` cùng lượt `vtts-k4`: ~42 giờ tiếng Google Dịch (notebook `vtts-gg-data`), lọc ASR còn 16.275 câu (vi 31,1 h, trộn 1,2 h, Anh 3,1 h) ⇒ thầy VITS 20k bước warm-start từ thầy Ngọc Huyền ⇒ chưng cất như Ngọc Huyền. SHA256 `46cbe449…3761d8` ở `assets/LOCAL_SHA256SUMS`. IPA thêm ~2,4 MB (~53 MB ⇒ Telegram nhận tin kèm link tải thay cho file, 1.3.1045).
- **`VttsVoice.googleDich`** (id `google-dich`, "Nữ · Google Dịch"), `bundled = [nu10, nam1, ngocHuyen, googleDich]`; mặc định vẫn `nu-10`. Ghi nguồn "pnnbao-ump · CC BY-NC 4.0" như Ngọc Huyền (thầy kế thừa thầy Ngọc Huyền ⇒ coi là dẫn xuất CC BY-NC). Mức tăng đoạn ngắn 8 dB (6 câu mẫu, −22,3 dBFS sau chỉnh tiếng).
- **CI**: `VOICES` thêm `google-dich`, `assets/vtts/` đúng 5 file.
- **Bản quyền**: `Vendor/vtts/THIRD_PARTY_NOTICES.md` thêm mục Google Dịch (nguồn tiếng không chính thức, không liên kết với Google, câu chữ dùng để đọc); `Vendor/vtts/README.md` ghi cách gỡ nếu bị yêu cầu (xoá file + `VttsVoice.googleDich` + dòng `VOICES` / `LOCAL_SHA256SUMS`, sửa số file mong đợi).
- Ai đã tự nhập `Google Dịch.vtts` (1.3.1043) sẽ thấy hai giọng; xoá bản ở "Giọng của tôi".
- Cập nhật `.claude/rules/tts.md`, `ci-release.md`, comment `project.yml`. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1045] - 2026-11-23

### ci: Telegram — IPA quá 50 MB gửi tin kèm link tải ở GitHub Release, bỏ transfer.sh

Anh Bửu: "file realease vượt 50 MB có vấn đề gì ko" → Javis kiểm build 1327 (1.3.1044): IPA 50 417 384 byte vượt ngưỡng 50 000 000 byte của bước gửi Telegram ⇒ workflow đẩy IPA lên transfer.sh, dịch vụ không kết nối được (hết 30 s) ⇒ tin tới Telegram với dòng "Tải IPA tại đây:" **trống**. Release + nguồn LiveContainer vẫn đủ. Plan → "Duyệt, sửa đi".

- **Ngưỡng** = giới hạn thật của Bot API: 50 MiB (52 428 800 byte). Dưới ngưỡng ⇒ `sendDocument` như cũ.
- **Vượt ngưỡng hoặc `sendDocument` hết 3 lượt vẫn lỗi** ⇒ `sendMessage` cùng danh sách commit, tiêu đề ghi lý do ("IPA <cỡ MiB> MB, quá 50 MB của bot" / "gửi file IPA lỗi"), dòng `⬇️ Tải IPA: <link>` = asset của release `build-<số build>` (`RELEASE_IPA_URL`, bước Publish ghi vào `GITHUB_ENV`, cùng tên tag / asset với `publish_altstore_source.py`); không có release (nhánh khác, Publish lỗi) ⇒ link trang lượt build (IPA ở Artifacts). Bỏ hẳn transfer.sh. Trước đây `sendDocument` lỗi chỉ để lại cảnh báo, không có tin nào tới.
- **Package IPA** nén `zip -9`.
- `.claude/rules/ci-release.md`: mục "IPA lớn hơn giới hạn gửi file của bot"; luật "không gửi link release" thêm ngoại lệ này.
- Không đổi code app. Chỉ sửa workflow (không tự kích hoạt build — chạy ở lượt build kế tiếp). Chưa thấy chạy thật.

## [1.3.1044] - 2026-11-23

### feat: vtts — đóng giọng Ngọc Huyền vào app (Có sẵn trong app, ghi nguồn CC BY-NC 4.0)

Anh Bửu: "Sao ko tích hợp trực tiếp vào app, giọng hợp lệ mà" → Javis đọc lại giấy phép (dataset `pnnbao-ump/ngochuyen_voice` CC BY-NC 4.0, card không thêm điều kiện; VoxCPM2 Apache-2.0; Piper vais1000 MIT, dữ liệu VAIS-1000 CC BY 4.0) ⇒ phát hành phi thương mại có ghi nguồn là được phép → plan → "Duyệt, làm đi". Giọng Google Dịch train cùng đợt vẫn chỉ nhập file (dữ liệu lấy qua endpoint không chính thức).

- **Model**: `Vendor/vtts/assets/vtts/vtts-ngochuyen-m-k4.q8.vtts` (2 580 320 byte) = `M-vocos-p-bi.q8.vtts` của lượt chưng cất `vtts-k4` trên Kaggle (thầy VITS 60k bước warm-start Piper vais1000; chưng cất front 10k / dec 30k / joint 20k bước trên 17.670 câu). SHA256 `908684ca…6dc72` ghi ở `assets/LOCAL_SHA256SUMS`. Trainer cùng commit runtime `VTTS_COMMIT.txt` (c5c8c00) ⇒ app đọc được. IPA nặng thêm ~2,6 MB.
- **`VttsVoice`**: thêm `ngocHuyen` (id `ngoc-huyen`, "Nữ · Ngọc Huyền"), `bundled = [nu10, nam1, ngocHuyen]`; mặc định vẫn `nu-10`. Trường mới `credit` (ghi nguồn mà giấy phép bắt buộc) + `bundledRowDetail`: hàng Ngọc Huyền trong sheet chọn giọng ghi "pnnbao-ump · CC BY-NC 4.0" thay "Việt + Anh · 2,6 MB" (dòng phụ chỉ một dòng, nối thêm sẽ bị cắt mất giấy phép). Mức tăng cho đoạn quá ngắn 7,5 dB — đo trên 6 câu mẫu của lượt train (−22,0 dBFS sau bước chỉnh tiếng của `VttsLoudness`), chưa đo trên đoạn truyện dài của CI như hai giọng release.
- **CI** (`Scripts/ci/check_vtts_assets.sh`): `VOICES` thêm `ngoc-huyen` ⇒ đọc thử bằng `vtts_say` + shim ASan/UBSan như hai giọng kia; `assets/vtts/` phải đúng 4 file; SHA256 kiểm qua `LOCAL_SHA256SUMS`.
- **Bản quyền**: `Vendor/vtts/THIRD_PARTY_NOTICES.md` thêm mục Ngọc Huyền (CC BY-NC 4.0, nguồn dữ liệu + link, thay đổi đã làm, VoxCPM2, Piper vais1000; điều kiện phi thương mại — app thu phí / quảng cáo ⇒ phải bỏ giọng này). `Vendor/vtts/README.md` thêm mục "Giọng tự train".
- Ai đã tự nhập `Ngọc Huyền.vtts` (1.3.1043) sẽ thấy hai giọng; xoá bản ở "Giọng của tôi".
- Dọn: entry 1.3.1014 chuyển sang `CHANGELOG.archive.md`. Cập nhật `.claude/rules/tts.md`, `ci-release.md`, comment `project.yml`. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1043] - 2026-11-22

### feat: vtts — nhập giọng từ file .vtts (Giọng của tôi), để dùng giọng Ngọc Huyền tự train

Anh Bửu: "Tích hợp giọng ngọc huyền vào app" → plan (giọng train riêng không đóng vào IPA: dữ liệu Ngọc Huyền CC BY-NC, repo công khai, IPA gửi Telegram ⇒ làm chức năng nhập file, giọng chỉ nằm trên máy) → "Javis tự duyệt đi".

- **`VttsVoice`** enum → struct (`id`, `displayName`, `source` = `.bundled(fileName:)` / `.imported(fileName:)`, `defaultLoudnessGainDb`). Id giọng có sẵn giữ `nu-10` / `nam-1` ⇒ lựa chọn đã lưu không mất; giọng tự nhập id `file:<tên file>`, tên hiện = tên file bỏ đuôi. `resolve`: giọng có sẵn ⇒ giọng tự nhập còn file ⇒ mặc định. Đoạn quá ngắn để đo âm lượng: giọng tự nhập tăng 9 dB (giữa hai giọng có sẵn).
- **`VttsImportedVoiceRepository`** (mới, `@MainActor @Observable`, khuôn `NghiVoiceDirectory`): chủ duy nhất của `Application Support/FreeBook/TTS/Vtts/`. Nhập = kiểm cỡ (≤ 64 MB) → chép sang file tạm → **nạp thử + đọc "Xin chào."** bằng runtime vtts của app (`VttsRuntime.validateModel`, handle riêng trên hàng đợi runtime, không vào `handles`) → đặt vào thư mục (trùng tên ⇒ thay) → nhả handle cũ của id đó. File hỏng / không phải vtts / khác phiên bản runtime không bao giờ vào danh sách. Xoá: đúng giọng trình đọc vtts đang dùng ⇒ dừng phiên trước; giọng đang chọn (trình đọc chính hay giọng dự phòng) ⇒ về `nu-10`. Tên file từ id được kiểm (không `/`, `:`, không bắt đầu `.`, đuôi `.vtts`). Không vào Sao lưu.
- **`VttsRuntime`**: handle khoá theo `VttsVoice.id`; `modelURL` theo nguồn (bundle / thư mục giọng tự nhập); `isAvailable` vẫn chỉ xét 2 giọng có sẵn + VLEX (giọng tự nhập cũng dùng VLEX của app); thêm `release(voiceId:)`, `validateModel(at:)`, lỗi `voiceFileMissing` (file tự nhập mất giữa chừng).
- **Sheet chọn giọng vtts** (`VttsVoicePickerList`, chép khuôn sheet NghiTTS): hàng đầu "Nhập giọng từ file .vtts" (`DocumentPickerPresenter` — `.fileImporter` không trả kết quả trong LiveContainer; nhận mọi file, runtime quyết định), "Có sẵn trong app", "Giọng của tôi" (dòng phụ "Tự nhập · X MB", ▶ thử, 🗑 / nhấn giữ ⇒ hỏi "Xoá giọng"), lớp "Đang nhập giọng...", toast kết quả. Màn Giọng dự phòng dùng chung sheet nên có luôn.
- Hàng "Giọng đọc" (`TTSReaderVoiceSummaryRow`): giọng tự nhập ghi "Giọng tự nhập · X MB".
- **Dung lượng**: dòng mới "vtts · N giọng tự nhập" (`StorageUsageDetail.Kind.vttsVoices`, thư mục `TTS/Vtts`); snapshot đo cũ không giải được Kind mới ⇒ màn đo lại (đã chấp nhận ở comment của `StorageUsageDetail`).
- Log: `🗣️ [Vtts] Đã nhập giọng <file>: <Hz>, bộ token …, X MB`, `❌ [Vtts] Nhập giọng …`, `🗑️ [Vtts] Đã xoá giọng tự nhập …`, `🗣️ [Vtts] Đã nhả giọng <id>`.
- Runtime vtts của app (`Vendor/vtts/VTTS_COMMIT.txt` c5c8c00) trùng commit repo dùng train giọng trên Kaggle ⇒ file `.vtts` train ra đọc được. Không đổi CI / `Vendor/vtts` / IPA.
- Dọn: entry 1.3.1013 chuyển sang `CHANGELOG.archive.md`. `.claude/rules/tts.md` + `storage.md` ghi giọng tự nhập. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1042] - 2026-11-21

### feat: Màn xem phim — chạm dải Playlist xổ danh sách mục (bìa ngang), chạm hàng phát mục đó

Anh Bửu: "bấm vào phần playlist trong phát video dọc cho xổ ra danh sách video cho tôi, hiển thị kiểu danh sách nhưng cover ngang" → plan + mockup (https://claude.ai/artifact/3vLeRzLdCr1fimJhxu9pFj) → "Duyệt".

- **Dải** `VideoWatchPlaylistBar`: cả dải (trừ nút ⏭) thành nút xổ / thu, thêm mũi `chevron.down` lật lên khi đang xổ; trạng thái xổ là `@State` của dải nên giữ qua lượt đổi phim tại chỗ. ⏭ giữ nguyên việc cũ.
- **Danh sách** `VideoWatchPlaylistQueueList` (mới): mục theo **thứ tự người dùng xếp** (không theo thứ tự xáo — như `AudioPlaylistQueueList`), lấy bản mới nhất của playlist, NSFW ẩn theo công tắc chung, playlist đã xoá ⇒ bản chụp của hàng đợi. Hàng dùng lại `PlaylistItemRow(kind: .video)` (bìa 92×52 bo 8, tên `.headline` 2 dòng, tên phim `.subheadline`; màn xem ép nền tối nên chữ trắng), mục đang phát tô màu nhấn + icon loa theo **id mục**. Thẻ nền trắng 7% bo 12, vạch ngăn mảnh giữa hàng. ≤ 4 mục hiện hết; dài hơn ⇒ khung cao 310 pt (≈ 4,5 hàng) cuộn bên trong, xổ ra / đổi mục thì cuộn tới mục đang phát.
- **Chạm hàng** ⇒ `PlaylistPlaybackCoordinator.jumpVideo(to:)` (mới, `+Video`): `queue.jump(to:)` rồi `playVideoItem` (cùng phim ⇒ chuyển tập trong phiên, phim khác ⇒ màn đổi tại chỗ) — vẫn ở chế độ playlist; không đi `model.play` / `selectEpisode` (lối đó thôi playlist). Chạm đúng mục đang phát ⇒ phim lỗi thì thử lại, đang mở / đang phát thì để yên. Danh sách giữ mở sau khi chạm. Log `🎶 [VideoWatch]` (xổ / thu, chọn mục), `⏭️ [PlaylistPlayback] Chọn mục i/n`.
- Đang xáo: số trên dải ("3/8") theo thứ tự phát, số của hàng theo thứ tự xếp — giống màn nghe nhạc.
- Dọn: entry 1.3.1012 chuyển sang `CHANGELOG.archive.md`. `.claude/rules/comic-video.md` ghi danh sách xổ. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1041] - 2026-11-20

### feat: vtts — từ điển phiên âm riêng như VieNeu / NghiTTS, sheet phiên âm khi bôi đen lưu được vào vtts

Anh Bửu: "thêm từ điển phiên âm giống vieneu và pipetts giúp tôi, sheet phiên âm bôi đen có thêm option lưu từ điển vtts" → plan + mockup (https://claude.ai/artifact/8eQ4RX84WY35hc1GABjCxv) → "Duyệt".

- **Kho** `VttsPhoneticDictionary` (actor, mới): `FreeBook/TTS/phien-am-vtts.plist`, khoá hạ chữ thường + NFC, **giữ dấu** (vtts tra mọi token kể cả chữ Việt — gấp dấu như hai từ điển kia thì mục "ban" thay luôn "bàn"). Công tắc `vttsDictionaryEnabled`, mặc định **bật** (từ điển chỉ có mục người dùng tự thêm).
- **Áp khi đọc** — `VttsTextFrontend` (mới): token **từ** của `TTSReplacementTokenizer` (từ nối `Kamar-Taj` là một token) khớp từ điển ⇒ cách đọc đi nguyên văn; phần chữ còn lại mới qua phiên âm tiếng Nhật ⇒ mục người dùng thắng, không phiên âm hai lần. `VttsTTSService` dùng nó cho trình đọc chính, giọng dự phòng, ▶ thử giọng; log `🗣️ [Vtts] Đoạn` thêm `dict=N` / `dict=off`. Công tắc nằm trong `TTSSettingsSnapshot` (`vttsDictionaryEnabled`) + fingerprint giọng dự phòng.
- **Cài đặt**: `VttsReaderManagementRows` (mới) — "Từ điển phiên âm vtts ›" + công tắc "Áp dụng từ điển phiên âm vtts" trên hàng "Phiên âm tiếng Nhật" ở Cài đặt TTS (nhánh vtts đặt **trước** nhánh tiện ích của `TTSSettingsView` — `isExtensionTool` cũng đúng với vtts nên trước đây vtts rơi vào nhánh tiện ích trống) và màn Giọng dự phòng; nút "?" giải thích. Màn `VttsPhoneticDictionaryView` (mới, khuôn màn VieNeu): tìm, nạp 100 từ / lượt, chạm hàng ⇒ `EditWordSheet`, xoá bằng icon / vuốt, "+" nổi ⇒ `AddWordSheet(target: .vtts)`, ngăn kéo "…": Nhập từ file… (`PhoneticDictionaryImporter.importVtts`, 3 chế độ), Xuất .plist / .json, Xoá tất cả. Không có Tải từ điển / Phiên âm lại.
- **Sheet bôi đen › Phiên âm** (`AddWordSheet`): Menu Lưu 4 mục — NghiTTS / VieNeu-TTS / **vtts** / Lưu tất cả (cả ba). `PhoneticDictionaryWriter.Destination` thành `nghiTTS / vieNeu / vtts / all` với cờ viết dương (bản cũ `self != .vieNeu` — thêm đích là cờ cũ đúng cho cả đích mới), `Result` thêm `wroteVtts`, toast liệt kê đúng từ điển đã ghi. Chip gợi ý `VTT` (`TTSPhoneticSuggestion.Origin.vttsLibrary`) ở sheet thêm từ và sheet sửa từ của mọi từ điển, nhấn giữ để xoá khỏi từ điển vtts (tra / xoá bằng khoá của chính vtts).
- **Sao lưu / Dung lượng**: file vào `BackupPaths.ttsDictionaryFiles` (nhóm `.dictCustom`), khôi phục xong nạp lại `VttsPhoneticDictionary`; nhãn Dung lượng "Từ điển phiên âm (NghiTTS, VieNeu, vtts)".
- Dọn: entry 1.3.1011 chuyển sang `CHANGELOG.archive.md`. `.claude/rules/tts.md` ghi từ điển vtts. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1040] - 2026-11-20

### feat: Reader — dấu trang chương và ghi chú đoạn (nút trên header, ô ở menu bôi đen, tab Dấu trang / Ghi chú trong mục lục, dấu đoạn có ghi chú)

Anh Bửu: "làm chức năng ghi chú, đánh dấu chương" → mockup → "thêm tab ở ghi chú dấu trang ở mục lục nữa, ngoài ra thêm đánh dấu để biết đoạn nào trong reader được ghi chú; bấm vào ghi chú để đến đoạn ghi chú, bấm vào đánh dấu để đến chương đánh dấu" → bỏ hai hàng ở ngăn kéo ⋯ → "thêm 1 nút dấu trang trên header" → "Duyệt".

- **Dữ liệu** (`Models/Reader/BookAnnotations`, `Services/Books/Annotations/`): mỗi truyện một file `annotations/<sha256(bookId)>.json` (`BookAnnotationStore`, ghi `.atomic`, rỗng ⇒ xoá file, file hỏng ⇒ cất `.broken-…`). Dấu trang theo **chương** (chỉ số + tên lúc tạo + link chương), ghi chú theo **đoạn** (`paragraphIndex` = id dòng thưa như `ParagraphItem.id`, "Đoạn N" để hiện, đoạn chữ đang bôi đen ≤ 300 ký tự). `BookAnnotationRepository` (`@MainActor @Observable`, cache RAM bỏ quan sát + `revision`) là lối của View. Chỉ truyện có bản ghi `Book` mới dùng được (không có ⇒ toast "Thêm truyện vào kệ…").
- **Reader**: nút dấu trang đầu cụm nút phải header (36×38, đặc + màu nhấn khi chương đang hiện có dấu, toast khi bật / tắt); menu bôi đen thêm cột 5 — "Ghi chú" (mở sheet viết với đoạn trích) và "Dấu trang" / "Bỏ dấu" (chương của vùng bôi đen) — bề rộng 275 → 327pt; đoạn có ghi chú có vạch màu nhấn ở lề trái + icon ghi chú ở lề phải (`ReaderNoteMarkerModifier`, gắn ngoài `ParagraphCardView.equatable()`), chạm ⇒ mở ghi chú (nhiều ghi chú ⇒ mở tab Ghi chú). Sheet `ReaderNoteEditorSheet` (kính, "Lưu" chữ ở header, "Xoá ghi chú" khi sửa, vuốt xuống lúc gõ dở ⇒ hỏi bỏ).
- **Mục lục**: chip Mục lục / Dấu trang N / Ghi chú N ở đầu panel (`ReaderChapterListView+Annotations`, kiểu chip `ExtensionKindFilterBar`, màu theo nền đọc). Tab Dấu trang: hàng chương + ngày, chạm ⇒ **đầu chương**. Tab Ghi chú: nhóm theo chương, đoạn trích + nội dung + "Đoạn N · ngày", chạm ⇒ **đúng đoạn**, nhấn giữ ⇒ Sửa / Xoá. 🗑 xoá ở mọi hàng. Hàng chương ở tab Mục lục có icon dấu trang + số ghi chú. Mở chỗ đã lưu: chỉ số không còn trỏ đúng link đã lưu ⇒ tra theo link (mục lục online, rồi `ChapterStore.fetchOrderedTOC`).
- **Đi theo truyện**: xoá truyện (`BookStorageManager.deleteBookSideData` thay cho `deleteLegadoState` ở ba lối xoá — gọi cả hai), đổi nguồn (`BookSourceMigrator` chép gộp theo id / xoá), sao lưu (`BackupAnnotationArchiver`, entry `library/annotations.json` = `[hash(bookId): …]`, đi kèm nhóm `.books`, khôi phục gộp), Dung lượng (loại mới "Ghi chú & dấu trang"), Dọn rác (file của truyện không còn trong thư viện, cùng luật `.bin` / phim / comic).
- Log `🔖 [Annotations]`. `storage.md`: thêm thư mục `annotations/`.
- Kiểm: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Chưa làm (đã nói trong plan): tô màu chữ đoạn có ghi chú, xuất ghi chú, truyện tranh / phim, xem từ Chi tiết truyện; vân tay sao lưu tự động (`BackupLibraryFingerprint`) chưa tính ghi chú ⇒ chỉ sửa ghi chú thì lượt sao lưu Drive tự động có thể bỏ qua.

## [1.3.1039] - 2026-11-20

### feat: Kệ — nút ⋮ mở tuỳ chọn truyện, nhấn giữ để chọn nhiều (Chọn tất cả, Thêm vào playlist, Thêm vào bộ sưu tập, Xoá)

Anh Bửu: thêm nút ba chấm dọc trên mỗi sách ở Kệ mở menu của sách; nhấn giữ lâu = chọn nhiều sách, có Chọn tất cả / Bỏ chọn tất cả, Xoá, Thêm vào playlist, Thêm vào bộ sưu tập → plan + mockup https://claude.ai/artifact/Es6YfEe94Zyi2uigCzMTPX → "Duyệt" (theo đề xuất: chỉ Kệ Sách + Lịch Sử, thanh thao tác đè thanh tab, Xoá ở Kệ hỏi hai hướng).

- **⋮** (`ShelfBookMoreButton`, mới): kiểu Danh sách cuối hàng sau badge chương mới (17pt, khung 32×44), kiểu Lưới cuối dòng "icon · Ch. N" (15pt), kiểu Chỉ bìa vòng tròn 26 nền đen 50% góc trên phải bìa (badge chương mới lùi sang trái). Bấm ⇒ `BookActionSheet` như nhấn giữ trước đây. Là tham số **opt-in** `onMore` của `ShelfBooksLayoutView`; thẻ lưới nhận `ShelfBookGridCardView.Accessory`.
- **Chọn nhiều** (`ShelfBookSelection` + `ShelfView+Selection`, mới): nhấn giữ (0,25 s, rung) ⇒ vào chế độ, truyện đó chọn sẵn. Header ✕ + "Đã chọn N" (`pageTitle(_:leadingIcon:)`) + "Chọn tất cả" / "Bỏ chọn tất cả" thay cụm 🔍 | …; nút "+" nổi ẩn. Chạm / nhấn giữ = chọn / bỏ, không mở truyện. Vòng chọn `ShelfBookSelectionMark` (mới); hàng đã chọn nền nhấn 18% + viền 60% (`bookListPanel(_:isHighlighted:)`), bìa đã chọn viền nhấn 3pt. Chỉ giữ `bookId`, mọi phép đếm / thao tác giao với danh sách đang hiện của trang (chip loại + NSFW, kể cả phần chưa phân trang tới — "Chọn tất cả" chọn hết). Thoát: ✕, đổi trang, mở Reader (thông báo / đĩa nghe), thao tác xong.
- **Thanh thao tác** `ShelfSelectionActionBar` (mới): cùng khuôn `MainTabBar`, `overlay` đè đúng chỗ thanh tab (không sửa thanh tab dùng chung). Thêm vào playlist · Thêm vào bộ sưu tập · Xoá.
- **Xoá**: Kệ Sách hỏi "Bỏ khỏi kệ (về Lịch sử)" (một lần lưu, `BookTransactionCoordinator+Batch.removeFromShelf(bookIds:)` chép luật bản một truyện) hoặc "Xoá hẳn khỏi máy" (`BookStorageManager.deleteBooksAsync`, lớp chờ "Đang dọn dẹp sách...", toast theo số thật đã xoá — truyện đang nghe TTS được giữ). Lịch Sử hỏi "Xoá N truyện khỏi lịch sử": trên kệ ⇒ `setHistory(bookIds:isHistory: false)`, không ở kệ ⇒ xoá khỏi máy.
- **Thêm vào bộ sưu tập**: sheet kính `CollectionBatchAddSheet` (mới) — chạm một bộ ⇒ `BookCollectionCoordinator.addBooks` (mới, **chỉ thêm**, một lần lưu; truyện ở Lịch sử lên kệ theo bất biến), "Tạo bộ sưu tập mới" tạo xong thêm luôn, toast "Đã thêm N truyện vào …".
- **Thêm vào playlist**: chỉ album âm thanh / phim (`PlaylistKind` qua `BookContentKindResolver`). Không có cuốn nào hợp ⇒ ô mờ + toast; có cả hai loại ⇒ hỏi Nhạc / Video; lấy mục lục **lần lượt** (`PlaylistAlbumItemsLoader.items`, ô hiện "Đang lấy i/N · Huỷ", bấm lại ⇒ huỷ) rồi mở `PlaylistAddSheet` (thêm tham số tuỳ chọn `onAdded`); truyện khác loại / album lỗi mục lục báo gộp một toast.
- Thêm xong (playlist / bộ sưu tập) ⇒ thoát chế độ chọn khi sheet đóng hẳn; vuốt đóng mà chưa thêm ⇒ giữ lựa chọn.
- Bộ sưu tập và Tìm trên kệ giữ nguyên (nhấn giữ vẫn mở sheet, không ⋮). Cụm nút phải header Kệ tách ra `headerTrailingButtons` (ngân sách type-check của `body`).
- `.claude/rules/ui-conventions.md` thêm luật. CHANGELOG: chuyển bản 1.3.1009 sang archive. Kiểm: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **chưa build tại chỗ (Windows), chưa thử máy**.

## [1.3.1038] - 2026-11-20

### fix: vtts — phiên âm tiếng Nhật đọc được tên viết hoa, thêm "vtts tự đọc nhanh tối đa" để chỉnh độ rõ lời

Anh Bửu thử 1.3.1036: hết tiếng "vụt" nhưng "âm điệu nghe khác ver trước", "nghe không được rõ lời lắm" (hai file tự đọc nhanh thường / bản 4 "nghe như nhau" ⇒ do tự đọc nhanh, không do bản 4); "tôi bật phiên âm tiếng nhật nhưng không thấy hoạt động". Log máy: `speed=1.80`, `NghiHandoff delayMs` 12–39 ms (đổi file không gây hở tiếng). Anh duyệt plan + mockup.

- **Phiên âm tiếng Nhật**: `TTSJapaneseTextTransliterator` (dùng chung Siri / Google / tiện ích / vtts) chỉ đổi từ `ForeignScriptClassifier` chấm ≥ 4 điểm hoặc có trong `JapaneseLoanwordList` ⇒ "Konoha", "Naruto", "Sasuke" (1 điểm) không bao giờ đổi, vtts đọc tiếng Anh. `spokenForm` nhận thêm luật tên viết hoa của VieNeu (`VieNeuJapaneseNameReader.reads`). Không hạ ngưỡng bộ chấm điểm. vtts đọc kết quả ("Kô nô ha", "Na ru tô") bằng tiếng Việt — đã đối chiếu `word_tag` / `parse_syl` của runtime. Log `🗣️ [Vtts] Đoạn` thêm `jp=off` / `jp=on(N: Konoha→Kô nô ha, …)` (tối đa 2 cặp, `applyReportingChanges`).
- **"vtts tự đọc nhanh tối đa"** (mockup https://claude.ai/artifact/XPxHGwcaoi3ZF9GsC2apAM): `VttsNativeSpeedRow` (mới, `Views/Settings/TTS/`) ngay dưới thanh Tốc độ ở Cài đặt TTS và màn Giọng dự phòng khi chọn vtts, 1,0–2,0 bước 0,1, khoá `vttsNativeSpeedMax` (`@AppStorage`), mặc định 1,4 (ước lượng), dòng số "vtts đọc X · trình phát kéo thêm Y", giải thích sau nút "?" của "Cấu hình giọng nói", "Đặt lại" về mặc định. Thanh Tốc độ giữ nghĩa tốc độ nghe: `TTSManager.vttsNativeSpeed(forListeningSpeed:)` = min(tốc độ, tối đa) kẹp 1,0–2,0; `localPlaybackRate` / `remotePlaybackRate` kéo phần còn lại. Giá trị nằm trong `TTSSettingsSnapshot` (`vttsNativeSpeedMax`) và fingerprint giọng dự phòng ⇒ đóng Cài đặt là dựng lại đoạn như đổi tốc độ.
- Dọn: entry 1.3.1008 chuyển sang `CHANGELOG.archive.md`. `.claude/rules/tts.md` ghi luật tên viết hoa + hàng mới. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1037] - 2026-11-20

### fix: Danh sách VietPhrase.dat / Names.dat (thẻ › Sửa) mở và tìm chậm — chỉ mục dựng một lần, trang đầu hiện ngay, tìm trên byte, kết quả hiện dần

Anh Bửu: "vietpharse tìm quá lâu, hiển thị ra cũng lâu, vì sao vậy?" → "tôi đang nói trong danh sách khi nhấn sửa ấy nhé" → plan → "Duyệt".

- **Nguyên nhân**: mở màn duyệt **hết** cây và dựng `String` cho từng khoá (cỡ triệu) rồi mới hiện; mỗi lượt tìm dựng lại bảng con của cây (vài mảng cỡ triệu phần tử) và dựng `String` + `range(of:options: .caseInsensitive)` cho **từng nghĩa** — từ hiếm phải quét hết cây, kết quả chỉ hiện khi quét xong.
- **Chỉ mục** `BaseDictionaryIndex` (`Models/Dictionaries/`, mới): dựng một lần mỗi lần mở màn ở nền — khoá dạng đơn vị UTF-16 nối liền một mảng + vị trí nghĩa trong pool `.dat`, thứ tự tiền thứ tự của cây như cũ. Phép duyệt **chép riêng** cùng phép tính của `walkEntries` (hàm đó giữ nguyên vì nuôi `allEntries` của nhập / gộp); không kiểm UTF-8 nghĩa lúc dựng (nghĩa hỏng hiện rỗng). 200 khoá đầu gửi về màn ngay khi có (`onFirstPage`), phần sau dựng chuỗi theo lượt 200 khi cuộn; tổng số từ lấy số mục chỉ mục (lúc đang dựng: `wordCount` ở đầu file). Lượt dựng không theo huỷ của `.task` (quay về từ "Từ đã sửa / đã xoá" không dựng lại).
- **Tìm** `BaseDictionaryIndexSearch` (mới): lớp sửa đổi (như cũ) ⇒ khoá **bắt đầu bằng** ⇒ khoá **chứa** (quét tuyến tính mảng UTF-16, không dựng chuỗi) ⇒ **nghĩa** chứa, so trên byte bằng `BaseDictionaryMeaningMatcher` (parser UTF-8 của stdlib, hạ thường theo `lowercaseMapping` dưới U+2000, không bỏ dấu, chuỗi tìm NFC; nghĩa có dấu rời / NFD đi đường Foundation cũ), quét theo lượt chia 2–3 luồng (1 luồng khi NghiTTS / VieNeu đang đọc). Kết quả gửi dần qua `AsyncStream` (`BaseDictionaryBrowser.searchUpdates`), dòng tổng ghi "Đang tìm… N kết quả" khi chưa xong; gõ tiếp ⇒ huỷ lượt quét; chỉ mục chưa xong thì lượt tìm chờ rồi tự chạy. Mỗi khoá một lần trong kết quả.
- Bỏ `FrozenTrieDictionary.allKeys()` và `BaseDictionaryBrowser.keys` / `search` cũ (không còn ai gọi). `walkEntries` / `allEntries` không đổi.
- Log `📚 [VPList]` (số mục, ms dựng, ms tới trang đầu) và `🔎 [VPList]` (ms phần khoá / nghĩa, số luồng, số nghĩa phải so bằng Foundation, đối chiếu 1000 nghĩa đầu giữa đường byte và Foundation — số lệch phải là 0) để đo trên máy.
- `translation.md`: sửa câu mô tả danh sách từ điển gốc. CHANGELOG: chuyển bản 1.3.1007 sang archive.
- Kiểm: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy, chưa đo được nhanh lên bao nhiêu**. Cần thử: bật Ghi log, Cài đặt dịch thuật › thẻ VietPhrase.txt › Sửa — trang đầu phải hiện gần như ngay; tìm một chữ Hán, một chữ Việt hiếm, một chữ Việt thông dụng (vd "của"); gửi log.

## [1.3.1036] - 2026-11-20

### fix: vtts — tự đọc nhanh theo thanh Tốc độ, làm nhỏ dần đuôi cụt, tiếng sáng và to hơn

Anh Bửu nghe 4 bản vtts tạo tiếng nhanh 1,8× ngay từ gốc (CI 1.3.1035, câu "…phiên bản, đem mệnh danh…"): "4 cái đều không có tiếng vụt" ⇒ tiếng "vụt" ở 1,8× là do `AVAudioPlayer` kéo nhanh tiếng vtts. Duyệt plan bước 2 kèm "bản 4" (anh đã chọn trong lượt nghe so âm lượng).

- **Tự đọc nhanh**: `TTSManager.localSynthesisSpeed(forTool: "vtts")` = `vttsSynthesisSpeed` (khoá `vttsRate` kẹp `VttsTTSService.nativeSpeedRange` 1,0–2,0, chung trình đọc chính và giọng dự phòng) ⇒ `VttsTTSService` đưa `length_scale = 1 / tốc độ` vào vtts, khoảng lặng đuôi chia cho tốc độ, khoá tổng hợp mặc định có tốc độ. Trình phát chỉ kéo phần còn lại: `TTSManager.localPlaybackRate` (sửa tại chỗ 2 dòng `NghiAudioPlayerQueue.start` / `updateRate` của `TTSManager.swift`, không thêm dòng) và `remotePlaybackRate` khi vtts là giọng dự phòng. NghiTTS / VieNeu không đổi. Tốc độ chỉ đổi ở sheet Cài đặt TTS, nằm trong `TTSSettingsSnapshot` ⇒ đóng sheet là xoá hết đệm (cả đầu chương kế).
- **Đuôi cụt** — `VttsEdgeFade` (mới): WAV CI cho thấy mảnh vtts kết thúc ở dấu phẩy (vtts tự cắt câu > 40 âm tiết) bị cắt lúc âm còn −36 dBFS rồi rơi thẳng về 0 (cả hai giọng ở 1×). Làm nhỏ dần 20 ms trước mỗi khe số 0 tuyệt đối ≥ 100 ms (khe 150 ms bridge chèn) và ở cuối tiếng, to dần 5 ms sau khe; log `cut=`.
- **Bản 4** — `VttsLoudness.process` (viết lại): lọc thông cao 150 Hz + nâng +6 dB quanh 2,8 kHz (biquad RBJ) → RMS khung 20 ms có tiếng về −14 dBFS (≈ −16 LUFS; trước −16 dBFS), tăng tối đa +18 dB → ghìm đỉnh ≤ −1 dBFS (cực tiểu ±5 ms, trung bình trượt ±5 ms, nhả 80 ms) thay cho cách hạ cả đoạn của 1.3.1033 (cách cũ chặn mức to ~−17,5 LUFS). `VttsVoice.defaultLoudnessGainDb` theo mốc mới (nu-10 +10,5, nam-1 +7 dB). Log `🗣️ [Vtts] Đoạn` thêm `speed=`, `limit=`. Thuật toán trùng bản Python đã dựng 4 file anh nghe (nu-10 tốc độ gốc: +11,6 dB, ghìm −3,8 dB).
- CI: gỡ `render_listening_samples` (tạm của 1.3.1035) — `check_vtts_assets.sh` / `build-ipa.yml` về như trước 1.3.1034.
- Dọn: entry 1.3.1006 chuyển sang `CHANGELOG.archive.md`. `.claude/rules/tts.md` ghi tự đọc nhanh, `VttsEdgeFade`, bản 4. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1035] - 2026-11-20

### fix: vtts — độ dài phân đoạn mặc định 500, log độ trễ chuyển đoạn, CI dựng câu nghe thử ở tốc độ gốc

Anh Bửu: "chỗ ngắt đoạn cũ đoạn mới hay có tiếng xoẹt xoẹt hoặc vấp". Anh thử câu "…Thổ Nạp Thuật phiên bản, đem mệnh danh là “Cá Trê Thổ Nạp Thuật”." (lỗi ở dấu phẩy): 1× + phân đoạn 500 sạch, 1× + 150 bị, 1,8× + 150 bị, 1,8× + 500 còn "vụt" nhẹ. vtts không có nhiễu ngẫu nhiên (cùng chữ ⇒ cùng mẫu) và tự cắt câu > 40 âm tiết **đúng dấu phẩy đó** (`MAX_SYL` của `vtts_text.c`; log máy `chars=187 chunks=2`) ⇒ ở 150 tiếng hai nửa câu y hệt, khác duy nhất là app xẻ thành 2 file ⇒ một lần đổi `AVAudioPlayer` giữa câu. Phần "vụt" ở 1,8× + 500 nằm trong một file ⇒ do trình phát kéo nhanh (chưa rõ cơ chế).

- `TTSManager.VttsSettings.defaultChunkLength` 150 → **500**: `NghiUtteranceSegmenter` luôn cắt ở dấu hết câu đầu tiên nên chunk vẫn là từng câu, chỉ câu > 150 ký tự thôi bị xẻ. Máy đã lưu `vttsChunk` giữ giá trị cũ (máy anh đã để 500).
- `NghiAudioPlayerQueue.lastHandoffDelayMs` (mới): ms từ delegate phát xong tới khi `play()` của player kế đã gọi; log `🔊 [TTSPerf] NghiHandoff` thêm `delayMs=` (sửa tại chỗ dòng log trong `TTSManager.swift`, không thêm dòng). Dùng chung NghiTTS / VieNeu / vtts — đo xem chỗ vấp có phải main kẹt lúc bàn giao (log anh có main kẹt 554 / 1045 ms).
- CI (tạm): bỏ phần đo Google (`Scripts/ci/tts_loudness_probe.py` xoá, `build-ipa.yml` thôi đưa `GOOGLE_CLOUD_TTS_API_KEY` vào bước vtts); `check_vtts_assets.sh` › `render_listening_samples` dựng câu của anh bằng 2 giọng: cả câu 1×, cả câu tốc độ gốc 1,8× (`vtts_say --speed 0.5556` — tham số này là `length_scale`), và 2 mảnh như khi cắt ở 150 ⇒ artifact `vtts-samples` để anh nghe so với app. Kết quả đo 1.3.1034: Google readaloud 6 giọng −19,8 LUFS, vtts 1.3.1033 đã ngang / to hơn (nu-10 −19,4, nam-1 −17,8) ⇒ vtts nghe nhỏ là do chất tiếng; bản "sáng và to hơn" anh chọn còn giữ tới khi nghe xong bản tốc độ gốc.
- Dọn: entry 1.3.1005 chuyển sang `CHANGELOG.archive.md`. `.claude/rules/tts.md` ghi lý do mặc định 500 + `delayMs`. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`.

## [1.3.1034] - 2026-11-20

### chore: vtts — CI đo tạm mức to Google TTS so với vtts để chọn mốc âm lượng

Anh Bửu: sau 1.3.1033 vtts vẫn "không to bằng google tts". Đo lại 2 WAV mẫu của CI: bản 1.3.1033 chỉ đưa vtts lên ~−17,7 LUFS (nu-10 −26,4 → −17,8; nam-1 −22,4 → −17,6 và đỉnh đã chạm trần −1 dBFS) — giữ đỉnh ≤ −1 dBFS bằng cách hạ **cả đoạn** nên mức to bị chặn, đoạn truyện dài đỉnh cao hơn còn được tăng ít hơn. Mốc −16 dBFS là ước lượng, chưa từng đo Google. Lượt này chỉ đo, chưa đổi app:

- `Scripts/ci/tts_loudness_probe.py` (mới, **tạm thời**, chỉ thư viện chuẩn): gọi Google readaloud đúng body của `GoogleTTSService.makeRequest` với cả 6 giọng (câu thử + một đoạn truyện ~30 s có thoại, câu cảm thán), giải mã bằng `afconvert` (lùi `ffmpeg`), đo LUFS tích hợp BS.1770, RMS lúc có tiếng (đúng cách `VttsLoudness` đo), đỉnh; vtts đọc cùng đoạn dài bằng 2 giọng, đo mức gốc + mô phỏng `VttsLoudness` 1.3.1033. In ra log CI + `loudness.txt` trong artifact `vtts-samples` (kèm WAV đoạn dài của vtts; audio Google không lưu). Không in key, lỗi gì cũng không làm đỏ build.
- `check_vtts_assets.sh`: hàm `probe_loudness` (tạm) chạy sau kiểm shim. `build-ipa.yml`: bước vtts nhận `GOOGLE_CLOUD_TTS_API_KEY` từ secret (tạm).
- Gỡ cả hai ở lượt sửa `VttsLoudness` tiếp theo. Dọn: 3 entry cũ nhất (1.3.1002–1.3.1004) chuyển sang `CHANGELOG.archive.md`.

## [1.3.1033] - 2026-11-20

### fix: vtts — giọng nhỏ, tự kéo âm lượng mỗi đoạn về mức TTS thường

Anh Bửu: "giọng nhỏ quá". Đo WAV đọc thử của CI (run 44685147889): model xuất nhỏ — `nu-10` đỉnh −11,3 dBFS, RMS lúc có tiếng −24,1 dBFS; `nam-1` −5,9 / −19,8 dBFS (TTS thường ~−16…−18 dBFS).

- `VttsLoudness` (mới, `Services/TTS/Vtts/`): đo RMS trên khung 20 ms có tiếng (> −45 dBFS) của **mỗi đoạn**, tăng về −16 dBFS; chỉ tăng 0…+12 dB, giới hạn để đỉnh ≤ −1 dBFS (không để `WAVEncoder` kẹp cứng gây rè); đoạn có tiếng < 0,4 s dùng mức cố định theo giọng (`VttsVoice.defaultLoudnessGainDb`: nu-10 +8, nam-1 +3,5 dB). Dùng Accelerate (`vDSP`).
- `VttsTTSService` gọi trước khi nối khoảng lặng đuôi ⇒ áp cho trình đọc chính, giọng dự phòng và ▶ thử giọng (cùng đi qua service). Log `🗣️ [Vtts] Đoạn` thêm `gain=+X.XdB`.
- Mô phỏng thuật toán trên 2 WAV mẫu: nu-10 +8,6 dB (đỉnh −2,7 dBFS), nam-1 +4,8 dB (đỉnh −1,1 dBFS), cả hai RMS −16 dBFS. Mốc −16 dBFS là ước lượng, chưa so với VieNeu / Google. Không thêm giao diện.
- Chưa thử máy; `.claude/rules/tts.md` ghi thêm.

## [1.3.1032] - 2026-11-20

### fix: vtts — CI dựng vtts_say kèm stub ZH/JA/RU, kiểm tài sản trong IPA, toast lỗi ghi đúng trình đọc

Sửa sau review phản biện (2 agent, chỉ đọc) trước lượt push đầu của vtts:

- **CI sẽ đỏ chắc chắn**: `check_vtts_assets.sh` dựng `vtts_say` với đúng cờ tắt ngôn ngữ của gói SPM, nhưng `vtts_say.c` (upstream) luôn gọi `vtts_zlex_init` / `vtts_jlex_init` / `vtts_rlex_init` — chỉ được định nghĩa trong `#if VTTS_ENABLE_ZH / _JA / _RU` ⇒ `Undefined symbols` lúc link. Thêm `Scripts/ci/vtts_say_lex_stubs.c` (3 hàm trả `-1`, chỉ link vào `vtts_say`), giữ nguyên cờ của app; `build-ipa.yml` thêm file này vào `paths`.
- **Bước Package IPA kiểm `FreeBook.app/vtts/`** có đủ `lex_en.bin` + 2 giọng M (folder reference nằm trong thư mục gói SPM cục bộ — chưa từng build; thiếu thì vtts lỗi ngay đoạn đầu).
- Toast / log lỗi tổng hợp của đường phát local chung ghi tên trình đọc đang dùng (`TTSManager.localReaderLabel`: NghiTTS / VieNeu / vtts) thay cho luôn "NghiTTS" — sửa tại chỗ 2 dòng `TTSManager.swift`, không thêm dòng.
- Dọn: 7 entry cũ nhất (1.3.995–1.3.1001) chuyển sang `CHANGELOG.archive.md` (file chính giữ 30 entry); `AGENTS.md` + `ci-release.md` ghi điều kiện chạy CI mới.
- Review không thấy lỗi biên dịch Swift / C nào khác (đối chiếu code, máy Windows không biên dịch được). Để sau (ghi nhận, chưa sửa): lỗi front-end hiếm của một đoạn vtts làm dừng cả phiên đọc; runtime có thể nạp lại ngay sau khi vừa nhả (chỉ tốn ~4,7 MB, không lỗi).

## [1.3.1031] - 2026-11-20

### feat: vtts — lưu sẵn model, từ điển và công cụ dựng lại trong repo, CI không tải gì từ upstream

Anh Bửu (qua session chính): lưu sẵn toàn bộ dữ liệu vtts trong repo, phòng repo upstream / CMUdict bị xoá — CI và app không phụ thuộc mạng tới `tuanpmt/vtts` hay `cmusphinx`. Thay phần tài sản của 1.3.1028–1029.

- **`Vendor/vtts/assets/`** (commit, `-text` trong `.gitattributes` ⇒ giữ nguyên byte): `vtts/` = **đúng** 3 file đóng vào app (2 giọng M release `v0.4.0` + `lex_en.bin`), `extra/` = 2 bản S dự trữ (không vào app), `cmudict/cmudict.dict` (commit `74790861…`, SHA256 trùng mức `cmudict.py` ghim), `SHA256SUMS` nguyên văn của release (4 model đã kiểm khớp trước khi commit) + `LOCAL_SHA256SUMS` (`lex_en.bin`, `cmudict.dict`). `lex_en.bin` dựng trên máy này bằng `build_lexicon.py` ở commit ghim `c5c8c00` (1 860 736 byte).
- **`Vendor/vtts/tools/`**: công cụ upstream cùng commit, chép nguyên văn (đã so hash git từng file): `scripts/frontend/build_lexicon.py` + 8 module `src/vtts/...` nó import (chỉ thư viện chuẩn), `runtime/tools/vtts_say.c`, `runtime/Makefile`. Nằm ngoài target SPM ⇒ không vào app. **`Vendor/vtts/rebuild_lex_en.sh`** (mới): dựng lại `lex_en.bin` từ `tools/` + `cmudict.dict` trong thư mục tạm, chặn mạng bằng proxy chết, so SHA256 (hoặc `--write` để ghi đè) — đã thử import + đọc CMUdict offline (126 052 từ); lượt dựng đầy đủ trên máy này hết RAM (`MemoryError` ở bước huấn luyện letter-to-sound, máy 8 GB chỉ còn ~0,8 GB trống) nên **chưa đối chiếu lại từng byte**. `Vendor/vtts/README.md` (mới): bố cục + cách dựng lại / nâng runtime / nâng model.
- **`Scripts/ci/check_vtts_assets.sh`** thay `fetch_vtts_assets.sh` (xoá): không mạng, không cache — kiểm SHA256 mọi tài sản + `assets/vtts/` đúng 3 file, dựng `vtts_say` từ mã đã vendor đọc thử câu Việt + Anh bằng từng giọng M (kiểm `token_set vi-en`, `mode auto lex 1`, id < vocab, WAV ≥ 1 s, không im lặng), kiểm thử shim với ASan/UBSan như trước. `build-ipa.yml`: một bước "Check vtts assets + smoke test" thay 4 bước cache / tải / lưu / smoke; `paths` đổi sang `check_vtts_assets.sh`. `project.yml`: folder resource `Vendor/vtts/assets/vtts` (bundle vẫn là `vtts/`, Swift không đổi đường tra). `.gitignore` bỏ `/Vendor/vtts-assets/`.
- Bản quyền: `THIRD_PARTY_NOTICES.md` ghi thêm `tools/`, bản S, CMUdict nguồn trong repo (BSD-2 điều khoản 1) bên cạnh VLEX trong IPA (điều khoản 2). Chú thích `Package.swift`, `VttsVoice`, `VttsRuntime`, `vtts_bridge_smoke.c`, `ci-release.md` cập nhật theo.
- Dung lượng thêm vào git: ~13,1 MB tài sản (4 model 7,57 MB + `lex_en.bin` 1,86 MB + `cmudict.dict` 3,62 MB) + ~85 KB công cụ.
- Kiểm: `bash -n`, thử phần kiểm SHA256 của script mới trên Windows (bắt được file thừa trong `assets/vtts/`), YAML hợp lệ, `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`). **Không biên dịch / chạy `vtts_say` được tại chỗ (Windows)** — chỉ CI.

## [1.3.1030] - 2026-11-20

### chore: Màn tự thử nhịp dọc header (tạm thời), đầu dò header sửa cho iOS 26, mũi back tự dựng trùng chỗ mũi back hệ thống

Anh Bửu chọn mốc B ("đáy thanh +16": nội dung đầu tiên cách đáy thanh tiêu đề / đáy ô tìm 16pt) sau log đo 1.3.1025 (iPhone 11: Form không tiêu đề nhóm 35pt, dưới ô tìm 50pt, List trơn 0pt, panel 4pt; mũi back hệ thống x=12 trong khi nội dung x=20) → duyệt bản đo.

- **Màn "Thử nhịp dọc header"** (tạm thời, Cài đặt › Ghi log hệ thống › Chẩn Đoán; `Views/Settings/Logs/HeaderSpacingLab/`): một nút **Chạy** tự đẩy lần lượt 22 trang mẫu — Form không / có tiêu đề nhóm, Form dưới ô tìm, List trơn (có / không ô tìm), panel ScrollView, header tự dựng — mỗi kiểu với các cách chỉnh khoảng trên (`contentMargins` top 0 / 16, `defaultMinListHeaderHeight` 0, `listSectionSpacing(.compact)`, đệm panel 16). Mỗi trang ~1,7 s: đầu dò UIKit (`HeaderSpacingLabProbe`) chụp đáy thanh, đáy ô tìm, mũi back hệ thống, ô / khung tiêu đề nhóm đầu; `labMeasure` (khung SwiftUI) đo chữ tiêu đề nhóm, chữ hàng đầu, panel đầu, icon "…" phải, mũi back tự dựng. Kết quả hiện trên màn + log `📐 [HeaderLab]` (kèm một lần cây view con của thanh: lớp + khung, để biết iOS 26 dựng ô nút toolbar bằng gì) + nút chia sẻ báo cáo. Gỡ cả thư mục khi đã áp.
- **Đầu dò `📐 [HeaderLayout]`** (`PageHeaderLayoutProbe`, vẫn tạm): iOS 26 không còn lớp "HostingView" trong thanh (1.3.1025 ra `left=- right=-`) ⇒ đo **view lá** nhìn thấy ở hàng nút, chia trái / phải (số mảnh, mép trái nhất – phải nhất); trang có tab vuốt (Kệ, Kho tiện ích) ⇒ đo scroll view dọc trong trang đang hiện; chọn scroll view theo phần **nằm trong cửa sổ**; `note=scrolled / offscreen / nobar` đánh dấu dòng nhiễu.
- **Mũi back tự dựng trùng chỗ mũi back hệ thống**: `HeaderBackButton` lùi `HeaderMetrics.backChevronOutdent` (8pt) ra ngoài lề (bề ngang bố cục 30pt, vùng chạm vẫn 38pt) ⇒ mũi ở `lề − 8` như nút back hệ thống (đo: x=12 khi lề 20). Áp cho trang con trong sheet, sheet hub, Reader, truyện tranh, trang xem phim mở bằng UIKit. Khoảng mũi → chữ tiêu đề giữ ~8pt.
- `ui-conventions.md`: luật nút back tự dựng thêm phần lùi 8pt.
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần: mở Cài đặt › Ghi log hệ thống › Thử nhịp dọc header, bấm Chạy, để yên ~50 s, bấm chia sẻ gửi báo cáo; nhìn mũi back ở trang con sheet hub / Reader có thẳng với mũi back của trang Cài đặt không.

## [1.3.1029] - 2026-11-20

### chore: vtts — CI giữ cache từ điển khi build đỏ, kiểm thử shim nhanh hơn

Tiếp 1.3.1028 (rà lại trước khi đẩy; chưa lượt CI nào chạy bản vtts).

- **Cache tài sản vtts tách `actions/cache/restore` + `save`**: `actions/cache` gộp chỉ lưu khi cả job xanh ⇒ lượt đầu mà shim C / code Swift còn lỗi biên dịch sẽ dựng lại VLEX ~8 phút mỗi lần đẩy sửa. Nay `fetch_vtts_assets.sh` có hai bước — `assets` (tải model, dựng VLEX, `vtts_say` đọc thử) rồi lưu cache ngay, sau đó `smoke` (kiểm thử shim) — không tham số vẫn chạy cả hai (build local). Bước `smoke` từ chối chạy khi chưa có tài sản khớp stamp.
- **Kiểm thử shim nhẹ hơn**: bản dựng thử đặt `-DVTTS_BRIDGE_SEGMENT_CP=150` ⇒ đường chia đoạn dài chạy với 8 bản câu thử (~550 code point, 4 phần) thay vì ~60 bản (~4 phút tiếng dưới ASan, mỗi giọng); chỉ giọng đầu chạy đoạn dài (`--long`), vẫn đòi đúng 8 lần tiếng câu thử + khoảng 150 ms. `vtts_bridge.c` thêm `#error` khi `VTTS_BRIDGE_SEGMENT_CP` ra ngoài `[1, VTTS_TEXT_MAX_CP)` ⇒ không phần nào chạm mức 4096 code point mà front-end cắt im lặng. Thêm `-fno-sanitize=function` (Apple clang mới bật nó cho C; tránh báo động nhầm ở callback nội bộ của upstream).
- `ci-release.md`: mục vtts ghi hai bước + cách lưu cache.
- Kiểm: `bash -n`, thử lại các hàm kiểm stamp / WAV của script trên Windows, YAML hợp lệ, `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`). **Không biên dịch được C / Swift tại chỗ (Windows).**

## [1.3.1028] - 2026-11-20

### feat: vtts Việt–Anh — runtime C, tài sản đóng trong IPA, service tổng hợp

Anh Bửu duyệt plan `Docs/Plans/2026-11-20-vtts-integration.md` (phần A — nền tảng; phần B là 1.3.1027). Nguồn ghim: `tuanpmt/vtts` commit `c5c8c0018dc6a1651d8ee6d4ec3635f6ff2f8e1e` (Apache-2.0) cho runtime lẫn script dựng từ điển, model release `v0.4.0` (`nu-10` nữ, `nam-1` nam, bản M, 2 580 320 byte mỗi file).

- **Gói SPM cục bộ `Vendor/vtts`** (product `CVTTS`, `project.yml` dùng `path:`): `Sources/CVTTS/runtime/{include,src}` chép nguyên văn ở commit ghim (`VTTS_COMMIT.txt`), kèm `LICENSE` / `NOTICE` của vtts; mọi ngôn ngữ phụ tắt bằng `VTTS_ENABLE_<L>=0` (27 ngôn ngữ, cấu hình `langs_test_none` của upstream) ⇒ chỉ còn Việt / Anh / auto. Bridging header của app không đổi.
- **Shim C `vtts_bridge`** (`Sources/CVTTS/bridge/`, header công khai duy nhất Swift thấy — không struct nào của vtts lộ ra): `create` mmap model + VLEX và giữ suốt đời handle (cả hai được đọc tại chỗ), workspace front-end ~145 KB trên heap, fd đóng ngay sau mmap; `synthesize` = `vtts_text_to_ids_ex` chế độ `VTTS_LANG_AUTO` (chọn Việt / Anh theo từng từ, có VLEX) ⇒ mỗi chunk ≤ 40 âm tiết tổng hợp riêng, nối với 150 ms im lặng như `tools/vtts_say.c`. Khác `vtts_say`: lấy số khung thật bằng `vtts_durations` rồi mới cấp arena / PCM đúng cỡ (vtts_say cấp theo n × max_duration — hàng chục MB với 320 id); id ngoài từ vựng ⇒ lỗi thay vì đọc lố bảng embedding; đoạn > 2000 code point tự chia ở ranh giới câu (front-end cắt **im lặng** phần sau 4096 code point); thẻ huỷ nguyên tử xét trước mỗi chunk. Model không phải bộ token vi-en / không có chế độ auto ⇒ mã lỗi riêng.
- **`Scripts/ci/fetch_vtts_assets.sh`** (máy Mac chạy trước `xcodegen`, idempotent theo `.stamp`): tải + kiểm SHA256 2 model; clone vtts ở commit ghim, so runtime đã vendor **từng byte** (lệch ⇒ đỏ); dựng `lex_en.bin` bằng `scripts/frontend/build_lexicon.py` (CMUdict ghim + SHA256, Python ≥ 3.11 chỉ thư viện chuẩn, ~8 phút — đo trên máy Windows: 1 860 736 byte); dựng `vtts_say` bằng clang với đúng cờ tắt ngôn ngữ của gói, đọc thử "Đã kết nối Bluetooth với AirPods, chương này tên là The Last Train." bằng từng giọng (kiểm `token_set vi-en`, `mode auto lex 1`, id < vocab, WAV ≥ 1 s, không im lặng); **luôn** biên dịch shim + runtime đã vendor + `Scripts/ci/vtts_bridge_smoke.c` với ASan/UBSan và chạy từng giọng (câu thử, chuỗi rỗng, chỉ dấu câu, đoạn > 4096 code point, thẻ huỷ), so WAV shim với `vtts_say` (lệch chỉ cảnh báo). Tài sản ⇒ `Vendor/vtts-assets/vtts` (gitignore), `project.yml` khai folder resource ⇒ `FreeBook.app/vtts/`.
- **`build-ipa.yml`**: bước Cache (khoá = hash script + `VTTS_COMMIT.txt` + tên model) + chạy script trước `xcodegen generate` (`pipefail`); artifact `vtts-samples` (WAV đọc thử); `paths` của `push` / `pull_request` thêm `Vendor/vtts/**`, `fetch_vtts_assets.sh`, `vtts_bridge_smoke.c`.
- **Swift `Services/TTS/Vtts/`**: `VttsVoice` (2 giọng, `resolve` id lạ ⇒ `nu-10`), `VttsRuntime` (handle theo giọng, **mọi** lượt gọi C trên **một** hàng đợi nối tiếp — front-end vtts có mảng `static` toàn cục, runtime có setter toàn cục; tra / nhả handle chỉ trong hàng đợi; `releaseAll` không chặn), `VttsTTSService` (`LocalTTSEngine`, qua `PiperSynthesisCoordinator`; tổng hợp `length_scale = 1`, tốc độ do `NghiAudioPlayerQueue`; khoảng lặng đuôi `VieNeuTTSEngine.pauseSeconds(for:)` như Turbo; áp "Phiên âm tiếng Nhật" của chính trình đọc ở tầng service (`TTSJapaneseTextTransliterator.apply(_, tool: "vtts")`) rồi NFC; WAV 22 050 Hz `WAVEncoder.encodePCM16`; `TTSEngineRTFStore` chia cho phần lời đọc; log `🗣️ [Vtts]` nạp giọng + mỗi đoạn (ký tự, số câu, ms, RTF), lỗi có `❌`, `CancellationError` không ghi lỗi).
- Bản quyền: `Vendor/vtts/THIRD_PARTY_NOTICES.md` + `LICENSE-cmudict.txt` (VLEX dẫn xuất từ CMUdict, BSD-2, phân phối trong IPA). `ci-release.md`: mục vtts (bước tài sản, commit ghim, cách nâng runtime / model).
- Kiểm: đọc code, `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`), `bash -n` + thử các hàm kiểm stamp / WAV của script trên Windows, YAML hợp lệ; tải 2 model và kiểm SHA256, dựng VLEX thành công trên máy này. **Không biên dịch được C / Swift tại chỗ (Windows)** — biên dịch, đọc thử và kiểm thử shim chỉ chạy trên CI; chưa thử trên máy iOS.

## [1.3.1027] - 2026-11-20

### feat: vtts Việt–Anh — nối trình đọc vào app, Cài đặt TTS, sheet chọn giọng, giọng dự phòng

Anh Bửu duyệt plan `Docs/Plans/2026-11-20-vtts-integration.md` + mockup màn Cài đặt TTS (phần B; phần A — runtime C, tài sản, `Services/TTS/Vtts/` — là commit riêng).

- **Nối vào `TTSManager`** (`TTSManager+Vtts.swift`, mới; khuôn VieNeu): `tool = "vtts"`; `isLocalEngine` **và** `isExtensionTool` thêm `"vtts"` cùng lúc; `localEngine` ⇒ `VttsTTSService.shared`. Khoá riêng `vttsVoice` / `vttsRate` / `vttsPitch` / `vttsChunk` (mặc định 150 ký tự) — `persistSpeed` / `persistPitch` / `persistVoice` / `persistChunkLength` / `resetPrefetchSettings` có nhánh vtts (không lọt vào `extRate_vtts`…). `TTSManager.swift` **không thêm dòng ròng nào** (3413 dòng): đổi tại chỗ dòng log của `tool.didSet` ⇒ `noteReaderToolChanged(from:)` và nhánh `vieneu` của `loadParamsForCurrentTool` ⇒ `applyOfflineModelParamsIfNeeded()` (VieNeu / vtts).
- **Nhả runtime**: trình đọc rời vtts ⇒ `releaseVttsRuntimeIfUnused` (giữ nếu vtts là giọng dự phòng của trình đọc online mới); sheet chọn giọng đóng sau lượt thử giọng vtts cũng gọi hàm này. Chuyển **sang** vtts không nhả VieNeu / Piper — đường cũ NghiTTS ↔ VieNeu cũng không nhả nhau khi đổi trình đọc.
- **Rà mọi chỗ so `"nghitts"` / `"vieneu"`**: vtts đi nhánh "không phải vieneu" (nhẹ như Piper) — ngưỡng đệm chung `nghittsSafeCachedTimeThreshold`, 1 lượt refill, 2 optional reserve; prefix chương kế chờ còn ≤ 2 dòng cha như VieNeu (`!= "nghitts"` ở `checkAndPromoteNextChapterAudioIfNeeded` / `TTSChapterPrefetcher`), nhịp nhiệt gọi `triggerNextChapterPrefetch` như VieNeu; khoá `nghittsPrefetchDelay` (Piper) không đụng. `currentPrefetchCount` rơi vào `extPrefetchCount` nhưng chỉ đường remote đọc nó.
- **Cài đặt TTS** (mockup): Picker thêm "vtts Việt–Anh (Offline)" sau VieNeu; "Giọng đọc" = hàng chung (`TTSVoiceEngine.vtts`: "Nữ · nu-10", "Có sẵn trong app · 2,6 MB", badge Nhẹ) ⇒ sheet chọn giọng chung (`VttsVoicePickerList`, mới: 2 giọng, ▶ thử giọng qua `TTSVoicePreviewPlayer` `.vtts`, không tải / xoá); "Quản lý riêng" chỉ "Phiên âm tiếng Nhật" (khoá `ttsJapaneseTransliterationEnabled.vtts`, mặc định tắt, giải thích sau "?"); nhánh cấu hình tiện ích của mục này nay xét `isExtensionTool` thay `!= "system"`; dòng cao độ "(*) Engine offline (NghiTTS/VieNeu/vtts)…"; "Tải trước dữ liệu" chỉ "Độ dài phân đoạn (vtts)" (50…500, bước 10) — `TTSSettingsView+Vtts.swift`, mới.
- **Giọng dự phòng**: `TTSOnlineFallbackSettings.Engine.vtts` ("vtts Việt–Anh (Offline)"); các toán tử ba ngôi hai engine đổi thành `switch` (`title`, `pickerTitle`, `speedKey`, giọng — `onlineFallbackVoice(for:)` mới); `fingerprint` có nhánh vtts; bản build thiếu dữ liệu ⇒ `engineUnavailable`. Màn Giọng dự phòng: hàng giọng + mục Quản lý riêng của vtts; chọn giọng ở đây chỉ ghi `vttsVoice` (`selectVttsVoice`), không đổi giọng trình đọc online.
- `TTSSettingsSnapshot` / `TTSSynthesisIdentity` không thêm trường: `tool` + `selectedVoice` + `chunkLength` + cờ tiếng Nhật theo `tool` + `fingerprint` đã phủ vtts. Khối đầu phiên log "vtts · <giọng>"; tab Cài đặt hiện "vtts".
- `tts.md`: thêm gạch "vtts Việt–Anh".
- Kiểm: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows)** — biên dịch phụ thuộc type của phần A (`VttsVoice`, `VttsTTSService`), chỉ CI kiểm được; chưa chạy trên máy.

## [1.3.1026] - 2026-11-20

### fix: TTS tạm dừng lâu rồi bấm phát ở sheet nghe mini không phát lại — luôn bật lại phiên âm thanh, VieNeu / NghiTTS kiểm tiếng chạy thật

Anh Bửu: "có lỗi để pause truyện lâu bấm start bằng sheet mini thì không phát lại, phải bấm tai nghe mới được. Phần nghe nhạc thì chưa biết" → plan → "Duyệt".

- **Nguyên nhân (đọc code, chưa có log máy)**: nút tai nghe Reader (trang đã cuộn khỏi đoạn đang dừng) dừng hẳn phiên rồi dựng phiên mới ⇒ bật lại phiên âm thanh; nút ⏯ của sheet mini chỉ `resume()`. Đường đó (1) không bật lại `AVAudioSession` vì tin cờ `isAudioSessionConfigured` — trong lúc tạm dừng phiên có thể bị app khác phát tiếng, phim trong app trả phiên, nghe thử giọng ở Cài đặt TTS, cuộc gọi tắt mà cờ vẫn `true` (ngắt lúc TTS không phát trước đây không hạ cờ); (2) với VieNeu / NghiTTS không kiểm `play()` có chạy thật — trình phát báo `true` mà thời gian đứng yên ⇒ kẹt "đang phát" không tiếng (đường Google / tiện ích đã có bước kiểm `verifyRemoteResumeProgress`).
- **Sửa** (`TTSManager+ResumeRecovery`, mới): `resume()` đường tạm dừng → phát gọi `reactivateAudioSessionForResume()` (hạ cờ rồi `setCategory` + `setActive` lại) thay cho `configureAudioSession()`; VieNeu / NghiTTS phát tiếp được ⇒ `didResumeNghiPlayer()` kiểm sau 0,25 s, `currentTime` không tiến ⇒ dừng player, bật lại phiên, đọc lại đoạn hiện tại từ đầu đoạn. `handleInterruption` `.began` lúc TTS đang tạm dừng cũng hạ cờ phiên.
- Log `🔊 [TTSResume]` (bật lại phiên OK / lỗi; play() trả true mà không tiến ⇒ đọc lại đoạn) để xác nhận trên máy.
- **Nghe nhạc**: nút phát của trình nghe (`AudioPlaybackSession.play` → `prepareAudioForPlayback`) luôn `setActive(true)` trước khi phát ⇒ không dính lỗi này, không sửa.
- `tts.md`: thêm gạch "Phát tiếp sau tạm dừng".
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần thử: tạm dừng TTS, mở app khác phát video / nhạc (hoặc nghe thử giọng ở Cài đặt TTS), quay lại bấm ⏯ ở sheet mini — phải đọc tiếp (VieNeu / NghiTTS có thể đọc lại từ đầu đoạn đang dừng); bật Ghi log để xem dòng `🔊 [TTSResume]`.

## [1.3.1025] - 2026-11-20

### chore: Log đo bố cục header 📐 [HeaderLayout] (tạm thời) để chỉnh khoảng cách dọc dưới tiêu đề

Anh Bửu: "hàng 1 với hàng 2 nhiều lúc cách khoảng rỗng, nhiều lúc khoảng hẹp", "hàng icon và hàng tiêu đề cũng có khoảng cách khác nhau giữa các màn hình" → plan header (đo trước khi chốt nhịp dọc 16pt) → "Làm tiếp".

- Mới `PageHeaderLayoutProbe` (`Views/Common/PageHeader/`, **tạm thời**): đầu dò UIKit 0×0 gắn ở mọi trang dùng `PageTitleModifier`. Chỉ khi công tắc Ghi log bật: ~0,8 s sau khi trang hiện ghi **một** dòng `📐 [HeaderLayout]` toạ độ cửa sổ (pt):
  - tiêu đề, kiểu tiêu đề, cách trình bày (gốc tab / đẩy vào / sheet / toàn màn), bề ngang cửa sổ, vùng an toàn trên;
  - thanh điều hướng: y, cao, lề trong (`layoutMargins`);
  - mũi back hệ thống (x, rộng, cao, tâm y);
  - các ô SwiftUI của toolbar bên trái / phải (x đầu–cuối, y, cao) — tiêu đề cạnh nút trái, cụm icon phải;
  - ô tìm `.searchable` (x, y đầu–cuối);
  - scroll view chính của trang (loại, y, inset trên, offset, gốc nội dung) và ô / tiêu đề nhóm đầu tiên của List (y, x đầu–cuối, cao).
- Không đổi gì trên màn. Có số thật rồi mới chốt cách đưa khoảng chân header → nội dung đầu tiên về một nhịp (Form / List thẻ đang chừa nhiều, List trơn / panel gần như sát) và vị trí mũi back hệ thống; xong thì **gỡ đầu dò**.
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần: bật Ghi log, mở các màn mẫu, xuất log phiên gửi lại.

## [1.3.1024] - 2026-11-20

### fix: Header — mũi ‹ trang con sheet hub cùng màu nhấn, khoảng tiêu đề cạnh nút back thành token chung

Gom ba bản header (1.3.1020, 1.3.1022, 1.3.1023) từ session con; dọn hai chỗ session con để ngỏ.

- **Mũi ‹ trang con Tác vụ AI / Kiểm tra nguồn của sheet hub** (`FloatingHubAITaskListView`, `FloatingHubSourceCheckListView`): bỏ `tint: Color.primary` ⇒ màu nhấn như trang con Thông báo / màn kiểm tra trong cùng sheet hub (trước một sheet có hai màu mũi).
- **Khoảng tiêu đề lùi về nút back 17pt** thành `HeaderBackButton.titleOverlap` (trước là hằng `private` ở `PageTitleModifier` + chép tay ở hai file hub).
- Entry 1.3.1023 sửa câu "vùng chạm không đổi": khoảng 19 nút trước chưa có khung nay có khung 36×38 nên vùng chạm rộng thêm về bên trái.
- `CHANGELOG.md` dời 1.3.987–994 sang `CHANGELOG.archive.md` (giữ ~30 entry).
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**.

## [1.3.1023] - 2026-11-20

### feat: Toolbar — nút ngoài cùng bên phải canh icon vào lề 16pt, icon tài sản trên toolbar 20pt

- Anh Bửu: "hàng 1 và hàng 2 header nhiều chỗ margin không giống nhau", "icon nhiều chỗ nhìn size cũng không giống nhau" — phần còn lại của lưới header chung (1.3.1017–1021): toolbar của thanh điều hướng hệ thống.
- Trước: icon nằm giữa khung chạm (36 hoặc 32 rộng) nên icon ngoài cùng lùi vào 6–10pt so với lề 16pt của tiêu đề / ô tìm / thẻ danh sách. Nay nút **ngoài cùng bên phải** của mỗi toolbar thêm `alignment: .trailing` vào `.frame(width:height:)` của icon (nút đã có khung giữ nguyên rộng / cao; khoảng 19 nút trước chưa có khung nay có khung 36×38 ⇒ vùng chạm rộng thêm về bên trái, icon vốn đã sát lề); nút bên trong cụm (🔍, ↻, nút dịch, Lọc, Chia sẻ) giữ canh giữa. Nút chữ (Lưu, Xong, `.headerTextButton()`), capsule "Áp dụng", nút "?" `SectionHelpButton`, `EditButton` không đổi.
- Số trần `17` của icon SF trong các nút đó → `HeaderMetrics.iconFontSize`; khung `36` / `38` → `HeaderMetrics.iconFrameWidth` / `iconFrameHeight` (đúng giá trị cũ, khung cao `36` giữ nguyên để không đổi cỡ thật). Icon tài sản `AppGlyph` trên toolbar → `HeaderMetrics.assetIconSize` (20pt, trước 17): nút sao chép của Gỡ lỗi từng bước (Legado), Lỗi & cảnh báo rule dịch nhanh; nút dịch `ReaderTranslationScopeMenuView(iconSize:)` của Chi tiết truyện; phễu `FilterGlyph` (đã 20, nay dùng token).
- Màn đã đổi: Kệ (🔍 | … — "…" ngoài cùng, chấm đỏ thông báo vẫn nằm đúng góc trên phải icon), Hộp thông báo, Chi tiết bộ sưu tập, Chi tiết truyện (nút dịch | …), Danh sách thể loại / Xem thêm (Lọc | Kiểu hiển thị), Tìm kiếm (Kiểu hiển thị), từ điển (VP / Name riêng, VP / Name chung, Phiên âm / Pronouns, sheet sửa từ có bút chì), Báo cáo kiểm tra (danh sách + chi tiết: Chia sẻ | Xoá), Gỡ lỗi từng bước (Legado), Danh sách kho (↻ | +), tab Legado + tab Tất cả tiện ích của Kho tiện ích, Bộ lọc tiện ích (Đặt lại), Playlist chi tiết, Cấu hình AI (+), Lịch sử phiên chat AI (thùng rác), Theo dõi nhiệt, Log phiên, Công cụ tra cứu nhanh, Dung lượng (↻ / vòng xoay đo), từ điển phiên âm NghiTTS / VieNeu, Thay thế TTS, Quản lý lọc rác, Bộ ngoặc, rule dịch nhanh (`QuickTranslationRuleIOMenu`), Quy tắc TOC.
- Không đụng (session khác làm hoặc đang làm): `PageHeader`, `HubStyleSheet`, `FloatingHub`, `TTSWidget`, `AudioPlayer`, `Reader`, `ComicReader`, `VideoPlayer`, `Discovery`, `SleepTimer`, `AppUpdate`, `ChapterTOCPanel`, `SideDrawerMenuPanel`, `SourceCheck`, `ExtensionCheckView`, `LegadoSourceCheckView`. `SideDrawerMenuModifier` chỉ có ví dụ trong comment, không có frame ⇒ không sửa.
- Kiểm: chỉ đọc code + check_architecture.py (chỉ còn violation cũ `JSDom.swift`); không build tại chỗ (Windows), chưa chạy trên máy. Cần thử: icon ngoài cùng ở các màn trên chạm đúng lề 16pt (so với tiêu đề / ô tìm / thẻ), chấm đỏ của "…" ở Kệ vẫn đúng góc, nút dịch ở Chi tiết truyện và sao chép ở Gỡ lỗi từng bước (20pt) không lệch hàng với nút bên cạnh.

## [1.3.1022] - 2026-11-20

### feat: Header sheet tự dựng — sheet hub, điều khiển nhanh TTS / nhạc, hẹn giờ, mục lục, cập nhật app về lề 16pt chung, nút back chung, tiêu đề 22pt

- Anh Bửu: "các header custom cho cảm giác logic thiết kế không giống", "hàng 1 và hàng 2 header nhiều chỗ margin không giống nhau" — áp tiếp lưới header chung (1.3.1017–1021) cho các sheet / panel tự dựng, giữ nguyên bố cục.
- Sheet hub (`FloatingHubSheet`): lề ngang trang chính / trang con nhỏ 20 → `HeaderMetrics.horizontalMargin` (16, máy ≥ 414pt 20). Tiêu đề "Lối tắt nổi" giữ `.headline` (cùng khuôn sheet kiểu hub).
- Trang con Tác vụ AI / Kiểm tra nguồn của hub (`FloatingHubAITaskListView`, `FloatingHubSourceCheckListView`): bỏ nút `chevron.left` tự vẽ + `.padding(.leading, -10)` ⇒ `HeaderBackButton` (mũi chạm lề, giữ màu chữ `Color.primary`); tiêu đề `.headline` → 22pt đậm (`rowTitleFontSize`) ngay cạnh nút, lùi 17pt như trang con có nút ‹ của `PageTitleModifier`, một dòng, dài thì cắt đuôi.
- Sheet hành động kiểu hub (`HubStyleActionSheet`): lề 20 → `horizontalMargin`; tiêu đề giữ `.headline`.
- Sheet điều khiển nhanh TTS / nhạc (`TTSQuickControlSheet`, `AudioQuickControlSheet`) và sheet "đang đọc chương này" (`ReaderTTSSameChapterSheet`): lề 20 → `horizontalMargin`; nút ⏱ khung tối thiểu 44×44 canh giữa → 36×38 (`iconFrameWidth` / `iconFrameHeight`) canh phải ⇒ chưa hẹn giờ thì icon chạm lề (đang hẹn: viên "Hủy" ngoài cùng, giữ nguyên). Bìa 52 + tên giữ.
- Sheet Hẹn giờ TTS (`TTSQuickTimerSheet` + `TTSQuickTimerHeader`): lề header 12, hàng tên chương đang phát + tab con 16 → `horizontalMargin`; nút ⚙ `gearshape.fill` trong vòng 28 nền `tertiarySystemFill` → icon trơn `gearshape` 17pt nửa đậm khung 36×38 canh phải, lề phải 10 → `horizontalMargin` (vòng nền chỉ cho header nổi trên ảnh / phim).
- Header mục lục Reader / truyện tranh (`ReaderChapterListView`, `ComicChapterListSheet+Header`): lề 12 → `horizontalMargin`; cụm nút phụ 14pt khung 32 cách 4 giữ, chỉ nút đứng cuối canh icon phải (Reader: cập nhật / vòng xoay, truyện TXT trên máy thì nút dịch lại; truyện tranh: dịch lại, chưa có mục lục thì nút kệ).
- Đầu panel Mục lục (`ChapterTOCPanelHeader`, dùng chung Chi tiết / Reader / truyện tranh / danh sách tập): lề trái 16 / phải 10 → `horizontalMargin` hai bên; nút ↓↑ khung 36 canh phải; "Mục lục" 22 → `rowTitleFontSize`, bỏ `minimumScaleFactor(0.8)` (không co chữ, dài thì cắt đuôi); ô tìm kéo ra 6pt bù khoản đệm phải sẵn có của `ChapterTOCSearchField` để hai mép ô tìm vẫn bằng lề.
- Ngăn kéo menu (`SideDrawerMenuPanel`): tiêu đề 22 → `rowTitleFontSize`, bỏ co chữ; lề phải khi có phụ kiện 10 → 16 như lề hàng ngăn kéo ⇒ viên NSFW của bảng chọn nguồn Khám phá chạm lề 16.
- Sheet "Tất cả tập" (`VideoWatchEpisodeSheet`): hàng tiêu đề lề 16 / 10 → `horizontalMargin`, "Danh sách tập (N)" 22 → token, bỏ co chữ; nút đổi kiểu Lưới / Danh sách canh icon phải khi là nút ngoài cùng (kiểu Lưới), giữa khi đứng trước ↓↑ (kiểu Danh sách).
- Sheet Hẹn giờ tắt phim / nhạc (`MediaSleepTimerSheet`), "Bản cập nhật mới" (`AppUpdateSheet`), "Có gì mới ở bản này" (`AppReleaseNotesSheet`): lề ngang 20 → `horizontalMargin` (lề dọc 20 giữ), tiêu đề 22 → `rowTitleFontSize`; hai sheet cập nhật bỏ co chữ tiêu đề, icon cạnh tiêu đề cùng token cỡ.
- Chưa sửa (ngoài phạm vi): nội dung dưới vài header vẫn lề cứng 16 — `SleepTimerOptionsView`, `TTSQuickTimerChapterList`, `VideoEpisodeGridView`, `.padding(.horizontal)` của `ChapterTOCPanelBackground` ⇒ máy ≥ 414pt lệch 4pt so với tiêu đề.
- Kiểm: chỉ đọc code + check_architecture.py (chỉ còn vi phạm cũ JSDom.swift); không build tại chỗ (Windows), chưa chạy trên máy. Cần thử: sheet hub (trang chính, Tác vụ AI, Kiểm tra nguồn hai lượt — mũi ‹ chạm lề, chữ 22pt), sheet nghe TTS / nhạc (⏱ chưa hẹn và đang hẹn + "Hủy"), sheet Hẹn giờ TTS (⚙ trơn góc phải), mục lục Reader / truyện tranh / tab Mục lục Chi tiết (nút ↓↑ và hai mép ô tìm thẳng lề), ngăn kéo chọn nguồn Khám phá (viên NSFW), "Tất cả tập" hai kiểu, hai sheet cập nhật app.

## [1.3.1021] - 2026-11-20

### feat: Nút ⌄ của sheet Kiểm tra tiện ích / Kiểm tra nguồn và màn AI toàn màn dời sang trái, tiêu đề 22pt kế bên

Anh Bửu (sau danh sách các màn có 2 nút bên phải): "Kiểm tra tiện ích / Kiểm tra nguồn, khi mở dạng sheet / Màn AI toàn màn của Reader dời ⌄", "size tiêu đề bằng size tiêu đề bình thường nhé".

- Mới `HeaderLeadingIconButton` (`Views/Common/PageHeader/`): nút icon đứng **trước tiêu đề** ở hàng nút — icon SF 17pt nửa đậm, khung 36×44 canh trái (icon chạm lề), tiêu đề lùi `titleOverlap` 10pt vào khung để icon cách chữ ~10pt, tiêu đề đè lên không nhận chạm.
- `PageTitleModifier` thêm `leadingIcon` (kiểu `.leading`) + `.pageTitle(_:style:leadingIcon:)`: nút và tiêu đề 22pt đậm chung một `ToolbarItem`; tiêu đề cạnh nút có trần bề ngang như cạnh nút back.
- **Kiểm tra tiện ích / Kiểm tra nguồn mở dạng sheet** (`ExtensionCheckView`, `LegadoSourceCheckView`): lượt đang chạy ⇒ ⌄ thu nhỏ đứng trước tiêu đề (`SourceCheckHeaderButtons.leadingMinimize`), cụm phải chỉ còn Chia sẻ (canh icon vào lề phải). Mở dạng trang (có nút back) và trang con trong sheet hub giữ như cũ.
- **Màn AI toàn màn của Reader** (`ReaderAIFullScreenView`): ⌄ Đóng (trước là `chevron.down.circle` ngoài cùng bên phải) thành `chevron.down` trước tiêu đề "Trợ lý AI" 22pt đậm + tên phiên; bên phải chỉ còn "…" (khung 36, canh vào lề).
- `ui-conventions.md`: thêm luật nút ⌄ trước tiêu đề.
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần thử: Tiện ích › Kiểm tra (mở dạng sheet) lúc đang chạy — ⌄ bên trái thu nhỏ đúng, hết lượt thì ⌄ biến mất, tiêu đề về sát lề; màn AI toàn màn — ⌄ đóng màn, "…" mở ngăn kéo.

## [1.3.1020] - 2026-11-20

### feat: Header tự dựng màn đọc / xem / nghe + Khám phá — lề 16pt chung, nút back chung, "…" có vòng, khối tiêu đề hai dòng

- Anh Bửu: "các header custom cho cảm giác logic thiết kế không giống", "hàng 1 và hàng 2 header nhiều chỗ margin không giống nhau" — đưa header tự dựng của màn đọc / xem / nghe + Khám phá về lưới chung `HeaderMetrics` (1.3.1017); bố cục từng màn giữ nguyên, chỉ đồng bộ lề, cỡ, nút.
- Reader (`ReaderHeaderFooterOverlayView`): lề 10 → `HeaderMetrics.horizontalMargin` (cả hàng 2); `chevron.left` tự vẽ → `HeaderBackButton` màu chữ theo nền đọc; "…" ngoài cùng canh phải trong khung 36×38; cụm phải giữ cách 6 khung 36 (ngoại lệ đã ghi trong chuẩn); nút dịch hàng 2 icon 19 → 20 (`assetIconSize`); tên truyện 16 đậm → 16 nửa đậm, chương 13 medium → 13 thường (giữ mũi ⌄ và màu chữ 72%).
- Tấm phủ Reader Xoá từ rác / Dịch / Copy nội dung gốc: tiêu đề 20 → 22 đậm (`rowTitleFontSize`); lề ngang cả panel 12 → `horizontalMargin` để tiêu đề thẳng hàng với các hàng bên dưới (panel Dịch của truyện tranh dùng chung view nên đổi theo). Nút chọn chữ chevron 13pt trong vòng 28 giữ nguyên.
- Truyện tranh (`ComicReaderChromeView`): lề thanh trên 8 → `horizontalMargin` (thanh dưới giữ 8); back → `HeaderBackButton` trắng; tiêu đề đảo về đúng thứ tự bằng `HeaderTitleBlock`: tên truyện dòng 1 (16 nửa đậm trắng), chương dòng 2 (13, trắng 60%) — lối mở không mang tên truyện ⇒ chỉ một dòng tên chương; icon dịch 17 → 20; "…" canh phải.
- Trình phát phim (`VideoPlayerTopBar`, `VideoWatchPosterView`): lề 8 → `horizontalMargin`; ⌄ ngoài cùng trái canh trái trong khung 32×38 (cặp ⌄ ✕ giữ cách 2); menu `ellipsis` trơn → `ellipsis.circle` canh phải; cụm phải giữ cách 6 khung 36; tên phim / tập → `HeaderTitleBlock` (16 nửa đậm trắng / 13 trắng 70%). `VideoPlayerIconLabel` / `VideoPlayerIconButton` thêm tham số `alignment` (mặc định canh giữa — thanh dưới, danh sách tập không đổi).
- Trang đè lên màn xem (`VideoWatchPagePresenter`): nút back tự vẽ trong toolbar → `HeaderBackButton` (màu nhấn, giữ nhãn "Quay lại màn xem phim").
- Màn nghe (`AudioPlayerHeader`): lề 6 → `horizontalMargin`; ⌄ khung 44×44 → 38×44 canh trái (icon thường 17pt); `ellipsis` trơn 44×44 → `ellipsis.circle` khung 36×38 canh phải; giữa thành `HeaderTitleBlock` căn giữa: tên album dòng 1 (16 nửa đậm), "Phát từ album" dòng 2 (13, trắng 65%) — trước đây "Phát từ album" nhỏ nằm trên. Hàng giữ cao 48.
- Khám phá (`DiscoveryView`, `DiscoverySourceMenuButton`): ba nút lọc / lưới / tìm thôi là vòng tròn nền 38 cách 4 → nút trơn khung 32×38 cách 2 như cụm 🔍 | … của Kệ (nút lọc dùng kiểu `.toolbar` của `FilterGlyph`, icon 20), Tìm ngoài cùng canh phải; `.padding(.horizontal)` → `horizontalMargin`. Vòng tròn ảnh nguồn + tên / link nguồn bên trái giữ nguyên.
- Kiểm: chỉ đọc code + check_architecture.py (chỉ còn violation cũ JSDom.swift); không build tại chỗ (Windows), chưa chạy trên máy. Cần thử: mũi back / ⌄ / "…" chạm lề 16pt (20pt ở máy Plus / Pro Max và phim nằm ngang) ở Reader, truyện tranh, phim dọc + ngang, màn bìa phim, màn nghe, Khám phá; tên phim dài không đè cụm nút phải khi hiện đủ nút (hẹn giờ, phụ đề, khoá xoay); panel Dịch (Reader + truyện tranh) không xuống dòng khác trước ở máy 375pt; màu chữ header Reader ở nền Sáng / Trầm ấm.

## [1.3.1019] - 2026-11-20

### feat: Công tắc Mờ bìa NSFW ở sheet Kiểu hiển thị, đổi mọi chữ 18+ thành NSFW

Anh Bửu: "sửa những chỗ có chữ 18+ thành nsfw hết, ghi vào rule là nội dung nhạy cảm thì ghi là nsfw hoặc nội dung nhạy cảm thôi", "thêm config làm mờ cover nội dung nhạy cảm … có thể bật tắt ở kiểu hiển thị" → chọn mặc định **tắt**, bìa lớn Chi tiết **cũng mờ**, bỏ chỗ đặt ở Kiểu hiển thị danh sách, công tắc ở **góc phải hàng tiêu đề** sheet (mockup A) → duyệt.

- **Mờ bìa NSFW** (`Views/Common/NsfwCoverBlur/NsfwCoverBlurModifier.swift`, khoá `nsfwCoverBlurEnabled`, mặc định tắt):
  - Công tắc "Mờ bìa NSFW" ở góc phải hàng tiêu đề `BookListLayoutSheet` (mọi màn mở sheet Kiểu hiển thị; sheet không cao thêm) + "Làm mờ bìa nội dung nhạy cảm" ở Cài đặt › Giao diện › Nội dung nhạy cảm (`NsfwSettingsView`, thêm đoạn giải thích trong "?").
  - `BookCoverView` tự xét `RepositoryFilterPolicy.isNsfwBook` (chỉ khi công tắc bật) ⇒ Kệ, Lịch sử, Bộ sưu tập, Tìm trong Kệ, tab Tải, sheet nhấn giữ, Chi tiết (cả bìa lớn), đầu mục lục, widget TTS.
  - `RemoteCoverImage` mờ theo cờ môi trường `coversAreNsfw` do màn của nguồn đặt (`.nsfwCoverContext`): Khám phá (trang chủ section + tab danh mục — `DiscoveryView`), Thể loại / Xem thêm (`CategoryNovelsListView`), Tìm kiếm (`searchResultCover` + lưới `SearchSingleSourceResultsView`), đề xuất ở Chi tiết (`SuggestRowView`). Màn xem phim / nghe, playlist, avatar bình luận không gắn cờ ⇒ không mờ.
  - `.blur` luôn gắn (bán kính 0 khi không mờ, theo cạnh ngắn ×0,12, tối thiểu 6) để bật / tắt không đổi danh tính view (ô bìa không nháy placeholder); nhãn tag / dải tên đè ngoài nên vẫn rõ.
- **Đổi "18+" ⇒ "NSFW"** ở 133 chỗ (53 file `Sources/` + `.claude/rules` + `rules.md`): chữ trên màn hình ("Phim NSFW", "Chỉ nguồn NSFW", "Đánh dấu / Bỏ đánh dấu NSFW", "ẩn N nguồn NSFW", "Mục NSFW được bỏ qua", toast, lỗi sao lưu, tên che "mục NSFW" ở playlist), comment, log. "Nội dung 18+" ⇒ "Nội dung nhạy cảm" (bộ chọn Cấu hình tiện ích, nhãn trợ năng). Nhãn đỏ trên icon tiện ích (`ExtensionNsfwBadge`) thành "NSFW", chữ hệ số 0,22 (trước 0,28), dời phải thêm chút.
  - Giữ: từ khoá nhận diện `"18+"` trong `ExtensionNsfwClassifier`, ví dụ dữ liệu thẻ `"18+,nsfw"`, emoji 🔞 đầu log, "iOS 18+" trong `rules.md`, entry CHANGELOG cũ.
- Luật mới trong `AGENTS.md` (Quy ước đặt tên): nội dung nhạy cảm chỉ ghi "NSFW" / "nội dung nhạy cảm"; kèm ghi chú cách gắn mờ bìa cho màn danh sách mới.
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần thử: bật công tắc ở sheet Kiểu hiển thị (Kệ, Khám phá nguồn NSFW, Thể loại, Tìm một nguồn) và ở Cài đặt; nhãn NSFW trên icon ở cỡ nhỏ (danh sách Kho) và lớn (đầu Cấu hình tiện ích); bìa lớn Chi tiết.

## [1.3.1018] - 2026-11-20

### feat: Tiêu đề trang có nút trái luôn nằm cạnh nút trái, bỏ tiêu đề hàng 2

Anh Bửu (sau khi duyệt cỡ 28 cho hàng 2): "tôi đổi ý, đừng hiện tiêu đề 2 hàng nữa, để nó luôn hiển thị cạnh nút trái nếu có nút trái".

- **Trang có nút back** (`.backPageTitle` / `PageTitleStyle.centered`, ~64 trang): bỏ tiêu đề lớn hàng 2 của iOS (1.3.984–1.3.1017) ⇒ `navigationBarTitleDisplayMode(.inline)`, tiêu đề **22pt đậm** (cùng cỡ tiêu đề tab gốc / gốc sheet) ở ô `topBarLeading` ngay cạnh nút back, một dòng, không co chữ, trần bề ngang `HeaderMetrics.besideLeftButtonTitleMaxWidth` (rộng màn − 150, chừa nút back + cụm hai nút phải), dài thì cắt đuôi. Hết cảnh khoảng hở giữa hàng nút và hàng tiêu đề mỗi trang một khác, hết tiêu đề thu / bung khi cuộn.
- Bỏ đầu dò `PageTitleCollapseProbe` (dò nhãn tiêu đề lớn để hiện tiêu đề nhỏ khi thu) và cỡ tiêu đề lớn ở `NavigationBarAppearance` (`applyLargeTitleFont`); `HeaderMetrics` bỏ `largeTitleFontSize` / `inlineTitleFontSize` — tiêu đề trang còn **một cỡ** `rowTitleFontSize` 22.
- **Trang con trong sheet** (sheet hub: Thông báo, màn kiểm tra của một lượt; sheet kiểu hub: "Từ URL"…): nút ‹ (`HeaderBackButton`) và tiêu đề do `PageTitleModifier` dựng **chung một** `ToolbarItem` khi có `\.sheetPageBack` ⇒ thứ tự luôn ‹ rồi chữ, mũi cách chữ ~8pt. Bỏ `.sheetPageBackButton()` (mục toolbar riêng — hai mục `topBarLeading` thì iOS tự xếp); `SheetPageBackButtonModifier.swift` → `SheetPageBackEnvironment.swift` chỉ còn khoá environment.
- `ui-conventions.md`, `floating-pills.md` cập nhật theo.
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần thử: trang có nút back (tiêu đề cạnh nút back, tên dài cắt đuôi, không đè nút phải), cuộn không còn thu / bung, trang con trong sheet hub và sheet "+" của Kệ ("Từ URL"): nút ‹ đứng trước tiêu đề, bấm về trang chính.

## [1.3.1017] - 2026-11-20

### feat: Header thống nhất — bộ số chung HeaderMetrics, tiêu đề hàng 2 28pt, tiêu đề hàng 1 không co chữ, nút back trang con trong sheet chạm lề

Anh Bửu: "hàng 1 và hàng 2 header nhiều chỗ margin không giống nhau", "icon nhiều chỗ nhìn size cũng không giống nhau, title lớn chưa đủ to", "các header custom cho cảm giác logic thiết kế không giống" → mockup so sánh trước / sau (lề 16pt chung, 6 header tự dựng, nhịp dọc) → "Duyệt, cỡ 28".

- **Bộ số chung** `HeaderMetrics` (`Sources/Common/Utils/`): lề ngang = lề thanh hệ thống (16pt, máy ≥ 414pt 20pt), hàng 44, icon SF 17 / icon tài sản `AppGlyph` 20, khung 36×38 / back 38×44, tiêu đề hàng 1 22 / hàng 2 28 / cạnh nút back 17 / khối tiêu đề màn đọc-xem-nghe 16 + 13. Luật: mép vật nhìn thấy ngoài cùng chạm lề, nút ngoài cùng canh icon vào lề trong khung thay vì canh giữa.
- **Thành phần dùng chung** (`Views/Common/PageHeader/`): `HeaderBackButton` (`chevron.backward` 17pt nửa đậm cỡ ảnh lớn như mũi back hệ thống, khung 38×44, mũi canh trái) và `HeaderTitleBlock` (dòng 1 16pt nửa đậm, dòng 2 13pt màu phụ) — header tự dựng chuyển sang ở các bản sau.
- **Tiêu đề lớn hàng 2: 22 → 28pt đậm** (`NavigationBarAppearance.applyLargeTitleFont` đọc `HeaderMetrics.largeTitleFontSize`). Trước 22pt bằng tiêu đề hàng 1, nằm lọt thỏm trong ô iOS dựng cho chữ 34pt. Đầu dò thu tiêu đề (`PageTitleCollapseProbe`, ngưỡng ≥ 20pt) không đổi.
- **Tiêu đề hàng 1 không co chữ** (`PageTitleModifier`: bỏ `.minimumScaleFactor(0.8)`) — trước đây tên dài co còn 17,6pt nên mỗi trang một cỡ; nay dài thì cắt đuôi.
- **Nút ‹ của trang con trong sheet** (`SheetPageBackButtonModifier`: sheet hub, sheet kiểu hub, Thông báo, kiểm tra nguồn) dùng `HeaderBackButton`: trước là `chevron.left` nhỏ hơn mũi hệ thống, nằm giữa khung 38pt ⇒ mũi lùi vào ~30pt trong khi tiêu đề hàng 2 ở 16pt.
- `ui-conventions.md`: thêm mục "Lưới header chung".
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần thử: tiêu đề hàng 2 các trang có nút back (cỡ, thu vào cạnh nút back khi cuộn), trang con trong sheet hub (mũi ‹ thẳng hàng tiêu đề).
