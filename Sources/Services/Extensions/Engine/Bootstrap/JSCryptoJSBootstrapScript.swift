import Foundation

/// JS bổ sung cho CryptoJS của tiện ích (hợp đồng chuẩn, mục "Crypto") — gọi xuống các block `_native*` do
/// `JSCryptoJSBridge.install(in:)` cài.
///
/// - `randomPolyfill`: `crypto.getRandomValues` toàn cục (JSC không có Web Crypto). CryptoJS 4.2.0 dò `globalThis.crypto`
///   để lấy số ngẫu nhiên; thiếu ⇒ `WordArray.random` và mã hoá bằng passphrase (sinh salt) ném lỗi.
/// - `addons`: chạy sau mỗi lần `load('crypto.js')` (file của tiện ích hay bản dựng sẵn), tự bỏ qua khi `CryptoJS` không
///   có dạng CryptoJS:
///   - `WordArray.random` lấy byte native — CryptoJS 4.1 trở về trước không dò `globalThis.crypto` nên polyfill trên
///     không tới được;
///   - `AES.encryptGcm/decryptGcm` theo hợp đồng, chỉ thêm khi thiếu. Khoá/IV là WordArray thì đọc như chuỗi Latin1
///     (giống app gốc với byte < 0x80), không ra hex hợp lệ thì dùng byte thô. Thẻ sai ⇒ WordArray rỗng (hành vi iOS);
///   - `PBKDF2` với hasher SHA1/224/256/384/512 qua CommonCrypto — cùng kết quả với bản JS, nhưng 250 000 vòng mặc định
///     của 4.2.0 chạy JS thuần trong JSC (không JIT) mất hàng chục giây. Hasher khác giữ bản JS.
///
///   Không bao giờ ném lỗi ra ngoài: `prepareScript` coi `context.exception` là lỗi biên dịch của tiện ích.
enum JSCryptoJSBootstrapScript {
    /// Nạp một lần khi dựng `JSContext`, ngay sau các block `_native*`.
    static let randomPolyfill = """
    (function () {
        if (typeof globalThis === 'undefined' || typeof globalThis.crypto !== 'undefined') return;
        globalThis.crypto = {
            getRandomValues: function (array) {
                var size = array && array.BYTES_PER_ELEMENT;
                if (!size || size > 4 || Object.prototype.toString.call(array).indexOf('Float') !== -1) {
                    throw new TypeError('crypto.getRandomValues chỉ nhận Int8/Uint8/Int16/Uint16/Int32/Uint32Array');
                }
                var count = array.length * size;
                if (count > 65536) throw new RangeError('crypto.getRandomValues: tối đa 65536 byte mỗi lần');
                var bytes = count > 0 ? _nativeRandomBytes(count) : [];
                for (var i = 0; i < array.length; i++) {
                    var value = 0;
                    for (var j = 0; j < size; j++) value = value * 256 + bytes[i * size + j];
                    array[i] = value;
                }
                return array;
            }
        };
    })();
    """

    /// Chạy sau mỗi lần `load('crypto.js')`; xem doc của type.
    static let addons = """
    (function () {
        try {
            if (typeof CryptoJS !== 'object' || CryptoJS === null) return;
            var C = CryptoJS, lib = C.lib, enc = C.enc;
            if (!lib || !lib.WordArray || !enc || !enc.Hex || !enc.Utf8 || !enc.Latin1 || !enc.Base64) return;
            var WordArray = lib.WordArray, Hex = enc.Hex, Utf8 = enc.Utf8, Latin1 = enc.Latin1, Base64 = enc.Base64;

            var isWordArray = function (value) {
                return !!value && typeof value === 'object' && Array.isArray(value.words) && typeof value.sigBytes === 'number';
            };
            var rawHex = function (value) {
                return isWordArray(value) ? Hex.stringify(value) : Hex.stringify(Utf8.parse(String(value)));
            };

            if (typeof _nativeRandomBytes === 'function') {
                WordArray.random = function (nBytes) {
                    var count = Math.max(0, Math.floor(Number(nBytes) || 0));
                    var bytes = count > 0 ? _nativeRandomBytes(count) : [];
                    var words = [];
                    for (var i = 0; i < bytes.length; i++) words[i >>> 2] |= (bytes[i] & 0xff) << (24 - (i % 4) * 8);
                    return WordArray.create(words, bytes.length);
                };
            }

            var hexKeyPattern = /^(?:[0-9a-fA-F]{32}|[0-9a-fA-F]{48}|[0-9a-fA-F]{64})$/;
            var evenHexPattern = /^(?:[0-9a-fA-F]{2})+$/;
            var asText = function (value) { return isWordArray(value) ? Latin1.stringify(value) : String(value); };
            var keyHex = function (key) {
                if (key === undefined || key === null) return '';
                var text = asText(key);
                return hexKeyPattern.test(text) ? text : rawHex(key);
            };
            var ivHex = function (iv) {
                if (iv === undefined || iv === null) return '';
                var text = asText(iv);
                if (text === '') return '';
                return evenHexPattern.test(text) ? text : rawHex(iv);
            };
            var dataHex = function (value) { return value === undefined || value === null ? '' : rawHex(value); };
            var boxHex = function (value) {
                if (value === undefined || value === null) return '';
                return isWordArray(value) ? Hex.stringify(value) : Hex.stringify(Base64.parse(String(value)));
            };

            var aes = C.AES;
            if (aes && typeof aes.encryptGcm !== 'function' && typeof _nativeAesGcmSeal === 'function') {
                aes.encryptGcm = function (plaintext, key, options) {
                    var opts = options || {};
                    var result = String(_nativeAesGcmSeal(keyHex(key), ivHex(opts.iv), dataHex(opts.aad), dataHex(plaintext)));
                    if (result.indexOf('ok:') !== 0) throw new Error('AES-GCM: ' + result.replace(/^err:/, ''));
                    var parts = result.substring(3).split(':');
                    return { ciphertext: Hex.parse(parts[0]), tag: Hex.parse(parts[1]) };
                };
            }
            if (aes && typeof aes.decryptGcm !== 'function' && typeof _nativeAesGcmOpen === 'function') {
                aes.decryptGcm = function (cipher, key, options) {
                    var opts = options || {}, box = cipher || {};
                    var result = String(_nativeAesGcmOpen(keyHex(key), ivHex(opts.iv), dataHex(opts.aad),
                                                          boxHex(box.ciphertext), boxHex(box.tag)));
                    return result.indexOf('ok:') === 0 ? Hex.parse(result.substring(3)) : WordArray.create([], 0);
                };
            }

            var algo = C.algo, pbkdf2 = algo && algo.PBKDF2;
            if (pbkdf2 && typeof pbkdf2.compute === 'function' && !pbkdf2.__nativeCompute && typeof _nativePbkdf2 === 'function') {
                var jsCompute = pbkdf2.compute;
                var prfNames = ['SHA1', 'SHA224', 'SHA256', 'SHA384', 'SHA512'];
                pbkdf2.compute = function (password, salt) {
                    var cfg = this.cfg || {}, prf = null;
                    for (var i = 0; i < prfNames.length; i++) {
                        if (algo[prfNames[i]] && cfg.hasher === algo[prfNames[i]]) { prf = prfNames[i]; break; }
                    }
                    var keyBytes = Number(cfg.keySize) * 4;
                    if (prf && keyBytes > 0 && keyBytes % 1 === 0) {
                        var derived = String(_nativePbkdf2(rawHex(password), rawHex(salt), Number(cfg.iterations) || 1, keyBytes, prf));
                        if (derived) return Hex.parse(derived);
                    }
                    return jsCompute.call(this, password, salt);
                };
                pbkdf2.__nativeCompute = true;
            }
        } catch (e) {}
    })();
    """
}
