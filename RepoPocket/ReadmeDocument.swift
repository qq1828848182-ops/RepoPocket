import Foundation

struct ReadmeDocument {
    let entry: Entry
    let source: String?
    let html: String?
}

enum ReadmeDocumentRules {
    static let sourceByteLimit = 1024 * 1024
    static let htmlByteLimit = 2 * 1024 * 1024
    static let collapsedHeight: CGFloat = 360
    static let inlineHeightLimit: CGFloat = 12_000
    // Fixed app-owned code runs in an isolated content world; README scripts stay disabled.
    static let heightObserver = """
    (() => {
      const article = document.getElementById('repopocket-readme');
      if (!article) return;
      const publish = () => window.webkit.messageHandlers.readmeSize.postMessage(article.getBoundingClientRect().height);
      new ResizeObserver(publish).observe(article);
      publish();
    })();
    """

    static func source(_ entry: Entry) throws -> String {
        guard (entry.size ?? 0) <= sourceByteLimit, entry.encoding == "base64",
              let content = entry.content, let bytes = Data(base64Encoded: content, options: .ignoreUnknownCharacters),
              bytes.count <= sourceByteLimit else { throw AppError(text: "自述文件原文不可用或超过 1 MiB。") }
        let signature = Array(bytes.prefix(4))
        let encoding: String.Encoding
        if signature.starts(with: [0xff, 0xfe, 0, 0]) { encoding = .utf32LittleEndian }
        else if signature.starts(with: [0, 0, 0xfe, 0xff]) { encoding = .utf32BigEndian }
        else if signature.starts(with: [0xff, 0xfe]) { encoding = .utf16LittleEndian }
        else if signature.starts(with: [0xfe, 0xff]) { encoding = .utf16BigEndian }
        else { encoding = .utf8 }
        guard let decoded = String(data: bytes, encoding: encoding), !decoded.contains("\0") else {
            throw AppError(text: "此自述文件不是可解码文本；仍会尝试 GitHub 排版。")
        }
        return decoded.hasPrefix("\u{feff}") ? String(decoded.dropFirst()) : decoded
    }

    static func renderedHTML(_ bytes: Data) throws -> String {
        guard bytes.count <= htmlByteLimit, let html = String(data: bytes, encoding: .utf8), !html.contains("\0") else {
            throw AppError(text: "自述文件排版结果过大或无效。")
        }
        return html
    }

    static func isLocalAnchor(_ url: URL, base: URL?) -> Bool {
        guard url.fragment != nil, let base,
              var target = URLComponents(url: url, resolvingAgainstBaseURL: true),
              var origin = URLComponents(url: base, resolvingAgainstBaseURL: true) else { return false }
        target.fragment = nil; origin.fragment = nil
        return target.url == origin.url
    }

    static func document(_ fragment: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: data:; style-src 'unsafe-inline'; script-src 'none'; frame-src 'none'; connect-src 'none'; base-uri 'none'; form-action 'none'">
        <style>
        :root { color-scheme: light dark; } * { box-sizing: border-box; }
        html, body { margin: 0; padding: 0; background: transparent; }
        #repopocket-readme { display: flow-root; }
        body { font: -apple-system-body; font-size: 17px; line-height: 1.5; overflow-wrap: anywhere; color: #1f2328; }
        h1 { font-size: 1.85em; } h2 { font-size: 1.45em; } h3 { font-size: 1.2em; }
        h1, h2 { border-bottom: 1px solid #d1d9e0; padding-bottom: .25em; }
        p, ul, ol, pre, blockquote, table { margin: 0 0 1em; } ul, ol { padding-left: 1.6em; }
        a { color: #0969da; text-decoration: none; } .anchor { display: none; }
        img, svg, video { max-width: 100%; height: auto; } img { vertical-align: middle; }
        pre { overflow: auto; padding: 12px; background: #f6f8fa; border-radius: 8px; }
        code, pre { font-family: ui-monospace, Menlo, monospace; font-size: .88em; }
        table { display: block; overflow: auto; border-collapse: collapse; max-width: 100%; }
        td, th { padding: 6px 12px; border: 1px solid #d1d9e0; }
        blockquote { border-left: 3px solid #d1d9e0; padding-left: 1em; color: #59636e; }
        summary { cursor: pointer; } hr { border: 0; border-top: 1px solid #d1d9e0; }
        @media (prefers-color-scheme: dark) {
          body { color: #f0f3f6; } a { color: #58a6ff; } pre { background: #161b22; }
          td, th, h1, h2, blockquote, hr { border-color: #3d444d; } blockquote { color: #9198a1; }
        }
        </style></head><body><main id="repopocket-readme">\(fragment)</main></body></html>
        """
    }
}

extension GitHub {
    func repositoryReadmeDocument(_ repo: String, branch: String) async throws -> ReadmeDocument {
        let entry = try await repositoryReadme(repo, branch: branch)
        guard (entry.size ?? 0) <= ReadmeDocumentRules.sourceByteLimit else { throw AppError(text: "自述文件超过 1 MiB，无法在此预览。") }
        let source = try? ReadmeDocumentRules.source(entry)
        do {
            let html = try await communityReadmeHTML(repo, branch: branch)
            return ReadmeDocument(entry: entry, source: source, html: html)
        } catch {
            try Task.checkCancellation()
            guard isCurrentSession, !RefreshFailure.isCancellation(error) else { throw CancellationError() }
            guard source != nil else { throw error }
            return ReadmeDocument(entry: entry, source: source, html: nil)
        }
    }
}
