import * as ConcurrentTask from "@andrewmacmurray/elm-concurrent-task";
import { createTasks as createWebCryptoTasks } from "../vendor/elm-webcrypto/js/src/index.js";
import { createTasks as createIndexedDbTasks } from "../vendor/elm-indexeddb/js/src/index.js";
import { createTasks as createPocketBaseTasks } from "../vendor/elm-pocketbase/js/src/index.js";
import { init as initPwa } from "../vendor/elm-pwa/js/src/index.js";

// Copy-to-clipboard custom element
class CopyButton extends HTMLElement {
  connectedCallback() {
    this.addEventListener("click", () => {
      const text = this.getAttribute("data-copy") || "";
      navigator.clipboard.writeText(text).then(() => {
        if (app && app.ports && app.ports.onClipboardCopy) {
          app.ports.onClipboardCopy.send(null);
        }
      });
    });
  }
}
customElements.define("copy-button", CopyButton);

// Web Share API custom element (hidden when unsupported)
class ShareButton extends HTMLElement {
  connectedCallback() {
    if (!navigator.share) {
      this.style.display = "none";
      return;
    }
    this.addEventListener("click", () => {
      navigator
        .share({
          title: this.getAttribute("data-share-title") || "",
          text: this.getAttribute("data-share-text") || "",
          url: this.getAttribute("data-share-url") || "",
        })
        .catch(() => {});
    });
  }
}
customElements.define("share-button", ShareButton);

// elm-url-navigation-port JS companion
function initNavigation(ports) {
  function sendNavigation(state) {
    ports.onNavEvent.send({ href: location.href, state: state });
  }

  ports.navCmd.subscribe(function (msg) {
    switch (msg.tag) {
      case "pushUrl":
        history.pushState(null, "", msg.url);
        sendNavigation(null);
        break;
      case "pushState":
        history.pushState(msg.state, "", msg.url);
        sendNavigation(msg.state);
        break;
      case "replaceUrl":
        history.replaceState(history.state, "", msg.url);
        break;
      case "go":
        history.go(msg.steps);
        break;
    }
  });

  window.addEventListener("popstate", function (event) {
    sendNavigation(event.state);
  });
}

var app = Elm.Main.init({
  node: document.getElementById("app"),
  flags: {
    initialUrl: location.href,
    language: navigator.language || "en",
    randomSeed: Array.from(crypto.getRandomValues(new Uint32Array(4))),
    currentTime: Date.now(),
    serverUrl: "http://127.0.0.1:8090",
    origin: location.origin,
    isOnline: navigator.onLine,
  },
});

initNavigation({
  navCmd: app.ports.navCmd,
  onNavEvent: app.ports.onNavEvent,
});

var pbTasks = createPocketBaseTasks();
pbTasks.setEventCallback(function (event) {
  app.ports.onPocketbaseEvent.send(event);
});

function createUsageStatsTasks() {
  return {
    "usageStats:estimateStorage": () => {
      if (navigator.storage && navigator.storage.estimate) {
        return navigator.storage.estimate().then((est) => ({
          usage: est.usage || 0,
          quota: est.quota || 0,
        }));
      }
      return Promise.resolve({ usage: 0, quota: 0 });
    },
  };
}

function createCompressionTasks() {
  function toBase64(uint8array) {
    let binary = "";
    for (let i = 0; i < uint8array.length; i++) {
      binary += String.fromCharCode(uint8array[i]);
    }
    return btoa(binary);
  }

  function fromBase64(base64) {
    return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  }

  function importAesKey(base64) {
    return crypto.subtle.importKey(
      "raw",
      fromBase64(base64),
      { name: "AES-GCM", length: 256 },
      true,
      ["encrypt", "decrypt"],
    );
  }

  return {
    // Compress (if beneficial) then encrypt a JSON string.
    // Returns { ciphertext, iv, compressed }.
    "compression:encryptJson": async ({ key, json, threshold }) => {
      try {
        const encoder = new TextEncoder();
        const originalBytes = encoder.encode(json);
        let dataToEncrypt = originalBytes;
        let compressed = false;

        if (typeof CompressionStream !== "undefined") {
          try {
            const compressedBytes = new Uint8Array(
              await new Response(
                new Blob([originalBytes])
                  .stream()
                  .pipeThrough(new CompressionStream("gzip")),
              ).arrayBuffer(),
            );
            console.log("Original   size: ", originalBytes.length);
            console.log("Compressed size: ", compressedBytes.length);
            if (compressedBytes.length <= threshold * originalBytes.length) {
              dataToEncrypt = compressedBytes;
              compressed = true;
            }
          } catch (_) {
            // Compression unavailable or failed, use original
          }
        }

        const cryptoKey = await importAesKey(key);
        const iv = crypto.getRandomValues(new Uint8Array(12));
        const ciphertext = await crypto.subtle.encrypt(
          { name: "AES-GCM", iv },
          cryptoKey,
          dataToEncrypt,
        );
        return {
          ciphertext: toBase64(new Uint8Array(ciphertext)),
          iv: toBase64(iv),
          compressed,
        };
      } catch (e) {
        return { error: "ENCRYPTION_FAILED:" + e.message };
      }
    },

    // Decrypt then decompress (if needed) to a JSON string.
    "compression:decryptJson": async ({ key, ciphertext, iv, compressed }) => {
      try {
        const cryptoKey = await importAesKey(key);
        const decrypted = await crypto.subtle.decrypt(
          { name: "AES-GCM", iv: fromBase64(iv) },
          cryptoKey,
          fromBase64(ciphertext),
        );
        let bytes = new Uint8Array(decrypted);
        if (compressed) {
          bytes = new Uint8Array(
            await new Response(
              new Blob([bytes])
                .stream()
                .pipeThrough(new DecompressionStream("gzip")),
            ).arrayBuffer(),
          );
        }
        return new TextDecoder().decode(bytes);
      } catch (e) {
        return { error: "DECRYPTION_FAILED:Invalid key or corrupted data" };
      }
    },
  };
}

ConcurrentTask.register({
  tasks: {
    ...createWebCryptoTasks(),
    ...createIndexedDbTasks(),
    ...pbTasks,
    ...createUsageStatsTasks(),
    ...createCompressionTasks(),
  },
  ports: {
    send: app.ports.sendTask,
    receive: app.ports.receiveTask,
  },
});

// Network bandwidth tracking via PerformanceObserver
if (typeof PerformanceObserver !== "undefined") {
  let pendingBytes = 0;

  try {
    const observer = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        if (entry.transferSize > 0) {
          pendingBytes += entry.transferSize;
        }
      }
    });
    observer.observe({ type: "resource", buffered: true });
  } catch (e) {
    // PerformanceObserver not supported for resource type
  }

  function flushBytesToIdb() {
    if (pendingBytes === 0) return;
    const bytesToAdd = pendingBytes;
    pendingBytes = 0;
    const req = indexedDB.open("partage");
    req.onsuccess = (e) => {
      const db = e.target.result;
      if (!db.objectStoreNames.contains("usageStats")) {
        db.close();
        pendingBytes += bytesToAdd;
        return;
      }
      const tx = db.transaction("usageStats", "readwrite");
      const store = tx.objectStore("usageStats");
      const getReq = store.get("stats");
      getReq.onsuccess = () => {
        const stats = getReq.result || {
          trackingStartDate: Date.now(),
          totalBytesTransferred: 0,
          storageBytes: 0,
          storageLastCheckedDate: "",
          storageCostAccumulatorCentNanos: 0,
        };
        stats.totalBytesTransferred += bytesToAdd;
        store.put(stats, "stats");
      };
      tx.oncomplete = () => db.close();
      tx.onerror = () => {
        db.close();
        pendingBytes += bytesToAdd;
      };
    };
    req.onerror = () => {
      pendingBytes += bytesToAdd;
    };
  }

  setInterval(flushBytesToIdb, 100_000);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") {
      flushBytesToIdb();
    }
  });
}

initPwa({
  ports: {
    pwaIn: app.ports.pwaIn,
    pwaOut: app.ports.pwaOut,
  },
});
