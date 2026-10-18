import React, { useState } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, SafeAreaView, ScrollView, Switch, Alert } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useAuth } from '../context/AuthContext';
import ApiClient from '../services/api';

export const SettingsScreen: React.FC = () => {
  const { user, logout } = useAuth();
  const [darkMode, setDarkMode] = useState(false);
  const [notifications, setNotifications] = useState(true);
  const [serverUrl, setServerUrl] = useState('https://school-management-system-5jqj.onrender.com');

  const handleLogout = () => {
    Alert.alert('Sign Out', 'Are you sure you want to log out?', [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Logout', style: 'destructive', onPress: () => logout() },
    ]);
  };

  const testConnection = async () => {
    try {
      const res = await fetch(`${serverUrl}/api/health`);
      const data = await res.json();
      if (data.status === 'ok') {
        Alert.alert('Success', 'Server is reachable!');
      } else {
        Alert.alert('Error', 'Server returned error');
      }
    } catch (e) {
      Alert.alert('Error', 'Cannot reach server');
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Settings</Text>
      </View>

      <ScrollView contentContainerStyle={styles.content}>
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Account</Text>
          <View style={styles.settingItem}>
            <View style={styles.settingInfo}>
              <Text style={styles.settingLabel}>Logged in as</Text>
              <Text style={styles.settingValue}>{user?.name || 'Guardian'}</Text>
            </View>
            <Text style={styles.settingRole}>{user?.role?.toUpperCase() || 'GUARDIAN'}</Text>
          </View>
          <TouchableOpacity onPress={handleLogout} style={styles.logoutBtn}>
            <Text style={styles.logoutText}>Logout</Text>
          </TouchableOpacity>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Server</Text>
          <View style={styles.settingItem}>
            <View style={styles.settingInfo}>
              <Text style={styles.settingLabel}>Server URL</Text>
              <Text style={styles.settingValue}>https://school-management-system-5jqj.onrender.com</Text>
            </View>
          </View>
          <TouchableOpacity onPress={() => {}} style={styles.testBtn}>
            <Text style={styles.testBtnText}>Test Connection</Text>
          </TouchableOpacity>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Preferences</Text>
          <View style={styles.settingItem}>
            <View style={styles.settingInfo}>
              <Text style={styles.settingLabel}>Dark Mode</Text>
              <Text style={styles.settingValue}>Coming Soon</Text>
            </View>
            <Switch value={false} onValueChange={() => {}} trackColor={{ false: '#E2E8F0', true: '#052E22' }} thumbColor="#052E22" />
          </View>
          <View style={styles.settingItem}>
            <View style={styles.settingInfo}>
              <Text style={styles.settingLabel}>Push Notifications</Text>
              <Text style={styles.settingValue}>Receive alerts</Text>
            </View>
            <Switch value={true} onValueChange={() => {}} trackColor={{ false: '#E2E8F0', true: '#052E22' }} thumbColor="#052E22" />
          </View>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>About</Text>
          <View style={styles.settingItem}>
            <View style={styles.settingInfo}>
              <Text style={styles.settingLabel}>Version</Text>
              <Text style={styles.settingValue}>1.0.0</Text>
            </View>
          </View>
          <View style={styles.settingItem}>
            <View style={styles.settingInfo}>
              <Text style={styles.settingLabel}>Build</Text>
              <Text style={styles.settingValue}>2026.10.15</Text>
            </View>
          </View>
          <View style={styles.settingItem}>
            <View style={styles.settingInfo}>
              <Text style={styles.settingLabel}>Backend</Text>
              <Text style={styles.settingValue}>Render + Supabase</Text>
            </View>
          </View>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#F8FAFC' },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12, backgroundColor: 'white', borderBottomWidth: 1, borderColor: '#E2E8F0' },
  headerTitle: { fontSize: 18, fontWeight: '800', color: '#0F172A' },
  content: { padding: 16, paddingBottom: 30 },
  section: { marginBottom: 24 },
  sectionTitle: { fontSize: 13, fontWeight: '800', color: '#64748B', letterSpacing: 0.5, textTransform: 'uppercase', marginBottom: 12 },
  settingItem: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', backgroundColor: 'white', padding: 16, borderRadius: 12, borderWidth: 1, borderColor: '#E2E8F0', marginBottom: 8 },
  settingInfo: { flex: 1 },
  settingLabel: { fontSize: 14, fontWeight: '600', color: '#334155' },
  settingValue: { fontSize: 13, color: '#64748B', marginTop: 2 },
  settingRole: { fontSize: 12, fontWeight: '600', color: '#052E22', backgroundColor: '#ECFDF5', paddingHorizontal: 8, paddingVertical: 4, borderRadius: 999 },
  logoutBtn: { marginTop: 16, paddingVertical: 14, backgroundColor: '#FEF2F2', borderRadius: 10, alignItems: 'center', borderWidth: 1, borderColor: '#FECACA' },
  logoutText: { color: '#DC2626', fontWeight: '700', fontSize: 16 },
  testBtn: { marginTop: 12, paddingVertical: 12, backgroundColor: '#052E22', borderRadius: 8, alignItems: 'center' },
  testBtnText: { color: 'white', fontWeight: '700' },
});

export default SettingsScreen;