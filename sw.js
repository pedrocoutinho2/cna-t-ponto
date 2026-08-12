// Cache só do casco e dos pesos do face-api. A marcação NUNCA é
// enfileirada offline: o horário válido é o do servidor, e um registro
// gravado com atraso de horas é pior que registro nenhum.
const CACHE = 'ponto-cna-v3';
const MODELOS = ['tiny_face_detector', 'face_landmark_68', 'face_recognition', 'face_expression'];
const CASCO = [
  './index.html', './manifest.webmanifest',
  './assets/cna.css', './assets/logo-cna.png', './assets/logo-cna-branca.png',
  './assets/icon-192.png', './assets/icon-512.png',
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

// As telas vao para a rede primeiro, com o cache como rede de seguranca.
// Com cache-first o celular continuava abrindo a versao antiga do PWA depois
// de cada deploy, ate alguem limpar os dados do navegador na mao.
const ehTela = (req) =>
  req.mode === 'navigate' || (req.destination === 'document') || /\.html($|\?)/.test(req.url);

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (url.pathname.includes('/functions/') || url.pathname.includes('/rest/')) return;

  if (ehTela(e.request)) {
    e.respondWith(
      fetch(e.request)
        .then((r) => {
          const copia = r.clone();
          caches.open(CACHE).then((c) => c.put(e.request, copia)).catch(() => {});
          return r;
        })
        .catch(() => caches.match(e.request).then((r) => r || caches.match('./index.html')))
    );
    return;
  }

  e.respondWith(caches.match(e.request).then((r) => r || fetch(e.request)));
});
