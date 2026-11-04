import Foundation

extension LegadoJSBootstrap {
    /// Lớp Java giả lập đợt 3 (spec §6.9), đăng ký vào `__lg.classes` như script `classes`:
    /// `java.util.zip.GZIPInputStream`/`InflaterInputStream`/`Inflater` (lệnh native `inflate`/`inflateUsed`),
    /// `java.nio.ByteBuffer` tối thiểu (`allocate`/`wrap` + `array()`),
    /// `java.io.InputStreamReader`/`BufferedReader` (giải bảng mã bằng `bytesToStr`), `java.net.URL` (ghép URL tương đối
    /// bằng lệnh `toURL`, các getter tách từ `href` theo ngữ nghĩa Java). Nạp sau `classes` (dùng `L.registerClass`,
    /// `L.toBytes`) và **trước** `packages`: gói `java.io`/`java.net`/`java.nio` chụp `__lg.classes` lúc `packages` dựng
    /// chúng.
    static let streams = #"""
        (function (g) {
          var L = g.__lg, call = L.call, callJSON = L.callJSON, register = L.registerClass, toBytes = L.toBytes;
          function nullPointer(what) { return new Error('java.lang.NullPointerException: ' + what + ' null'); }
          function intArg(v, fallback) { return v === undefined || v === null ? fallback : Number(v); }

          // Đọc hết một luồng vào: luồng kiểu `ByteArrayInputStream` (có `readAllBytes`), luồng có `read(buf, off, len)`
          // trả -1 khi hết, hoặc mảng byte trần.
          function drain(input) {
            if (input === undefined || input === null) { throw nullPointer('luồng vào'); }
            if (typeof input.readAllBytes === 'function') { return toBytes(input.readAllBytes()); }
            if (typeof input.read === 'function') {
              var chunks = [], buf = new Uint8Array(8192), n;
              while ((n = input.read(buf, 0, buf.length)) > 0) { chunks.push(buf.slice(0, n)); }
              return L.concatBytes(chunks);
            }
            return toBytes(input);
          }
          function inflated(bytes, mode) { return L.hexToBytes(call('inflate', [bytes, mode])); }

          // java.util.zip: giải hết ngay khi dựng (lỗi ném ở `new`, như header của GZIPInputStream), trả luồng đọc giống
          // `ByteArrayInputStream` (`read()` → 0..255 hoặc -1, `read(buf[, off, len])` → số byte hoặc -1).
          register('java.util.zip.GZIPInputStream', function (input) { return L.byteStream(inflated(drain(input), 'gzip')); });
          register('java.util.zip.InflaterInputStream', function (input, inflater) {
            return L.byteStream(inflated(drain(input), inflater && inflater.__lgNowrap ? 'raw' : 'zlib'));
          });

          // Inflater giản lược: lần `inflate` đầu sau `setInput` giải hết dữ liệu vào rồi trả dần. Dữ liệu vào phải đủ cả
          // luồng trong một lần `setInput` (cụt ⇒ ném lỗi thay vì `needsInput()`), `getRemaining()` chỉ đúng sau khi giải.
          function Inflater(nowrap) {
            var mode = nowrap ? 'raw' : 'zlib', input = null, out = null, pos = 0, used = 0;
            L.defineHidden(this, '__lgNowrap', !!nowrap);
            function clear() { input = null; out = null; pos = 0; used = 0; }
            this.setInput = function (b, off, len) {
              if (out !== null) { return; }
              var bytes = toBytes(b), start = intArg(off, 0);
              input = bytes.slice(start, start + intArg(len, bytes.length - start));
            };
            this.inflate = function (buf, off, len) {
              if (buf === undefined || buf === null) { throw nullPointer('bộ đệm'); }
              if (out === null && input !== null && input.length > 0) {
                var r = callJSON('inflateUsed', [input, mode]) || {};
                out = L.hexToBytes(r.hex); used = Number(r.used) || input.length;
              }
              if (out === null) { return 0; }
              var start = intArg(off, 0), n = Math.min(intArg(len, buf.length - start), out.length - pos);
              for (var i = 0; i < n; i++) { buf[start + i] = out[pos++]; }
              return Math.max(0, n);
            };
            this.finished = function () { return out !== null && pos >= out.length; };
            this.needsInput = function () {
              if (out === null) { return input === null || input.length === 0; }
              return pos >= out.length && input.length - used <= 0;
            };
            this.getRemaining = function () {
              if (input === null) { return 0; }
              return out === null ? input.length : Math.max(0, input.length - used);
            };
            this.getTotalIn = function () { return out === null ? 0 : used; };
            this.getTotalOut = function () { return pos; };
            this.getBytesRead = this.getTotalIn;
            this.getBytesWritten = this.getTotalOut;
            this.needsDictionary = function () { return false; };
            this.setDictionary = function () { call('unsupported', ['java.util.zip.Inflater.setDictionary']); };
            this.reset = clear;
            this.end = clear;
          }
          register('java.util.zip.Inflater', Inflater);

          // java.nio.ByteBuffer tối thiểu: chỉ để lấy mảng byte (`Uint8Array`, cùng dạng `byte[]` của bootstrap) qua
          // `allocate(n).array()` / `wrap(bytes).array()` (`wrap` dùng chung mảng khi đã là `Uint8Array`, như Java).
          function byteBuffer(backing) {
            return {
              array: function () { return backing; },
              hasArray: function () { return true; },
              capacity: function () { return backing.length; },
              limit: function () { return backing.length; }
            };
          }
          register('java.nio.ByteBuffer', {
            allocate: function (n) {
              var size = Number(n);
              if (!(size >= 0)) { throw new Error('java.lang.IllegalArgumentException: capacity < 0: (' + n + ')'); }
              return byteBuffer(new Uint8Array(Math.floor(size)));
            },
            wrap: function (bytes) {
              if (bytes === undefined || bytes === null) { throw nullPointer('mảng byte'); }
              return byteBuffer(bytes instanceof Uint8Array ? bytes : toBytes(bytes));
            }
          });

          // java.io: đọc ký tự. Cả luồng được giải bảng mã một lần (không cắt đôi ký tự nhiều byte), rồi đọc dần.
          function charsetName(cs) {
            if (cs === undefined || cs === null) { return 'UTF-8'; }
            if (typeof cs === 'string' || cs instanceof String) { return String(cs); }
            if (typeof cs.name === 'function') { try { return String(cs.name()); } catch (e) { return 'UTF-8'; } }
            return 'UTF-8';
          }
          function charReader(target, load) {
            var text = null, pos = 0;
            function all() { if (text === null) { text = String(load()); } return text; }
            target.read = function (cbuf, off, len) {
              var t = all();
              if (cbuf === undefined || cbuf === null) { return pos < t.length ? t.charCodeAt(pos++) : -1; }
              var start = intArg(off, 0), count = intArg(len, cbuf.length - start);
              if (count <= 0) { return 0; }
              if (pos >= t.length) { return -1; }
              var n = Math.min(count, t.length - pos), typed = ArrayBuffer.isView(cbuf);
              for (var i = 0; i < n; i++, pos++) { cbuf[start + i] = typed ? t.charCodeAt(pos) : t.charAt(pos); }
              return n;
            };
            target.ready = function () { return pos < all().length; };
            target.skip = function (n) { var k = Math.max(0, Math.min(Number(n) || 0, all().length - pos)); pos += k; return k; };
            target.close = function () {};
            L.defineHidden(target, '__lgRest', function () { var t = all(), rest = t.slice(pos); pos = t.length; return rest; });
            return {
              all: all,
              at: function () { return pos; },
              seek: function (p) { pos = p; }
            };
          }
          register('java.io.InputStreamReader', function (input, charset) {
            var cs = charsetName(charset);
            charReader(this, function () { return call('bytesToStr', [drain(input), cs]); });
            this.getEncoding = function () { return cs; };
          });
          register('java.io.BufferedReader', function (reader) {
            if (reader === undefined || reader === null) { throw nullPointer('Reader'); }
            var r = charReader(this, function () {
              if (typeof reader.__lgRest === 'function') { return reader.__lgRest(); }
              if (typeof reader.readAllBytes === 'function') { return call('bytesToStr', [drain(reader), 'UTF-8']); }
              var s = '', c;
              if (typeof reader.read === 'function') { while ((c = reader.read()) >= 0) { s += String.fromCharCode(c); } return s; }
              return String(reader);
            });
            // Dòng kết thúc bằng `\n`, `\r\n` hoặc `\r` (không gồm dấu xuống dòng); hết dữ liệu ⇒ `null`.
            this.readLine = function () {
              var t = r.all(), start = r.at(), i = start;
              if (start >= t.length) { return null; }
              while (i < t.length) { var ch = t.charCodeAt(i); if (ch === 10 || ch === 13) { break; } i++; }
              var line = t.slice(start, i);
              if (i < t.length) { i += t.charCodeAt(i) === 13 && t.charCodeAt(i + 1) === 10 ? 2 : 1; }
              r.seek(i);
              return line;
            };
          });

          // java.net.URL: thành phần theo RFC 3986 (phụ lục B) trên `href`; `getPath()` rỗng khi không có đường dẫn,
          // `getQuery()`/`getRef()` = null khi không có, như Java. Không mở kết nối.
          var URL_PARTS = /^([A-Za-z][A-Za-z0-9+.\-]*):(?:\/\/([^\/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#([\s\S]*))?$/;
          var URL_SCHEME = /^[A-Za-z][A-Za-z0-9+.\-]*:/;
          var KNOWN_PROTOCOLS = { http: 80, https: 443, ftp: 21, file: -1, jar: -1 };
          function malformed(message) { return new Error('java.net.MalformedURLException: ' + message); }
          function urlHref(args) {
            if (args.length >= 3) {
              var file = String(args.length >= 4 ? args[3] : args[2]), port = args.length >= 4 ? Number(args[2]) : -1;
              return String(args[0]) + '://' + String(args[1]) + (port >= 0 ? ':' + port : '') + file;
            }
            var spec = String(args.length >= 2 ? args[1] : args[0]).replace(/^[\u0000- ]+|[\u0000- ]+$/g, '');
            var context = args.length >= 2 && args[0] !== undefined && args[0] !== null ? String(args[0]) : null;
            if (URL_SCHEME.test(spec)) { return spec; }
            if (context === null || !URL_SCHEME.test(context)) { throw malformed('no protocol: ' + spec); }
            // Rỗng / chỉ `#ref` / chỉ `?query`: giữ nguyên phần trước của ngữ cảnh (kể cả đường dẫn rỗng), như Java.
            var noRef = context.replace(/#[\s\S]*$/, '');
            if (spec === '') { return noRef; }
            if (spec.charAt(0) === '#') { return noRef + spec; }
            if (spec.charAt(0) === '?') { return noRef.replace(/\?[\s\S]*$/, '') + spec; }
            return String((callJSON('toURL', [spec, context]) || {}).href || '');
          }
          function JavaURL() {
            var href = urlHref(arguments), m = URL_PARTS.exec(href);
            if (!m) { throw malformed('no protocol: ' + href); }
            var protocol = m[1].toLowerCase();
            if (!Object.prototype.hasOwnProperty.call(KNOWN_PROTOCOLS, protocol)) { throw malformed('unknown protocol: ' + protocol); }
            var authority = m[2] === undefined ? null : m[2], userInfo = null, host = '', port = -1;
            if (authority !== null) {
              var hostPort = authority, at = authority.lastIndexOf('@');
              if (at >= 0) { userInfo = authority.slice(0, at); hostPort = authority.slice(at + 1); }
              var colon = hostPort.lastIndexOf(':');
              if (colon >= 0 && hostPort.indexOf(']', colon) < 0) {
                var portText = hostPort.slice(colon + 1);
                host = hostPort.slice(0, colon);
                if (portText.length > 0) {
                  if (!/^[0-9]+$/.test(portText)) { throw malformed('Invalid port number: ' + portText); }
                  port = parseInt(portText, 10);
                }
              } else { host = hostPort; }
            }
            var path = m[3], query = m[4] === undefined ? null : m[4], ref = m[5] === undefined ? null : m[5];
            var file = path + (query === null ? '' : '?' + query);
            var external = protocol + ':' + (authority ? '//' + authority : '') + file + (ref === null ? '' : '#' + ref);
            this.getProtocol = function () { return protocol; };
            this.getHost = function () { return host; };
            this.getPort = function () { return port; };
            this.getDefaultPort = function () { return KNOWN_PROTOCOLS[protocol]; };
            this.getPath = function () { return path; };
            this.getQuery = function () { return query; };
            this.getRef = function () { return ref; };
            this.getFile = function () { return file; };
            this.getAuthority = function () { return authority; };
            this.getUserInfo = function () { return userInfo; };
            this.toString = function () { return external; };
            this.toExternalForm = this.toString;
            this.equals = function (o) { return o !== undefined && o !== null && String(o) === external; };
            ['openConnection', 'openStream', 'getContent', 'toURI'].forEach(function (name) {
              this[name] = function () { call('unsupported', ['java.net.URL.' + name]); };
            }, this);
            L.defineHidden(this, '__lgString', function () { return external; });
          }
          register('java.net.URL', JavaURL);
        })(this);
        """#
}
