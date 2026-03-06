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

ConcurrentTask.register({
  tasks: { ...createWebCryptoTasks(), ...createIndexedDbTasks(), ...pbTasks },
  ports: {
    send: app.ports.sendTask,
    receive: app.ports.receiveTask,
  },
});

initPwa({
  ports: {
    pwaIn: app.ports.pwaIn,
    pwaOut: app.ports.pwaOut,
  },
});
