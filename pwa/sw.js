// Cache só do casco e dos pesos do face-api. A marcação NUNCA é
// enfileirada offline: o horário válido é o do servidor, e um registro
// gravado com atraso de horas é pior que registro nenhum.
const CACHE = 'ponto-cna-v1';
const CASCO = [
  './index.html', './manifest.webmanifest',
  './models/tiny_face_detector_model-weights_manifest.json',
  './models/face_landmark_68_model-weights_manifest.json',
  './models/face_recognition_model-weights_manifest.json',
  './models/face_expression_model-weights_manifest.json',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(CASCO)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (url.pathname.includes('/functions/') || url.pathname.includes('/rest/')) return;
  e.respondWith(caches.match(e.request).then((r) => r || fetch(e.request)));
});
