import React, { createContext, useContext, useState, useEffect } from 'react';
import ApiClient from '../services/api';

interface User {
  id: number;
  role: string;
  username: string;
  name: string;
  email?: string;
  phone?: string;
  active: number;
  created_at: string;
}

interface AuthContextType {
  user: User | null;
  loading: boolean;
  login: (username: string, password: string) => Promise<void>;
  logout: () => void;
  checkAuth: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  const checkAuth = async () => {
    setLoading(true);
    try {
      const token = localStorage.getItem('auth_token');
      if (token) {
        const res = await fetch('https://school-management-system-5jqj.onrender.com/api/auth/me', {
          headers: { 'Authorization': `Bearer ${token}`, 'ngrok-skip-browser-warning': 'true' }
        });
        if (res.ok) {
          const data = await res.json();
          setUser(data.user);
        }
      }
    } catch (e) {
      console.error('Auth check failed:', e);
    } finally {
      setLoading(false);
    }
  };

  const login = async (username: string, password: string) => {
    const data = await ApiClient.login(username, password);
    if (data.token) {
      if (data.user.role !== 'admin') throw new Error('Admin access required');
      setUser(data.user);
    } else {
      throw new Error(data.error || 'Login failed');
    }
  };

  const logout = () => {
    ApiClient.logout();
    setUser(null);
  };

  return (
    <AuthContext.Provider value={{ user, loading, login, logout, checkAuth }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used within AuthProvider');
  return context;
};