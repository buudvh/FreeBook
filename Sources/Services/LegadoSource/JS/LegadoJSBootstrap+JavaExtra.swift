import Foundation

extension LegadoJSBootstrap {
    /// `java.*` đợt 2 + 3 (spec §10, §11, §13, §14) gắn thêm vào đối tượng `java` đã dựng ở `java`: trình duyệt hiện
    /// cho người dùng, ngữ cảnh `loginCheckJs`, khám phá động, phần đuôi, tệp, font, RSA. Mỗi hàm gọi một lệnh native.
    static let javaExtra = #"""
        (function (g) {
          var L = g.__lg, call = L.call, callJSON = L.callJSON, java = g.java;
          function str(v) { return v === undefined || v === null ? null : String(v); }
          function bytesOrText(v) {
            if (v === undefined || v === null) { return null; }
            if (v instanceof Uint8Array || v instanceof Int8Array || Array.isArray(v)) { return v; }
            return String(v);
          }

          // Trình duyệt hiện cho người dùng / mã xác minh (§10.8, §9.6).
          java.startBrowser = function (url, title) { call('startBrowser', [String(url), title == null ? '' : String(title)]); };
          java.startBrowserDp = java.startBrowser;
          java.startBrowserAwait = function (url, title, refetch, html) {
            return L.response(callJSON('startBrowserAwait', [String(url), title == null ? '' : String(title),
              refetch === undefined || refetch === null ? null : !!refetch, str(html)]));
          };
          java.getVerificationCode = function (imageUrl) { return call('verificationCode', [String(imageUrl)]); };

          // Ngữ cảnh loginCheckJs (§10.7): `java.ruleUrl` do runtime đặt trước mỗi lần chạy.
          var lcHeaders = null;
          L.resetLoginCheck = function () { lcHeaders = null; };
          java.initUrl = function () { call('lcInitUrl', []); lcHeaders = null; };
          java.getHeaderMap = function () {
            if (lcHeaders === null) { lcHeaders = L.map(callJSON('lcHeaders', []) || {}); }
            return lcHeaders;
          };
          java.getStrResponse = function (jsStr, sourceRegex) {
            return L.response(callJSON('lcResend', [lcHeaders, str(jsStr), str(sourceRegex)]));
          };
          java.getResponse = function () { return java.getStrResponse(null, null); };

          // Mục lục / sách (§13.3): chỉ có tác dụng khi luồng đặt hook (preUpdateJs, ruleBookInfo.init).
          java.refreshTocUrl = function () { call('refreshTocUrl', []); };
          java.refreshBookUrl = java.refreshTocUrl;
          java.refreshBookInfo = java.refreshTocUrl;
          java.reGetBook = function () { call('reGetBook', []); };

          // Khám phá động, UI nhỏ (§11.5, §11.6, §14.5).
          java.refreshExplore = function () { call('refreshExplore', []); };
          java.searchBook = function (key, scope) {
            var target = null;
            if (scope && typeof scope === 'object' && scope.bookSourceUrl !== undefined) { target = String(scope.bookSourceUrl); }
            else if (scope !== undefined && scope !== null) { target = String(scope); }
            call('searchBook', [key == null ? '' : String(key), target]);
          };
          java.openUrl = function (url) { call('openUrl', [String(url)]); };
          java.copyText = function (text) { call('copyText', [text == null ? '' : String(text)]); };
          java.refreshContent = function () { call('refreshContent', []); };

          // Phần đuôi (§13.7, §13.8, §14.5).
          java.importScript = function (path) { return call('importScript', [String(path)]); };
          java.cacheFile = function (url, saveTime) {
            return call('cacheFile', [String(url), saveTime === undefined || saveTime === null ? null : Number(saveTime)]);
          };
          java.toURL = function (url, base) {
            var u = callJSON('toURL', [String(url), str(base)]) || {};
            L.defineHidden(u, 'toString', function () { return u.href || ''; });
            return u;
          };
          java.webViewUA = call('webViewUA', []);
          java.base64Decoder = function (s, cs) { return java.base64Decode(s, cs); };
          java.clearCookie = function (url) { g.cookie.removeCookie(url); };
          java.sleep = function (ms) { call('sleep', [Number(ms)]); };
          java.getThemeConfig = function () { return ''; };
          java.webViewGetSource = function (html, url, js, sourceRegex) {
            return call('webViewGetSource', [str(html), str(url), str(js), str(sourceRegex)]);
          };
          java.webViewGetOverrideUrl = function (html, url, js, regex) {
            return call('webViewGetOverrideUrl', [str(html), str(url), str(js), str(regex)]);
          };

          // Tệp (§14.2): đường dẫn tương đối trong thư mục tệp của nguồn.
          java.downloadFile = function (url) { return call('downloadFile', [String(url)]); };
          java.readTxtFile = function (path, charset) { return call('readTxtFile', [String(path), str(charset)]); };
          java.deleteFile = function (path) { return call('deleteFile', [String(path)]) === '1'; };
          java.unzipFile = function (path) { return call('unzipFile', [String(path)]); };
          java.unArchiveFile = java.unzipFile;
          java.getTxtInFolder = function (path) { return call('getTxtInFolder', [String(path)]); };
          java.getZipStringContent = function (url, path, charset) {
            return call('zipString', [String(url), String(path), str(charset)]);
          };
          java.getZipByteArrayContent = function (url, path) { return L.hexToBytes(call('zipBytes', [String(url), String(path)])); };
          ['unrarFile', 'getRarStringContent', 'getRarByteArrayContent'].forEach(function (name) {
            java[name] = function () { call('unsupportedArchive', ['RAR']); };
          });
          ['un7zFile', 'get7zStringContent', 'get7zByteArrayContent'].forEach(function (name) {
            java[name] = function () { call('unsupportedArchive', ['7z']); };
          });

          // Font chống thu thập (§14.1): đối tượng font mờ với JS (giữ id), `null` khi lỗi.
          function fontHandle(id) { return id === null || id === undefined ? null : { __lgFont: id, toString: function () { return '[TTF]'; } }; }
          java.queryTTF = function (x) { return fontHandle(callJSON('queryTTF', [bytesOrText(x)])); };
          java.queryBase64TTF = function (b64) { return fontHandle(callJSON('queryB64TTF', [str(b64)])); };
          java.replaceFont = function (text, f1, f2, filter) {
            return call('replaceFont', [text == null ? '' : String(text), f1 ? f1.__lgFont : null, f2 ? f2.__lgFont : null, !!filter]);
          };

          // Mã hoá hiếm (§14.3, §14.4).
          java.desEncodeToBase64String = function (data, key, transformation, iv) {
            return java.createSymmetricCrypto(String(transformation), key, iv === '' ? undefined : iv).encryptBase64(data);
          };
          java.tripleDESEncodeBase64Str = function (data, key, mode, padding, iv) {
            return java.createSymmetricCrypto('DESede/' + mode + '/' + padding, key, iv).encryptBase64(data);
          };
          java.createAsymmetricCrypto = function (transformation) { return L.rsaCipher(String(transformation || 'RSA')); };
          java.createSign = function (algorithm) { return L.rsaSigner(String(algorithm || 'SHA256withRSA')); };
        })(this);
        """#
}
