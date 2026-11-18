const CACHE_NAME = "coachingos-shell-v1";
const APP_SHELL = ["./", "./index.html", "./manifest.webmanifest", "./assets/coachingos-icon.svg"];

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", event => {
  const request = event.request;
  const url = new URL(request.url);

  // Never cache Supabase, authentication, user records, or other cross-origin data.
  if (request.method !== "GET" || url.origin !== self.location.origin) return;

  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request)
        .then(response => {
          if (response.ok) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then(cache => cache.put(request, copy));
          }
          return response;
        })
        .catch(async () => {
          return (await caches.match(request)) ||
            (await caches.match("./")) ||
            Response.error();
        })
    );
    return;
  }

  // Cache only the app shell assets; do not cache arbitrary same-origin responses.
  if (APP_SHELL.some(path => new URL(path, self.registration.scope).pathname === url.pathname)) {
    event.respondWith(
      caches.match(request).then(cached => cached || fetch(request))
    );
  }
});