---
name: vbook_helper
description: Support for developing, modifying, and debugging JavaScript-based VBook extensions and their integration in the FreeBook iOS app.
---

# VBook Extension Developer & Integrator Skill

Use this skill when you need to write new VBook JavaScript extensions, debug existing extensions, or modify the JS execution environment in the FreeBook app.

## Writing a VBook JavaScript Extension

Every VBook extension consists of:
1. `plugin.json` (Manifest file)
2. Standalone JS script files (`search.js`, `detail.js`, `toc.js`, `chap.js`, `genre.js`, `home.js`) located either in the root directory or inside `src/`.

### 1. Structure of `plugin.json`
```json
{
  "metadata": {
    "name": "My Extension",
    "author": "Author Name",
    "version": 1,
    "source": "https://mysource.com",
    "regexp": "^https?://mysource\\.com/book/\\d+$",
    "description": "Short description",
    "locale": "vi_VN",
    "type": "novel"
  },
  "script": {
    "home": "home.js",
    "genre": "genre.js",
    "detail": "detail.js",
    "toc": "toc.js",
    "chap": "chap.js",
    "search": "search.js"
  }
}
```

### 2. Implementing JS Scripts
Every script file MUST define a global function called `execute` as the main entry point:

#### `genre.js`
Returns a list of categories/genres wrapped in `Response.success(data)`. Each item must contain a `title`, an `input` (the query or page URL to pass to the script), and a `script` (the JS file to execute when this category is opened, such as `search.js` or a custom script):
```javascript
function execute() {
    return Response.success([
        { title: "Tiên Hiệp", input: "https://mysource.com/tien-hiep", script: "search.js" },
        { title: "Review", input: "/review?cat=5794f03dd7ced228f4419196", script: "review.js" }
    ]);
}
```

#### `home.js`
Similar to `genre.js`, it returns a list of default dashboard/home tabs (like "New Releases" or "Hot Updates") wrapped in `Response.success(data)`. Each item defines the designated script to run with the given input when accessing the tab:
```javascript
function execute() {
    return Response.success([
        { title: "Mới cập nhật", input: "/danh-sach/moi-cap-nhat", script: "homecontent.js" },
        { title: "Đọc nhiều nhất", input: "/danh-sach/doc-nhieu-nhat", script: "homecontent.js" }
    ]);
}
```

#### `search.js`
Returns a list of novel search results:
```javascript
function execute(keyword, page) {
    let url = "https://mysource.com/search?q=" + keyword + "&page=" + page;
    let res = fetch(url);
    if (res.ok) {
        let doc = res.html();
        let list = [];
        doc.select(".novel-item").forEach(function(el) {
            list.push({
                name: el.select(".title").text(),
                link: el.select(".title a").attr("href"),
                cover: el.select("img").attr("src"),
                author: el.select(".author").text()
            });
        });
        return Response.success(list);
    }
    return Response.error("Search failed");
}
```

#### `detail.js`
Returns metadata of a specific novel:
```javascript
function execute(url) {
    let res = fetch(url);
    if (res.ok) {
        let doc = res.html();
        return Response.success({
            name: doc.select(".title").text(),
            author: doc.select(".author").text(),
            cover: doc.select(".cover img").attr("src"),
            description: doc.select(".desc").text(),
            detail: url
        });
    }
    return null;
}
```

#### `toc.js`
Returns a list of chapters (Table of Contents):
```javascript
function execute(url) {
    let res = fetch(url);
    if (res.ok) {
        let doc = res.html();
        let list = [];
        doc.select(".chapter-list a").forEach(function(el) {
            list.push({
                name: el.text(),
                link: el.attr("href")
            });
        });
        return Response.success(list);
    }
    return Response.success([]);
}
```

#### `chap.js`
Returns the text content of a chapter:
```javascript
function execute(url) {
    let res = fetch(url);
    if (res.ok) {
        let doc = res.html();
        return Response.success(doc.select(".chapter-content").text());
    }
    return "";
}
```

### 3. Comic extensions (`metadata.type: "comic"`)
`chap.js` must return an **array** of image entries. Each entry is either a URL string or an object
`{ link, fallback: [url...], script: "image.js", width, height, referer, headers }`:
```javascript
function execute(url) {
    let doc = fetch(url).html();
    let imgs = [];
    doc.select(".page-chapter img").forEach(function(e) {
        imgs.push({ link: e.attr("data-src"), fallback: [e.attr("src")] });
    });
    return Response.success(imgs);
}
```
An image `script` receives `execute(link)` and returns **raw base64** (no `data:` prefix). It may use
`Graphics.createImage(b64)`, `Graphics.createCanvas(w, h)`, `canvas.drawImage(img, ...3|5|9 args)` and
`canvas.capture()`. In FreeBook, a `link` paired with a `script` is passed through verbatim.

### 4. Video extensions (`metadata.type: "video"`, script key `track` required)
Flow: `toc` (episodes) → `chap(episodeUrl)` (servers) → `track(data)` (playable source).
```javascript
// chap.js — list of servers; `data` is opaque and passed verbatim to track.js
function execute(url) {
    let doc = fetch(url).html();
    let servers = [];
    doc.select(".server a").forEach(function(e) {
        servers.push({ title: e.text(), data: e.attr("data-link") });
    });
    return Response.success(servers);
}
// track.js — type: "native" (m3u8/mp4 URL or #EXTM3U text), "auto" (page URL, app sniffs the media),
// "webview" (URL/HTML; app sniffs, otherwise embeds the page)
function execute(data) {
    return Response.success({
        type: "native",
        data: data,
        headers: { Referer: "https://mysource.com/" },
        timeSkip: [{ fromTime: 0, toTime: 90000 }],          // milliseconds
        subtitles: [{ data: "https://mysource.com/vi.vtt", type: "vtt", label: "Tiếng Việt", language: "vi" }]
    });
}
```
`browser.urls()` / `browser.waitUrl([regex], ms)` see every request of the page (XHR, fetch, media, iframes);
the regex must match the **whole** URL.

---

## Debugging JS Environment in FreeBook App

If an extension fails to load or execute, check the Xcode Console output. The app logs:
1. `🔍 [ExtensionManager] <action> called` with input parameters.
2. `💬 JS Console` logs from `console.log(...)` in JavaScript.
3. `❌ JSContext Exception` containing description, line number, column number, and stacktrace.
4. `📝 [ExtensionManager] <action> raw JS result` indicating exactly what the JS engine returned.
