/// <reference path="../pb_data/types.d.ts" />

/**
 * Add Timing-Allow-Origin header for cross-origin PerformanceResourceTiming.
 * Allows the client app to measure transferSize for API requests.
 */
onEvent("OnServe", (e) => {
  const allowed = [
    "http://localhost:50217",
    "http://localhost:54448",
    // Add production origin here
    "https://partage.dokploy.zidev.ovh",
  ];

  e.router.use((e) => {
    const origin = e.request.header.get("Origin");
    if (allowed.includes(origin)) {
      e.response.header().set("Timing-Allow-Origin", origin);
    }
    e.next();
  });

  e.next();
});
