import SwiftUI

/// Khối "biên tập vùng chọn" của Reader: nới/thu vùng bôi đen, đồng bộ editor từ vùng chọn, tra
/// nhiều tầng từ điển cho một từ, và mở công cụ tra cứu ngoài.
///
/// Tách khỏi `ReaderView.swift` vì (a) file đó đã vượt baseline dòng của
/// `Scripts/check_architecture.py` nên chỉ được giảm, và (b) đây đúng là khối mà **ba** panel dùng
/// chung: màn Dịch, panel Xoá từ rác, panel Copy nội dung gốc và màn Check rule. Mọi panel đều đọc
/// `originalSentence` + `selectedWordOffset/Length` rồi gọi `updateEditorFromSelection()`.
///
/// Bất biến giữ nguyên khi di chuyển: `selectedWordOffset/Length` là **NSRange UTF-16 trên
/// `originalSentence`** (text gốc của đoạn), không phải trên chuỗi đang hiển thị.
extension ReaderView {

    // MARK: - Chuyển đổi thuần

    func getHanViet(for word: String) -> String {
        ReaderSelectionCoordinator.shared.getHanViet(for: word)
    }

    func formatMeaning(_ input: String, style: String) -> String {
        ReaderSelectionCoordinator.shared.formatMeaning(input, style: style)
    }

    // MARK: - Nới / thu vùng chọn

    func expandSelectionLeft() {
        if selectedWordOffset > 0 {
            selectedWordOffset -= 1
            selectedWordLength += 1
            updateEditorFromSelection()
        }
    }

    func shrinkSelectionLeft() {
        if selectedWordLength > 1 {
            selectedWordOffset += 1
            selectedWordLength -= 1
            updateEditorFromSelection()
        }
    }

    func shrinkSelectionRight() {
        if selectedWordLength > 1 {
            selectedWordLength -= 1
            updateEditorFromSelection()
        }
    }

    func expandSelectionRight() {
        let ns = originalSentence as NSString
        if selectedWordOffset + selectedWordLength < ns.length {
            selectedWordLength += 1
            updateEditorFromSelection()
        }
    }

    // MARK: - Đồng bộ editor theo vùng chọn

    func updateEditorFromSelection() {
        self.saveAsNameType = self.pinnedSaveAsNameType
        self.saveToBookSpecific = self.pinnedSaveToBookSpecific
        let ns = originalSentence as NSString
        guard selectedWordOffset >= 0 && selectedWordOffset + selectedWordLength <= ns.length else { return }
        let word = ns.substring(with: NSRange(location: selectedWordOffset, length: selectedWordLength))
        self.selectedTextForDefinition = word
        self.junkPatternInput = word

        if translationMode == "VP" {
            self.customMeaning = TranslateUtils.translateMeta(
                word,
                bookId: bookId,
                shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
            )
        } else {
            self.customMeaning = getHanViet(for: word)
        }

        // Cập nhật các tokens phân tách và tra cứu từ điển đa tầng.
        //
        // `translationTokens` chỉ phụ thuộc **đoạn văn** (và generation của từ điển/rule), không phụ
        // thuộc vùng chọn — nên 4 nút nới/thu không được trả tiền một lượt tokenize cả đoạn. Trước
        // 1.3.339 mỗi lần nhấn đều gọi lại `getTranslationTokens`, tức tokenize toàn đoạn + tra từ
        // điển từng token, đồng bộ trên main thread. Generation nằm trong khoá nên sửa một mục VP là
        // lượt sau tính lại thật, không hiện token cũ.
        let tokensKey = "\(TranslateUtils.translationGenerationToken(for: bookId))|\(originalSentence)"
        if translationTokensSource != tokensKey {
            self.translationTokens = TranslateUtils.getTranslationTokens(for: originalSentence, bookId: bookId)
            self.translationTokensSource = tokensKey
        }
        self.dictionaryMatches = getDictionaryMatches(for: word)
        refreshSuggestionChips(for: word)

        // Chip rule chiếu theo vùng chọn nên phải đi theo vùng chọn — bất biến ghi ở
        // `ReaderView+DefinitionPanel` nhưng trước 1.3.339 không có đường nào thực hiện, nên chip nói
        // sai sau khi nới/thu. Làm được từ nay vì `refreshRuleTraces` đã debounce + chạy off-main.
        if showingDefinitionSheet {
            refreshRuleTraces()
        }
    }

    // MARK: - Tra cứu

    /// `query` mặc định là `selectedTextForDefinition` — chuỗi đã map về **text gốc**, đúng cho các
    /// trang tra Hán-Việt/từ điển ở panel Dịch. Truyền `query` tường minh khi cần tra đúng **chữ người
    /// dùng đang thấy** (nút "Tìm").
    func performQuickLookup(using engine: SearchEngine, query: String? = nil) {
        let word = (query ?? selectedTextForDefinition).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }

        let rawUrl = engine.urlTemplate.replacingOccurrences(of: "%s", with: word)
        guard let encoded = rawUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }

        // Present one immutable URL snapshot. A fresh identity also guarantees
        // the browser cannot reuse the previous lookup request.
        self.lookupRoute = ReaderLookupRoute(urlString: url.absoluteString)
    }

    /// Nút "Tìm" của menu bôi đen (1.3.334, thế chỗ nút Check rule cũ): tra cụm đang bôi đen bằng
    /// Google. Đi qua **đúng** `performQuickLookup` để chỉ có một chỗ mở URL và một chỗ chốt scheme
    /// http/https — không tự dựng đường mở Safari thứ hai.
    ///
    /// Tra **`selectedDisplayedText`**, tức đúng chữ đang bôi đen (bản dịch khi bật dịch), **không**
    /// phải `selectedTextForDefinition` (chuỗi gốc đã map ngược) — người dùng bôi tiếng Việt thì mong
    /// Google tìm tiếng Việt. Vẫn có đường lùi về chuỗi gốc nếu vì lý do nào đó chưa có chữ hiển thị.
    func searchSelectionOnGoogle() {
        let displayed = selectedDisplayedText.trimmingCharacters(in: .whitespacesAndNewlines)
        performQuickLookup(
            using: SearchEngine(
                name: "Google",
                urlTemplate: "https://www.google.com/search?q=%s"
            ),
            query: displayed.isEmpty ? nil : displayed
        )
    }

    /// Tra một từ qua **7** tầng theo đúng thứ tự ưu tiên của pipeline dịch, để màn Dịch nói rõ
    /// nghĩa đang đến từ đâu. Thứ tự này là hợp đồng với UI — đổi thứ tự là đổi nghĩa hiển thị.
    func getDictionaryMatches(for word: String) -> [DictionaryMatchInfo] {
        var matches: [DictionaryMatchInfo] = []
        guard !word.isEmpty else { return matches }

        let manager = TranslationManager.shared
        let bookDicts = manager.getBookDictionaries(for: bookId)

        // 1. Book Names
        if let bookNames = bookDicts.names,
           let match = bookNames.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            matches.append(DictionaryMatchInfo(source: "Names (Riêng)", translation: match.value))
        }

        // 2. Global Names
        var namesTranslation: String? = nil
        if let customNames = manager.customNamesDict,
           let match = customNames.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            namesTranslation = match.value
        } else if !manager.deletedNames.contains(word),
                  let names = manager.namesDict,
                  let match = names.findLongestMatch(text: word, startIndex: 0),
                  match.length == word.count {
            namesTranslation = match.value
        }
        if let trans = namesTranslation {
            matches.append(DictionaryMatchInfo(source: "Names (Chung)", translation: trans))
        }

        // 3. Pronouns
        if let pronouns = manager.pronounsDict,
           let match = pronouns.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            matches.append(DictionaryMatchInfo(source: "Xưng hô (Pronouns)", translation: match.value))
        }

        // 4. LuatNhan
        if let luatNhan = manager.luatNhanDict,
           let match = luatNhan.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            matches.append(DictionaryMatchInfo(source: "Luật nhân (LuatNhan)", translation: match.value))
        }

        // 5. Book VietPhrase
        if let bookVP = bookDicts.vietPhrase,
           let match = bookVP.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            matches.append(DictionaryMatchInfo(source: "VietPhrase (Riêng)", translation: match.value))
        }

        // 6. Global VietPhrase
        var vpTranslation: String? = nil
        if let customVP = manager.customVietPhraseDict,
           let match = customVP.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            vpTranslation = match.value
        } else if !manager.deletedVietPhrase.contains(word),
                  let vp = manager.vietPhraseDict,
                  let match = vp.findLongestMatch(text: word, startIndex: 0),
                  match.length == word.count {
            vpTranslation = match.value
        }
        if let trans = vpTranslation {
            matches.append(DictionaryMatchInfo(source: "VietPhrase (Chung)", translation: trans))
        }

        // 7. PhienAm
        let phienAm = getHanViet(for: word)
        if !phienAm.isEmpty {
            matches.append(DictionaryMatchInfo(source: "Phiên âm", translation: phienAm))
        }

        return matches
    }
}
