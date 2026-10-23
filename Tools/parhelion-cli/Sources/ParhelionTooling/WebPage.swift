/// The web preview's page: the screen inside the phone, scaled to fit the
/// browser window, with the app's status above it.
///
/// It is Swift source rather than a file, because Parhelion ships no
/// SwiftPM resources (docs/adr/0003-no-swiftpm-resources.md). The page
/// opens a WebSocket at `/socket`, draws the frames it receives into a
/// canvas, acknowledges each one, and sends pointer, wheel, and keyboard
/// input back as JSON.
enum WebPage {
    /// The page runs only its own inline script and style, and connects only
    /// to its own server.
    static let contentSecurityPolicy =
        "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; "
        + "img-src 'self' data:; connect-src 'self' ws: wss:; worker-src blob:; base-uri 'none'; "
        + "form-action 'none'; frame-ancestors 'none'"

    static let html = #"""
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport"
          content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no,
          viewport-fit=cover">
        <meta name="color-scheme" content="dark">
        <link rel="icon" href="data:,">
        <title>Parhelion</title>
        <style>
          :root {
            --background: #1c1c1e; --bar: #2c2c2e; --text: #f2f2f7; --secondary: #8e8e93;
            --green: #30d158; --orange: #ff9f0a; --red: #ff453a;
          }
          * { box-sizing: border-box; }
          html, body {
            margin: 0; height: 100%; overflow: hidden; background: var(--background);
            color: var(--text); font: 13px/1.4 -apple-system, system-ui, sans-serif;
            -webkit-user-select: none; user-select: none; -webkit-tap-highlight-color: transparent;
          }
          body { display: flex; flex-direction: column; }
          #bar {
            display: flex; align-items: center; gap: 12px; padding: 8px 16px;
            padding-top: max(8px, env(safe-area-inset-top)); background: var(--bar);
          }
          #title { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis;
            white-space: nowrap; font-weight: 600; }
          #title span { color: var(--secondary); font-weight: 400; }
          #state { display: flex; align-items: center; gap: 6px; color: var(--secondary);
            white-space: nowrap; }
          #state::before { content: ""; width: 8px; height: 8px; border-radius: 50%;
            background: var(--state, var(--secondary)); }
          #stats { color: var(--secondary); font-variant-numeric: tabular-nums;
            white-space: nowrap; }
          #keyboard { display: none; border: 0; border-radius: 6px; padding: 4px 10px;
            background: #3a3a3c; color: var(--text); font: inherit; }
          @media (pointer: coarse) { #keyboard { display: block; } }
          #stage { flex: 1; position: relative; display: flex; align-items: center;
            justify-content: center; min-height: 0; }
          #phone { position: relative; }
          #screen { position: absolute; display: block; background: #000; touch-action: none; }
          #bezel { position: absolute; inset: 0; width: 100%; height: 100%;
            pointer-events: none; }
          #notice { position: absolute; top: 12px; left: 50%; transform: translateX(-50%);
            padding: 6px 14px; border-radius: 999px; background: rgba(44, 44, 46, 0.92);
            white-space: nowrap; display: none; }
          #errors { position: absolute; left: 16px; right: 16px; bottom: 16px; max-height: 45%;
            display: none; flex-direction: column; border-radius: 12px;
            background: rgba(28, 28, 30, 0.96); border: 1px solid #48484a; }
          #errors header { display: flex; align-items: center; padding: 8px 12px;
            color: var(--red); font-weight: 600; }
          #errors header span { flex: 1; }
          #errors button { border: 0; background: none; color: var(--secondary); font: inherit; }
          #errors pre { margin: 0; padding: 0 12px 12px; overflow: auto; font: 12px/1.45
            ui-monospace, SFMono-Regular, Menlo, monospace; white-space: pre-wrap;
            -webkit-user-select: text; user-select: text; }
          #keys { position: fixed; left: 0; bottom: 0; width: 1px; height: 1px; opacity: 0;
            border: 0; padding: 0; resize: none; font-size: 16px; }
        </style>
        </head>
        <body>
        <div id="bar">
          <div id="title">Parhelion</div>
          <div id="stats" hidden></div>
          <div id="state">Connecting</div>
          <button id="keyboard" type="button">Keyboard</button>
        </div>
        <div id="stage">
          <div id="phone">
            <canvas id="screen" width="1" height="1"></canvas>
            <img id="bezel" alt="" hidden>
          </div>
          <div id="notice"></div>
          <div id="errors">
            <header><span>Build failed</span><button id="dismiss" type="button">Hide</button>
            </header>
            <pre id="errorText"></pre>
          </div>
        </div>
        <textarea id="keys" autocapitalize="off" autocomplete="off" autocorrect="off"
          spellcheck="false" aria-label="Keyboard input"></textarea>
        <script>
        "use strict";
        const token = new URLSearchParams(location.search).get("token") || "";
        const $ = (id) => document.getElementById(id);
        const canvas = $("screen");
        const context = canvas.getContext("2d");
        const keys = $("keys");
        const touchDevice = matchMedia("(pointer: coarse)").matches;
        let socket = null;
        let hello = null;
        let retryDelay = 250;
        let chain = Promise.resolve();

        // Measurements, for the stats line (?stats) and for scripts.
        const stats = { connections: 0, frames: 0, bytes: 0, latency: 0, fps: 0,
          bytesPerFrame: 0, latencyMilliseconds: 0 };
        // The most recent frames: when each was drawn, its size, and the time from its
        // arrival until it was drawn.
        const recent = [];
        window.parhelion = { stats, recent };
        const statsLine = $("stats");
        statsLine.hidden = !new URLSearchParams(location.search).has("stats");
        let last = { time: performance.now(), frames: 0, bytes: 0, latency: 0 };
        setInterval(() => {
          const now = performance.now();
          const frames = stats.frames - last.frames;
          stats.fps = frames * 1000 / (now - last.time);
          stats.bytesPerFrame = frames ? (stats.bytes - last.bytes) / frames : 0;
          stats.latencyMilliseconds = frames ? (stats.latency - last.latency) / frames : 0;
          last = { time: now, frames: stats.frames, bytes: stats.bytes, latency: stats.latency };
          statsLine.textContent = `${stats.fps.toFixed(0)} fps · ` +
            `${(stats.bytesPerFrame / 1024).toFixed(1)} KB/frame · ` +
            `${stats.latencyMilliseconds.toFixed(1)} ms to draw`;
        }, 1000);

        function setState(text, color) {
          $("state").textContent = text;
          $("state").style.setProperty("--state", color);
        }

        function setNotice(text) {
          $("notice").textContent = text;
          $("notice").style.display = text ? "block" : "none";
        }

        function connect() {
          const scheme = location.protocol === "https:" ? "wss" : "ws";
          socket = new WebSocket(
            `${scheme}://${location.host}/socket?token=${encodeURIComponent(token)}`);
          socket.binaryType = "arraybuffer";
          socket.onopen = () => {
            stats.connections += 1;
            retryDelay = 250;
            setState("Connected", "var(--green)");
          };
          socket.onmessage = (event) => {
            if (typeof event.data === "string") {
              receive(JSON.parse(event.data));
            } else {
              // Decompress at once, while earlier frames draw; draw in order.
              const frame = decodeFrame(event.data);
              chain = chain.then(() => frame).then(drawFrame).catch((error) => console.error(error));
            }
          };
          socket.onclose = () => {
            setState("Reconnecting", "var(--orange)");
            setTimeout(connect, retryDelay);
            retryDelay = Math.min(retryDelay * 2, 4000);
          };
        }

        function send(message) {
          if (socket && socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(message));
        }

        function receive(message) {
          if (message.type === "hello") {
            hello = message;
            const device = hello.deviceName ? ` <span>${escapeHTML(hello.deviceName)}</span>` : "";
            $("title").innerHTML = escapeHTML(hello.appName) + device;
            document.title = [hello.appName, hello.deviceName, "Parhelion"].filter(Boolean)
              .join(" — ");
            const bezel = $("bezel");
            bezel.hidden = !hello.bezel;
            if (hello.bezel) {
              bezel.src = `bezel.png?token=${encodeURIComponent(token)}&v=${hello.revision}`;
            }
            layout();
          } else if (message.type === "status") {
            const failed = message.state === "buildFailed";
            $("errors").style.display = failed ? "flex" : "none";
            $("errorText").textContent = failed ? message.message : "";
            setNotice({ building: "Building…", stopped: message.message }[message.state] || "");
          }
        }

        function escapeHTML(text) {
          const element = document.createElement("span");
          element.textContent = text;
          return element.innerHTML;
        }

        // Fits the phone, or the screen without one, into the space below the bar.
        function layout() {
          if (!hello) return;
          const bezel = hello.bezel;
          const width = bezel ? bezel.width : hello.screenWidth;
          const height = bezel ? bezel.height : hello.screenHeight;
          const stage = $("stage").getBoundingClientRect();
          const scale = Math.min((stage.width - 24) / width, (stage.height - 24) / height);
          const phone = $("phone");
          phone.style.width = `${width * scale}px`;
          phone.style.height = `${height * scale}px`;
          const margin = bezel ? bezel.margin * scale : 0;
          canvas.style.left = canvas.style.top = `${margin}px`;
          canvas.style.width = `${hello.screenWidth * scale}px`;
          canvas.style.height = `${hello.screenHeight * scale}px`;
          canvas.style.borderRadius = `${hello.cornerRadius * scale}px`;
        }
        addEventListener("resize", layout);

        // Workers decompress compressed parts in parallel, off the thread that handles
        // input. Without workers, the page decompresses them itself.
        const inflateSource = `onmessage = async (event) => {
          const stream = new Blob([event.data.bytes]).stream()
            .pipeThrough(new DecompressionStream("deflate"));
          const pixels = new Uint8Array(await new Response(stream).arrayBuffer());
          postMessage({ id: event.data.id, pixels }, [pixels.buffer]);
        };`;
        const decoders = [];
        const pending = new Map();
        let nextJob = 0;
        try {
          const url = URL.createObjectURL(new Blob([inflateSource], { type: "text/javascript" }));
          for (let index = 0; index < Math.min(navigator.hardwareConcurrency || 2, 4); index++) {
            const worker = new Worker(url);
            worker.onmessage = (event) => {
              pending.get(event.data.id)(event.data.pixels);
              pending.delete(event.data.id);
            };
            decoders.push(worker);
          }
        } catch (error) {
          decoders.length = 0;
        }

        async function inflate(bytes) {
          if (decoders.length) {
            return new Promise((resolve) => {
              const id = nextJob++;
              pending.set(id, resolve);
              const copy = bytes.slice();
              decoders[id % decoders.length].postMessage({ id, bytes: copy }, [copy.buffer]);
            });
          }
          const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate"));
          return new Uint8Array(await new Response(stream).arrayBuffer());
        }

        // A frame message: a header, then parts that each change a rectangle, in order.
        // A part is pixels (raw or compressed), or a copy from elsewhere in the canvas.
        async function decodeFrame(buffer) {
          const start = performance.now();
          const view = new DataView(buffer);
          if (view.getUint8(0) !== 1) return null;
          const sequence = view.getUint32(2);
          const width = view.getUint16(6);
          const height = view.getUint16(8);
          const count = view.getUint16(10);
          const parts = [];
          let offset = 12;
          for (let index = 0; index < count; index++) {
            const part = { encoding: view.getUint8(offset), x: view.getUint16(offset + 1),
              y: view.getUint16(offset + 3), w: view.getUint16(offset + 5),
              h: view.getUint16(offset + 7) };
            if (part.encoding === 2) {
              part.fromX = view.getUint16(offset + 9);
              part.fromY = view.getUint16(offset + 11);
              offset += 13;
            } else {
              const length = view.getUint32(offset + 9);
              offset += 13;
              part.bytes = new Uint8Array(buffer, offset, length);
              offset += length;
            }
            parts.push(part);
          }
          await Promise.all(parts.filter((part) => part.encoding === 1).map(async (part) => {
            part.bytes = await inflate(part.bytes);
          }));
          return { start, size: buffer.byteLength, sequence, width, height, parts };
        }

        function drawFrame(frame) {
          if (!frame) return;
          const { start, size, sequence, width, height, parts } = frame;
          if (canvas.width !== width || canvas.height !== height) {
            canvas.width = width;
            canvas.height = height;
          }
          for (const part of parts) {
            if (part.encoding === 2) {
              // Replace the pixels exactly, alpha included, and only inside the rectangle.
              context.save();
              context.beginPath();
              context.rect(part.x, part.y, part.w, part.h);
              context.clip();
              context.globalCompositeOperation = "copy";
              context.drawImage(canvas, part.fromX, part.fromY, part.w, part.h,
                part.x, part.y, part.w, part.h);
              context.restore();
            } else {
              const pixels = new Uint8ClampedArray(part.bytes.buffer, part.bytes.byteOffset,
                part.w * part.h * 4);
              context.putImageData(new ImageData(pixels, part.w, part.h), part.x, part.y);
            }
          }
          const end = performance.now();
          stats.frames += 1;
          stats.bytes += size;
          stats.latency += end - start;
          recent.push({ time: end, bytes: size, latency: end - start });
          if (recent.length > 1000) recent.shift();
          send({ type: "ack", sequence });
        }

        // Positions in the screen's points.
        function point(event) {
          const rect = canvas.getBoundingClientRect();
          return {
            x: (event.clientX - rect.left) * hello.screenWidth / rect.width,
            y: (event.clientY - rect.top) * hello.screenHeight / rect.height,
          };
        }

        let activePointer = null;
        canvas.addEventListener("pointerdown", (event) => {
          if (!hello || activePointer !== null || event.button !== 0) return;
          event.preventDefault();
          activePointer = event.pointerId;
          canvas.setPointerCapture(event.pointerId);
          if (!touchDevice) keys.focus({ preventScroll: true });
          send({ type: "down", ...point(event) });
        });
        canvas.addEventListener("pointermove", (event) => {
          if (event.pointerId === activePointer) send({ type: "move", ...point(event) });
        });
        for (const type of ["pointerup", "pointercancel"]) {
          canvas.addEventListener(type, (event) => {
            if (event.pointerId !== activePointer) return;
            activePointer = null;
            send({ type: "up", ...point(event) });
          });
        }
        canvas.addEventListener("contextmenu", (event) => event.preventDefault());

        // Wheel and trackpad scrolling. Pixel deltas move the content as far as the
        // pointer would move across the scaled screen; a line is 40 points, as in the
        // window.
        canvas.addEventListener("wheel", (event) => {
          event.preventDefault();
          if (!hello) return;
          const rect = canvas.getBoundingClientRect();
          let factor = hello.screenWidth / rect.width;
          if (event.deltaMode === 1) factor = 40;
          if (event.deltaMode === 2) factor = hello.screenHeight;
          send({ type: "scroll", dx: event.deltaX * factor, dy: event.deltaY * factor,
            ...point(event) });
        }, { passive: false });

        // Keyboard input goes through a hidden text area, so keyboard layouts, input
        // methods, and phone keyboards work. Editing keys are sent by name.
        const keyNames = { Backspace: "backspace", Delete: "delete", ArrowLeft: "left",
          ArrowRight: "right", Home: "home", End: "end", Tab: "tab", Enter: "return",
          Escape: "escape" };
        keys.addEventListener("keydown", (event) => {
          let name = keyNames[event.key];
          if (!name || event.isComposing || event.metaKey || event.ctrlKey || event.altKey) return;
          if (name === "tab" && event.shiftKey) name = "backTab";
          event.preventDefault();
          send({ type: "key", key: name });
        });
        function sendTyped() {
          const text = keys.value;
          keys.value = "";
          if (text) send({ type: "text", text });
        }
        keys.addEventListener("input", (event) => { if (!event.isComposing) sendTyped(); });
        keys.addEventListener("compositionend", sendTyped);
        if (!touchDevice) {
          // Typing anywhere on the page goes to the app.
          document.addEventListener("keydown", () => {
            if (document.activeElement !== keys && !getSelection().toString()) {
              keys.focus({ preventScroll: true });
            }
          }, true);
          keys.focus({ preventScroll: true });
        }
        $("keyboard").addEventListener("click", () => {
          if (document.activeElement === keys) keys.blur(); else keys.focus();
        });
        $("dismiss").addEventListener("click", () => { $("errors").style.display = "none"; });

        connect();
        </script>
        </body>
        </html>
        """#
}
