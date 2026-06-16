//
//  MermaidFullscreenOverlayController.swift
//  md-preview
//

import Cocoa
import WebKit

/// Window-level fullscreen overlay for native Mermaid SVG diagrams.
/// Covers the document area while keeping the host window header visible.
/// Controls sit at the bottom to avoid fighting macOS titlebar hit testing.
final class MermaidFullscreenOverlayController: NSViewController {

    private var backdrop: NSView!
    private var toolbarView: NSView!
    private var hintLabel: NSTextField!
    private var levelLabel: NSTextField!
    private var closeButton: NSButton!
    private var webView: WKWebView!
    private var webViewTopConstraint: NSLayoutConstraint!
    private let overlayBridge = OverlayBridge()
    private var escapeMonitor: Any?
    private weak var hostWindow: NSWindow?
    private var isPresented = false

    private static let panelBackground = NSColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1)
    private static let toolbarBackground = NSColor(red: 0.09, green: 0.11, blue: 0.13, alpha: 1)

    override func loadView() {
        let root = MermaidOverlayRootView()
        root.wantsLayer = true
        root.layer?.backgroundColor = Self.panelBackground.cgColor

        backdrop = NSView()
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = Self.panelBackground.cgColor
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(backdrop)

        let config = WKWebViewConfiguration()
        overlayBridge.owner = self
        config.userContentController.add(overlayBridge, name: OverlayBridge.name)
        webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(webView)

        toolbarView = NSView()
        toolbarView.wantsLayer = true
        toolbarView.layer?.backgroundColor = Self.toolbarBackground.cgColor
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(toolbarView)

        hintLabel = NSTextField(labelWithString: "滚轮缩放 · 拖拽平移 · 双击适配 · Esc 关闭")
        hintLabel.font = .systemFont(ofSize: 13, weight: .regular)
        hintLabel.textColor = NSColor(white: 0.78, alpha: 1)
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.addSubview(hintLabel)

        levelLabel = NSTextField(labelWithString: "100%")
        levelLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        levelLabel.textColor = NSColor(white: 0.92, alpha: 1)
        levelLabel.alignment = .center
        levelLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.addSubview(levelLabel)

        closeButton = NSButton(title: "  关闭  ", target: self, action: #selector(closePressed(_:)))
        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .regular
        closeButton.font = .systemFont(ofSize: 13, weight: .semibold)
        closeButton.contentTintColor = .white
        closeButton.toolTip = "关闭 (Esc)"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor(white: 1, alpha: 0.16).cgColor
        closeButton.layer?.cornerRadius = 6
        closeButton.layer?.masksToBounds = true
        toolbarView.addSubview(closeButton)

        let toolbarSeparator = NSBox()
        toolbarSeparator.boxType = .separator
        toolbarSeparator.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.addSubview(toolbarSeparator)

        webViewTopConstraint = webView.topAnchor.constraint(equalTo: root.topAnchor)

        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: root.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            toolbarView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            toolbarView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: 48),

            toolbarSeparator.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor),
            toolbarSeparator.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor),
            toolbarSeparator.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            toolbarSeparator.heightAnchor.constraint(equalToConstant: 1),

            hintLabel.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor, constant: 20),
            hintLabel.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: levelLabel.leadingAnchor, constant: -16),

            levelLabel.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            levelLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -16),
            levelLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),

            closeButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor, constant: -20),
            closeButton.heightAnchor.constraint(equalToConstant: 28),
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),

            webViewTopConstraint,
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: toolbarView.topAnchor),
        ])

        view = root
    }

    func present(svg: String, in window: NSWindow) {
        if isPresented {
            dismiss()
        }

        hostWindow = window
        guard let contentView = window.contentView else { return }

        let overlayView = view
        overlayView.frame = overlayFrame(in: window, contentView: contentView)
        overlayView.autoresizingMask = [.width, .height]
        let topInset = overlayTopPassthroughInset(in: contentView)
        (overlayView as? MermaidOverlayRootView)?.passthroughTopInset = topInset
        webViewTopConstraint.constant = topInset
        contentView.addSubview(overlayView, positioned: .above, relativeTo: nil)
        isPresented = true

        levelLabel.stringValue = "100%"
        webView.navigationDelegate = self
        webView.loadHTMLString(Self.overlayHTML(svg: svg), baseURL: nil)

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isPresented else { return event }
            if event.keyCode == 53 {
                self.dismiss()
                return nil
            }
            return event
        }
    }

    func dismiss() {
        guard isPresented else { return }
        isPresented = false

        escapeMonitor.map { NSEvent.removeMonitor($0) }
        escapeMonitor = nil
        webView.navigationDelegate = nil

        view.removeFromSuperview()
        hostWindow = nil
    }

    /// Cover the whole content view, including the full-size titlebar area. A
    /// passthrough strip keeps native window controls clickable.
    private func overlayFrame(in window: NSWindow, contentView: NSView) -> NSRect {
        contentView.bounds
    }

    private func overlayTopPassthroughInset(in contentView: NSView) -> CGFloat {
        if #available(macOS 11.0, *) {
            return contentView.safeAreaInsets.top
        }
        return 0
    }

    @objc private func closePressed(_ sender: Any?) {
        dismiss()
    }

    fileprivate func overlayDidReportZoom(_ percent: Int) {
        levelLabel.stringValue = "\(percent)%"
    }

    private static func overlayHTML(svg: String) -> String {
        let payload = javaScriptStringLiteral(svg)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        html, body {
            width: 100%;
            height: 100%;
            overflow: hidden;
            background: #0d1117;
        }
        .stage {
            position: absolute;
            inset: 0;
            overflow: hidden;
            cursor: grab;
            touch-action: none;
            background: #0d1117;
        }
        .stage:active { cursor: grabbing; }
        .canvas {
            position: absolute;
            top: 0;
            left: 0;
        }
        .canvas svg {
            display: block;
            background: transparent;
            shape-rendering: geometricPrecision;
        }
        </style>
        </head>
        <body>
        <div class="stage" id="stage">
          <div class="canvas" id="canvas"></div>
        </div>
        <script>
        (() => {
            const post = (() => {
                try {
                    const h = window.webkit && window.webkit.messageHandlers
                        && window.webkit.messageHandlers.\(OverlayBridge.name);
                    if (!h) return () => false;
                    return (msg) => { h.postMessage(msg); return true; };
                } catch (e) { return () => false; }
            })();

            const canvas = document.getElementById('canvas');
            canvas.innerHTML = \(payload);
            const svg = canvas.querySelector('svg');
            if (!svg) return;

            svg.removeAttribute('width');
            svg.removeAttribute('height');
            svg.style.maxWidth = 'none';
            svg.style.maxHeight = 'none';

            function contentSize() {
                const vb = svg.viewBox && svg.viewBox.baseVal;
                if (vb && vb.width > 0 && vb.height > 0) {
                    return { w: vb.width, h: vb.height };
                }
                try {
                    const box = svg.getBBox();
                    if (box.width > 0 && box.height > 0) {
                        return { w: box.width, h: box.height };
                    }
                } catch (e) {}
                const rect = svg.getBoundingClientRect();
                return { w: Math.max(rect.width, 1), h: Math.max(rect.height, 1) };
            }

            const base = contentSize();
            const stage = document.getElementById('stage');
            const state = {
                tx: 0, ty: 0, scale: 1, min: 0.15, max: 12,
                dragging: false, lastX: 0, lastY: 0
            };

            function layoutSVG() {
                const w = base.w * state.scale;
                const h = base.h * state.scale;
                svg.setAttribute('width', String(w));
                svg.setAttribute('height', String(h));
                svg.style.width = w + 'px';
                svg.style.height = h + 'px';
                canvas.style.transform = 'translate(' + state.tx + 'px,' + state.ty + 'px)';
            }

            function apply() {
                layoutSVG();
                post({ kind: 'zoom', value: Math.round(state.scale * 100) });
            }

            function fit() {
                const pad = 32;
                const sw = Math.max(stage.clientWidth - pad, 1);
                const sh = Math.max(stage.clientHeight - pad, 1);
                const fitScale = Math.min(sw / base.w, sh / base.h, 1);
                state.scale = fitScale;
                state.min = Math.min(fitScale * 0.5, 0.15);
                const w = base.w * fitScale;
                const h = base.h * fitScale;
                state.tx = (stage.clientWidth - w) / 2;
                state.ty = (stage.clientHeight - h) / 2;
                apply();
            }

            function zoomAt(x, y, factor) {
                const next = Math.max(state.min, Math.min(state.max, state.scale * factor));
                if (next === state.scale) return;
                const ratio = next / state.scale;
                state.tx = x - (x - state.tx) * ratio;
                state.ty = y - (y - state.ty) * ratio;
                state.scale = next;
                apply();
            }

            stage.addEventListener('wheel', (event) => {
                event.preventDefault();
                const rect = stage.getBoundingClientRect();
                const k = Math.exp(-event.deltaY * 0.01);
                zoomAt(event.clientX - rect.left, event.clientY - rect.top, k);
            }, { passive: false });

            stage.addEventListener('pointerdown', (event) => {
                if (event.button !== 0) return;
                stage.setPointerCapture(event.pointerId);
                state.dragging = true;
                state.lastX = event.clientX;
                state.lastY = event.clientY;
            });

            stage.addEventListener('pointermove', (event) => {
                if (!state.dragging) return;
                state.tx += event.clientX - state.lastX;
                state.ty += event.clientY - state.lastY;
                state.lastX = event.clientX;
                state.lastY = event.clientY;
                apply();
            });

            const endDrag = (event) => {
                if (!state.dragging) return;
                state.dragging = false;
                try { stage.releasePointerCapture(event.pointerId); } catch (e) {}
            };
            stage.addEventListener('pointerup', endDrag);
            stage.addEventListener('pointercancel', endDrag);

            stage.addEventListener('dblclick', () => fit());

            requestAnimationFrame(() => requestAnimationFrame(fit));
            window.addEventListener('resize', fit);
        })();
        </script>
        </body>
        </html>
        """
    }

    private static func javaScriptStringLiteral(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2 else { return "\"\"" }
        return String(json.dropFirst().dropLast())
    }
}

extension MermaidFullscreenOverlayController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        for scrollView in webView.descendantScrollViews {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.verticalScrollElasticity = .none
            scrollView.horizontalScrollElasticity = .none
            scrollView.drawsBackground = true
            scrollView.backgroundColor = Self.panelBackground
        }
        webView.setValue(false, forKey: "drawsBackground")
    }
}

private final class MermaidOverlayRootView: NSView {
    var passthroughTopInset: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        if passthroughTopInset > 0,
           point.y >= bounds.maxY - passthroughTopInset {
            return nil
        }
        return super.hitTest(point)
    }
}

private extension NSView {
    var descendantScrollViews: [NSScrollView] {
        subviews.flatMap { view -> [NSScrollView] in
            let nested = view.descendantScrollViews
            if let scrollView = view as? NSScrollView {
                return [scrollView] + nested
            }
            return nested
        }
    }
}

private final class OverlayBridge: NSObject, WKScriptMessageHandler {
    static let name = "mdMermaidOverlay"
    weak var owner: MermaidFullscreenOverlayController?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == Self.name,
              let dict = message.body as? [String: Any],
              dict["kind"] as? String == "zoom",
              let value = dict["value"] as? Int else { return }
        owner?.overlayDidReportZoom(value)
    }
}
