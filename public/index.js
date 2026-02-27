import * as ConcurrentTask from "@andrewmacmurray/elm-concurrent-task";
import { createTasks as createWebCryptoTasks } from "../vendor/elm-webcrypto/js/src/index.js";
import { createTasks as createIndexedDbTasks } from "../vendor/elm-indexeddb/js/src/index.js";

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
  },
});

initNavigation({
  navCmd: app.ports.navCmd,
  onNavEvent: app.ports.onNavEvent,
});

ConcurrentTask.register({
  tasks: { ...createWebCryptoTasks(), ...createIndexedDbTasks() },
  ports: {
    send: app.ports.sendTask,
    receive: app.ports.receiveTask,
  },
});
