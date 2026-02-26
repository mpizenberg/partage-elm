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
  },
});

initNavigation({
  navCmd: app.ports.navCmd,
  onNavEvent: app.ports.onNavEvent,
});
