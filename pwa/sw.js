// Cache só do casco e dos pesos do face-api. A marcação NUNCA é
// enfileirada offline: o horário válido é o do servidor, e um registro
// gravado com atraso de horas é pior que registro nenhum.
const CACHE = 'ponto-cna-v1';
const MODELOS = ['tiny_face_detector', 'face_landmark_68', 'face_recognition', 'face_expression'];
const CASCO = [
  './index.html', './manifest.webmanifest',
  // manifesto e pesos: sem o .bin o face-api baixa 7 MB a cada marcação
  ...MODELOS.flatMap((m) => [
    `./models/${m}_model-weights_manifest.json`,
    `./models/${m}_model.bin`,
  ]),
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
