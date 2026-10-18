const API_URL = 'https://school-management-system-5jqj.onrender.com';

class ApiClient {
  static token = null;
  static cache = new Map();
  static CACHE_DURATION = 5 * 60 * 1000;

  static init() {
    if (typeof window !== 'undefined') {
      const stored = localStorage.getItem('auth_token');
      if (stored) this.token = stored;
      try {
        const cached = localStorage.getItem('api_cache');
        if (cached) {
          const parsed = JSON.parse(cached);
          this.cache = new Map(Object.entries(parsed));
        }
      } catch (e) {}
    }
  }

  static async login(username, password) {
    const res = await fetch(`${API_URL}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true' },
      body: JSON.stringify({ username, password })
    });
    const data = await res.json();
    if (data.token) {
      this.token = data.token;
      localStorage.setItem('auth_token', data.token);
    }
    return data;
  }

  static async get(path, useCache = true) {
    const cacheKey = path;
    if (useCache && this.cache.has(cacheKey)) {
      const cached = this.cache.get(cacheKey);
      if (Date.now() - cached.timestamp < this.CACHE_DURATION) {
        return cached.data;
      }
    }
    const headers = {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
    };
    if (this.token) headers['Authorization'] = `Bearer ${this.token}`;
    const res = await fetch(`${API_URL}${path}`, { headers });
    const data = await res.json();
    if (useCache) {
      this.cache.set(cacheKey, { data, timestamp: Date.now() });
      this.saveCache();
    }
    return data;
  }

  static async post(path, body) {
    const res = await fetch(`${API_URL}${path}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
        ...(this.token ? { Authorization: `Bearer ${this.token}` } : {})
      },
      body: JSON.stringify(body || {})
    });
    return res.json();
  }

  static async put(path, body) {
    const res = await fetch(`${API_URL}${path}`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
        ...(this.token ? { Authorization: `Bearer ${this.token}` } : {})
      },
      body: JSON.stringify(body || {})
    });
    return res.json();
  }

  static async delete(path) {
    const res = await fetch(`${API_URL}${path}`, {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
        ...(this.token ? { Authorization: `Bearer ${this.token}` } : {})
      }
    });
    return res.json();
  }

  static logout() {
    this.token = null;
    this.cache.clear();
    localStorage.removeItem('auth_token');
    localStorage.removeItem('api_cache');
  }

  static saveCache() {
    try {
      const obj = Object.fromEntries(this.cache);
      localStorage.setItem('api_cache', JSON.stringify(obj));
    } catch (e) {}
  }

  static clearCache(path) {
    if (path) this.cache.delete(path);
    else this.cache.clear();
    this.saveCache();
  }

  static getCached(path) {
    const cached = this.cache.get(path);
    if (cached && Date.now() - cached.timestamp < this.CACHE_DURATION) {
      return cached.data;
    }
    return null;
  }
}

export default ApiClient;