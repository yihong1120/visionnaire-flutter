{{flutter_js}}
{{flutter_build_config}}

const serviceWorkerVersion = {{flutter_service_worker_version}};

const appBuildVersion = String(serviceWorkerVersion || Date.now());

const appendVersionQuery = (path) => {
  if (!path || typeof path !== 'string') return path;
  if (/[?&]v=/.test(path)) return path;
  return `${path}${path.includes('?') ? '&' : '?'}v=${encodeURIComponent(appBuildVersion)}`;
};

const cacheBustFlutterEntrypoints = () => {
  const buildConfig = window._flutter && window._flutter.buildConfig;
  const builds = buildConfig && Array.isArray(buildConfig.builds)
    ? buildConfig.builds
    : [];
  builds.forEach((build) => {
    if (!build || typeof build !== 'object') return;
    build.mainJsPath = appendVersionQuery(build.mainJsPath);
    build.mainWasmPath = appendVersionQuery(build.mainWasmPath);
    build.jsSupportRuntimePath = appendVersionQuery(build.jsSupportRuntimePath);
  });
};

const clearLegacyServiceWorkers = async () => {
  if (!('serviceWorker' in navigator)) return;
  const registrations = await navigator.serviceWorker.getRegistrations();
  await Promise.all(
    registrations.map((registration) => {
      const worker = registration.active || registration.waiting || registration.installing;
      const scriptUrl = worker && worker.scriptURL ? worker.scriptURL : '';
      if (scriptUrl.endsWith('/firebase-messaging-sw.js')) {
        return Promise.resolve(false);
      }
      return registration.unregister();
    }),
  );
};

const clearLegacyFlutterCaches = async () => {
  if (!('caches' in window)) return;
  const cacheNames = await caches.keys();
  await Promise.all(
    cacheNames
      .filter((name) => !name.includes('firebase'))
      .map((name) => caches.delete(name)),
  );
};

Promise.all([
  clearLegacyServiceWorkers(),
  clearLegacyFlutterCaches(),
]).finally(() => {
  cacheBustFlutterEntrypoints();
  _flutter.loader.load();
});
