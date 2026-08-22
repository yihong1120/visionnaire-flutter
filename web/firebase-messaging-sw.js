importScripts('https://www.gstatic.com/firebasejs/12.15.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.15.0/firebase-messaging-compat.js');
importScripts('firebase-messaging-config.generated.js');

const firebaseMessagingConfig = self.__FIREBASE_MESSAGING_CONFIG__;

const firstText = (...values) => {
  for (const value of values) {
    if (typeof value === 'string' && value.trim()) return value.trim();
  }
  return null;
};

const violationRoute = (data) => {
  const id = firstText(
    data.violation_id,
    data.violationId,
    data.violation_record_id,
    data.violationRecordId,
    data.record_id,
    data.recordId,
    data.case_id,
    data.caseId,
  );
  return id ? `/violations/${encodeURIComponent(id)}` : '/violations';
};

const notificationRoute = (data) => {
  const explicitRoute = firstText(data.deep_link, data.deepLink, data.route);
  if (explicitRoute) return explicitRoute;
  return violationRoute(data);
};

const notificationContent = (payload) => {
  const data = payload.data || {};
  const notification = payload.notification || {};
  const title = firstText(notification.title, data.title) || 'Visionnaire';
  const body = firstText(notification.body, data.body, data.message) || '';

  return {
    title,
    options: {
      body,
      icon: data.icon || 'icons/Icon-192.png',
      badge: data.badge || 'icons/Icon-192.png',
      data,
    },
  };
};

if (firebaseMessagingConfig !== null) {
  firebase.initializeApp(firebaseMessagingConfig);
  const messaging = firebase.messaging();

  messaging.onBackgroundMessage((payload) => {
    const {title, options} = notificationContent(payload);
    self.registration.showNotification(title, options);
  });
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const data = event.notification.data || {};
  const target = notificationRoute(data);

  event.waitUntil(
    self.clients.matchAll({type: 'window', includeUncontrolled: true}).then(
      (clientList) => {
        for (const client of clientList) {
          const url = new URL(client.url);
          if (url.origin !== self.location.origin) continue;
          client.focus();
          if ('navigate' in client) return client.navigate(target);
          return undefined;
        }
        return self.clients.openWindow(target);
      },
    ),
  );
});
