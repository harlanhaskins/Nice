class NiceWeatherApp {
    constructor() {
        this.baseURL = 'api';
        this.auth = null;
        this.isSignUp = false;
        this.locationPermission = 'default';
        this.notificationPermission = 'default';

        this.init();
    }

    init() {
        this.loadStoredAuth();
        this.bindEvents();
        this.updateUI();
        this.requestPermissions();
        this.requestLocation(); // Request location on app load

        if ('serviceWorker' in navigator) {
            navigator.serviceWorker.register('sw.js')
                .then(registration => console.log('SW registered:', registration))
                .catch(error => console.log('SW registration failed:', error));
        }
    }

    bindEvents() {
        document.getElementById('auth-form').addEventListener('submit', (e) => this.handleAuth(e));
        document.getElementById('auth-toggle').addEventListener('click', (e) => this.toggleAuthMode(e));
        document.getElementById('location-btn').addEventListener('click', () => this.requestLocation());
        document.getElementById('notification-btn').addEventListener('click', () => this.requestNotifications());
        document.getElementById('refresh-weather').addEventListener('click', () => this.loadWeather());
        document.getElementById('test-notifications').addEventListener('click', () => this.registerPushNotifications());
        document.getElementById('send-test-notification').addEventListener('click', () => this.sendTestNotification());
        document.getElementById('sign-out').addEventListener('click', () => this.signOut());
    }

    loadStoredAuth() {
        const stored = localStorage.getItem('nice-auth');
        if (stored) {
            try {
                this.auth = JSON.parse(stored);
                // Check if token is expired
                if (new Date(this.auth.token.expires) > new Date()) {
                    this.updateUI();
                    this.loadWeather();
                    // Register push notifications if permission is already granted
                    console.log('Loaded stored auth, notification permission:', this.notificationPermission);
                    if (this.notificationPermission === 'granted') {
                        console.log('Registering push notifications from stored auth');
                        this.registerPushNotifications();
                    } else {
                        console.log('Notification permission not granted for stored auth, skipping push registration');
                    }
                } else {
                    this.clearAuth();
                }
            } catch (e) {
                this.clearAuth();
            }
        }
    }

    async handleAuth(event) {
        event.preventDefault();

        const username = document.getElementById('username').value;
        const password = document.getElementById('password').value;
        const confirmPassword = document.getElementById('confirm-password').value;

        if (!username || !password) {
            this.showError('Please fill in all fields');
            return;
        }

        if (this.isSignUp) {
            if (!confirmPassword) {
                this.showError('Please confirm your password');
                return;
            }

            if (password !== confirmPassword) {
                this.showError('Passwords do not match');
                return;
            }

            if (password.length < 8) {
                this.showError('Password must be at least 8 characters long');
                return;
            }
        }

        this.setLoading(true);

        try {
            const endpoint = this.isSignUp ? 'users' : 'auth';
            const body = { username, password };

            // Add location if we have it during signup
            if (this.isSignUp && this.currentLocation) {
                body.location = this.currentLocation;
            }

            const response = await fetch(`${this.baseURL}/${endpoint}`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(body),
            });

            if (!response.ok) {
                const error = await response.text();
                throw new Error(error || `HTTP ${response.status}`);
            }

            this.auth = await response.json();
            localStorage.setItem('nice-auth', JSON.stringify(this.auth));

            this.showSuccess(this.isSignUp ? 'Account created successfully!' : 'Signed in successfully!');
            this.updateUI();
            this.loadWeather();

            // Register push notifications if permission is already granted
            console.log('Sign-in complete, notification permission:', this.notificationPermission);
            if (this.notificationPermission === 'granted') {
                console.log('Registering push notifications after sign-in');
                await this.registerPushNotifications();
            } else {
                console.log('Notification permission not granted, skipping push registration');
            }

        } catch (error) {
            console.error('Auth error:', error);
            this.showError(error.message || 'Authentication failed');
        } finally {
            this.setLoading(false);
        }
    }

    toggleAuthMode(event) {
        event.preventDefault();
        this.isSignUp = !this.isSignUp;
        this.updateAuthForm();
    }

    updateAuthForm() {
        const button = document.getElementById('auth-button');
        const toggleText = document.getElementById('auth-toggle-text');
        const toggleLink = document.getElementById('auth-toggle');
        const confirmPasswordGroup = document.getElementById('confirm-password-group');
        const confirmPasswordInput = document.getElementById('confirm-password');

        if (this.isSignUp) {
            button.textContent = 'Sign Up';
            toggleText.textContent = 'Already have an account?';
            toggleLink.textContent = 'Sign In';
            confirmPasswordGroup.style.display = 'block';
            confirmPasswordInput.required = true;
        } else {
            button.textContent = 'Sign In';
            toggleText.textContent = "Don't have an account?";
            toggleLink.textContent = 'Sign Up';
            confirmPasswordGroup.style.display = 'none';
            confirmPasswordInput.required = false;
            confirmPasswordInput.value = '';
        }
    }

    async requestLocation() {
        if (!navigator.geolocation) {
            this.showError('Geolocation is not supported by this browser');
            return;
        }

        try {
            const position = await new Promise((resolve, reject) => {
                navigator.geolocation.getCurrentPosition(resolve, reject, {
                    enableHighAccuracy: true,
                    timeout: 10000,
                    maximumAge: 300000 // 5 minutes
                });
            });

            this.currentLocation = {
                latitude: position.coords.latitude,
                longitude: position.coords.longitude
            };

            this.locationPermission = 'granted';
            this.updatePermissionStatus();
            this.showSuccess('Location access granted!');

            // Update location on server if authenticated
            if (this.auth) {
                await this.updateServerLocation();
                this.loadWeather();
            }

        } catch (error) {
            console.error('Location error:', error);
            this.locationPermission = 'denied';
            this.updatePermissionStatus();
            this.showError('Location access denied or failed');
        }
    }

    async updateServerLocation() {
        if (!this.auth || !this.currentLocation) return;

        try {
            const response = await fetch(`${this.baseURL}/location`, {
                method: 'PUT',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${this.auth.token.token}`,
                },
                body: JSON.stringify(this.currentLocation),
            });

            if (!response.ok) {
                throw new Error(`Failed to update location: ${response.status}`);
            }
        } catch (error) {
            console.error('Failed to update server location:', error);
        }
    }

    async requestNotifications() {
        if (!('Notification' in window)) {
            this.showError('This browser does not support notifications');
            return;
        }

        try {
            const permission = await Notification.requestPermission();
            this.notificationPermission = permission;
            this.updatePermissionStatus();

            if (permission === 'granted') {
                this.showSuccess('Notification access granted!');
                await this.registerPushNotifications();
            } else {
                this.showError('Notification access denied');
            }
        } catch (error) {
            console.error('Notification error:', error);
            this.showError('Failed to request notification permission');
        }
    }

    async registerPushNotifications() {
        if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
            console.log('Push notifications not supported');
            return;
        }

        if (!this.auth) {
            console.log('Not authenticated, skipping push notification registration');
            return;
        }

        try {
            // Get the VAPID public key from the server
            const vapidResponse = await fetch(`${this.baseURL}/notifications/vapid-public-key`);
            if (!vapidResponse.ok) {
                throw new Error('Failed to get VAPID public key');
            }

            const vapidData = await vapidResponse.json();
            console.log('VAPID response:', vapidData);
            const publicKey = vapidData.publicKey || vapidData;
            console.log('Public key:', publicKey);
            console.log('Public key length (base64):', publicKey.length);
            const applicationServerKey = this.base64ToUint8Array(publicKey);
            console.log('Application server key ready, length:', applicationServerKey.length);

            const registration = await navigator.serviceWorker.ready;

            // Subscribe to push notifications
            const subscription = await registration.pushManager.subscribe({
                userVisibleOnly: true,
                applicationServerKey: applicationServerKey
            });

            // Register the subscription with the server
            console.log('About to send push token to server...');
            await this.sendPushTokenToServer(subscription);

            console.log('Push subscription registered:', subscription);
            this.showSuccess('Push notifications registered!');
        } catch (error) {
            console.error('Failed to register push notifications:', error);
            this.showError('Failed to register push notifications');
        }
    }

    async sendPushTokenToServer(subscription) {
        console.log('sendPushTokenToServer called with subscription:', subscription);
        if (!this.auth) {
            console.error("No auth available; not sending notification push update");
            return;
        }

        try {
            const response = await fetch(`${this.baseURL}/notifications`, {
                method: 'PUT',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${this.auth.token.token}`,
                },
                body: JSON.stringify({
                    token: JSON.stringify(subscription),
                    deviceType: 'web'
                }),
            });

            if (!response.ok) {
                throw new Error(`Failed to register push token: ${response.status}`);
            }

            console.log('Push token registered with server');
        } catch (error) {
            console.error('Failed to send push token to server:', error);
            throw error;
        }
    }

    base64ToUint8Array(base64String) {
        // Remove any padding and convert to raw bytes
        const padding = '='.repeat((4 - base64String.length % 4) % 4);
        const base64 = (base64String + padding)
            .replace(/-/g, '+')
            .replace(/_/g, '/');

        const rawData = window.atob(base64);
        const outputArray = new Uint8Array(rawData.length);

        for (let i = 0; i < rawData.length; ++i) {
            outputArray[i] = rawData.charCodeAt(i);
        }

        console.log('Converted key length:', outputArray.length, 'bytes');
        console.log('Key bytes:', Array.from(outputArray.slice(0, 8)).map(b => b.toString(16).padStart(2, '0')).join(' '), '...');
        return outputArray;
    }

    async sendTestNotification() {
        if (!this.auth) {
            this.showError('Please sign in to send test notifications');
            return;
        }

        if (this.notificationPermission !== 'granted') {
            this.showError('Please enable notifications first');
            return;
        }

        try {
            const response = await fetch(`${this.baseURL}/notifications/test`, {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${this.auth.token.token}`,
                },
            });

            if (!response.ok) {
                throw new Error(`Failed to send test notification: ${response.status}`);
            }

            this.showSuccess('Test notification sent!');
        } catch (error) {
            console.error('Test notification error:', error);
            this.showError(error.message || 'Failed to send test notification');
        }
    }

    async loadWeather() {
        if (!this.auth) return;

        try {
            const response = await fetch(`${this.baseURL}/forecast`, {
                headers: {
                    'Authorization': `Bearer ${this.auth.token.token}`,
                },
            });

            if (!response.ok) {
                if (response.status === 400) {
                    this.showError('Please enable location services to see weather forecast');
                    return;
                }
                throw new Error(`Failed to load weather: ${response.status}`);
            }

            const forecast = await response.json();
            this.displayWeather(forecast);
            document.getElementById('weather-section').classList.remove('hidden');

        } catch (error) {
            console.error('Weather error:', error);
            this.showError(error.message || 'Failed to load weather');
        }
    }

    displayWeather(forecast) {
        document.getElementById('temperature').textContent = `${Math.round(forecast.temperature)}°`;
        document.getElementById('feels-like').textContent = `${Math.round(forecast.feelsLike)}°`;
        document.getElementById('clouds').textContent = `${forecast.clouds}%`;

        const sunrise = new Date(forecast.sunrise).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
        const sunset = new Date(forecast.sunset).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});

        document.getElementById('sunrise').textContent = sunrise;
        document.getElementById('sunset').textContent = sunset;

        // Show "nice" indicator
        const indicator = document.getElementById('nice-indicator');
        const text = document.getElementById('nice-text');

        if (forecast.isNice) {
            indicator.className = 'nice-indicator nice';
            text.textContent = '😎';
        } else {
            indicator.className = 'nice-indicator not-nice';
            text.textContent = '😐';
        }

        indicator.classList.remove('hidden');
    }

    async signOut() {
        if (!this.auth) return;

        try {
            // Get the push subscription to send as notification token
            let notificationToken = '';
            if ('serviceWorker' in navigator && 'PushManager' in window) {
                try {
                    const registration = await navigator.serviceWorker.ready;
                    const subscription = await registration.pushManager.getSubscription();
                    if (subscription) {
                        notificationToken = JSON.stringify(subscription);
                    }
                } catch (subError) {
                    console.error('Failed to get push subscription for logout:', subError);
                }
            }

            await fetch(`${this.baseURL}/auth`, {
                method: 'DELETE',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${this.auth.token.token}`,
                },
                body: JSON.stringify({
                    notificationToken: notificationToken
                }),
            });
        } catch (error) {
            console.error('Sign out error:', error);
        }

        this.clearAuth();
        this.updateUI();
        this.showSuccess('Signed out successfully');
    }

    clearAuth() {
        this.auth = null;
        localStorage.removeItem('nice-auth');
    }

    updateUI() {
        const authSection = document.getElementById('auth-section');
        const appSection = document.getElementById('app-section');

        if (this.auth) {
            authSection.classList.add('hidden');
            appSection.classList.remove('hidden');
            document.getElementById('username-display').textContent = this.auth.user.username;
        } else {
            authSection.classList.remove('hidden');
            appSection.classList.add('hidden');
            document.getElementById('weather-section').classList.add('hidden');
        }

        this.updatePermissionStatus();
    }

    updatePermissionStatus() {
        document.getElementById('location-status').textContent = this.getPermissionText(this.locationPermission);
        document.getElementById('notification-status').textContent = this.getPermissionText(this.notificationPermission);

        // Update button states
        document.getElementById('location-btn').disabled = this.locationPermission === 'granted';
        document.getElementById('notification-btn').disabled = this.notificationPermission === 'granted';
    }

    getPermissionText(permission) {
        switch (permission) {
            case 'granted': return 'Granted ✅';
            case 'denied': return 'Denied ❌';
            default: return 'Not requested';
        }
    }

    requestPermissions() {
        // Synchronously check notification permission first
        if ('Notification' in window) {
            this.notificationPermission = Notification.permission;
        }

        // Check current permission states
        if (navigator.geolocation) {
            navigator.permissions?.query({name: 'geolocation'}).then(result => {
                this.locationPermission = result.state;
                this.updatePermissionStatus();
            });
        }

        this.updatePermissionStatus();
    }

    setLoading(loading) {
        const button = document.getElementById('auth-button');
        button.disabled = loading;
        button.textContent = loading ? 'Loading...' : (this.isSignUp ? 'Sign Up' : 'Sign In');
    }

    showError(message) {
        this.hideMessages();
        const errorEl = document.getElementById('error-message');
        errorEl.textContent = message;
        errorEl.classList.remove('hidden');
        setTimeout(() => errorEl.classList.add('hidden'), 5000);
    }

    showSuccess(message) {
        this.hideMessages();
        const successEl = document.getElementById('success-message');
        successEl.textContent = message;
        successEl.classList.remove('hidden');
        setTimeout(() => successEl.classList.add('hidden'), 3000);
    }

    hideMessages() {
        document.getElementById('error-message').classList.add('hidden');
        document.getElementById('success-message').classList.add('hidden');
    }
}

// Initialize app when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    new NiceWeatherApp();
});