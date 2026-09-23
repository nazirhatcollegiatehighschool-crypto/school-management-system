const API = '/api';

let token = localStorage.getItem('token') || '';

export function setToken(t) {
  token = t || '';
  if (t) localStorage.setItem('token', t);
  else localStorage.removeItem('token');
}

export function getToken() {
  return token;
}

export async function api(path, opts = {}) {
  const res = await fetch(API + path, {
    method: opts.method || 'GET',
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Bearer ' + token
    },
    body: opts.body ? JSON.stringify(opts.body) : undefined
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    if (res.status === 401) {
      token = '';
      localStorage.removeItem('token');
      if (window.__onSessionExpired) window.__onSessionExpired();
    }
    throw new Error(data.error || 'Request failed');
  }
  return data;
}