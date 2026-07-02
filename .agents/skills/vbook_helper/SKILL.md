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

---

## Debugging JS Environment in FreeBook App

If an extension fails to load or execute, check the Xcode Console output. The app logs:
1. `🔍 [ExtensionManager] <action> called` with input parameters.
2. `💬 JS Console` logs from `console.log(...)` in JavaScript.
3. `❌ JSContext Exception` containing description, line number, column number, and stacktrace.
4. `📝 [ExtensionManager] <action> raw JS result` indicating exactly what the JS engine returned.
