self.addEventListener('activate', event => {
  console.log('Service Worker: Claiming clients');
  self.clients.claim();
});

// Push event - handle push notifications
self.addEventListener('push', event => {
  console.log('Service Worker: Push event received', event);

  const options = {
    body: event.data ? event.data.text() : '',
    icon: 'icon-192.png',
    badge: 'icon-192.png',
    vibrate: [200, 100, 200],
    data: {
      url: '/'
    },
    actions: [
      {
        action: 'view',
        title: 'View Weather'
      }
    ]
  };

  event.waitUntil(
    self.registration.showNotification('😎 Nice', options)
  );
});

// Notification click event
self.addEventListener('notificationclick', event => {
  console.log('Service Worker: Notification clicked', event);

  event.notification.close();

  if (event.action === 'view' || !event.action) {
    event.waitUntil(
      clients.openWindow(event.notification.data.url || '/')
    );
  }
});

// Background sync (for future enhancement)
self.addEventListener('sync', event => {
  console.log('Service Worker: Background sync', event.tag);

  if (event.tag === 'weather-sync') {
    event.waitUntil(
      // Could sync weather data in background
      console.log('Service Worker: Weather sync requested')
    );
  }
});

// Message event - communicate with main app
self.addEventListener('message', event => {
  console.log('Service Worker: Message received', event.data);

  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});