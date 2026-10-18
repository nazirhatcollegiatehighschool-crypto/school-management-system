import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, SafeAreaView, ScrollView, FlatList, Alert, Modal, TextInput } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import ApiClient from '../services/api';

interface Child {
  student: any;
  attendance_summary: any;
  recent_results: any[];
}

export const DashboardScreen: React.FC = () => {
  const navigation = useNavigation();
  const { user, logout } = useAuth();
  const [children, setChildren] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const loadChildren = async () => {
    try {
      const data = await ApiClient.get('/guardian/dashboard');
      setChildren(data.siblings || []);
    } catch (e) {
      console.error('Failed to load children:', e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const onRefresh = async () => {
    const data = await fetch('https://school-management-system-5jqj.onrender.com/api/guardian/dashboard', {
      headers: { Authorization: `Bearer ${localStorage.getItem('auth_token')}` }
    }).then(r => r.json());
    setChildren(data.siblings || []);
    setRefreshing(false);
  };

  const handleLogout = () => {
    Alert.alert('Sign Out', 'Are you sure you want to log out?', [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Logout', style: 'destructive', onPress: () => logout() },
    ]);
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>My Children</Text>
        <TouchableOpacity onPress={handleLogout} style={styles.logoutBtn}>
          <Text style={styles.logoutText}>Logout</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.profileCard}>
        <Text style={styles.guardianName}>👤 {user?.name || 'Guardian'}</Text>
        <Text style={styles.guardianPhone}>{user?.phone || ''}</Text>
      </View>

      <FlatList
        data={children}
        keyExtractor={(item) => item.student.id.toString()}
        renderItem={({ item }) => (
          <TouchableOpacity style={styles.childCard} onPress={() => {}}>
            <View style={styles.childInfo}>
              <Text style={styles.childName}>{item.student.name}</Text>
              <Text style={styles.childClass}>{item.student.class_name} {item.student.section || ''} • Roll: {item.student.roll}</Text>
              <View style={styles.childStats}>
                <Text style={styles.statItem}>
                  <Text style={styles.statLabel}>Attendance: </Text>
                  <Text style={styles.statValue}>{item.attendance_summary?.percentage || 0}%</Text>
                </Text>
                <Text style={styles.statItem}>
                  <Text style={styles.statLabel}>GPA: </Text>
                  <Text style={styles.statValue}>3.85</Text>
                </Text>
              </View>
            </View>
            <TouchableOpacity style={styles.viewDetailsBtn}>
              <Text style={styles.viewDetailsText}>View Details →</Text>
            </TouchableOpacity>
          </TouchableOpacity>
        )}
        keyExtractor={(item) => item.student.id.toString()}
        ListEmptyComponent={
          <View style={styles.emptyState}>
            <Text style={styles.emptyText}>No linked children found</Text>
            <TouchableOpacity style={styles.linkBtn}>
              <Text style={styles.linkBtnText}>Link Another Child</Text>
            </TouchableOpacity>
          </View>
        }
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={async () => {}} colors={['#052E22']} />
        }
      />
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f5f5f5' },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12, backgroundColor: 'white', borderBottomWidth: 1, borderColor: '#E2E8F0' },
  headerTitle: { fontSize: 18, fontWeight: '800', color: '#0F172A' },
  logoutBtn: { padding: 8 },
  logoutText: { color: '#DC2626', fontWeight: '700', fontSize: 14 },
  profileCard: { backgroundColor: 'white', marginHorizontal: 16, marginTop: 16, marginBottom: 12, borderRadius: 12, padding: 16, borderWidth: 1, borderColor: '#E2E8F0' },
  guardianName: { fontSize: 18, fontWeight: '700', color: '#0F172A' },
  guardianPhone: { fontSize: 14, color: '#64748B', marginTop: 4 },
  childCard: { backgroundColor: 'white', marginHorizontal: 16, marginBottom: 12, borderRadius: 12, padding: 16, borderWidth: 1, borderColor: '#E2E8F0', flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  childInfo: { flex: 1 },
  childName: { fontSize: 18, fontWeight: '800', color: '#0F172A' },
  childClass: { fontSize: 13, color: '#64748B', marginTop: 4 },
  childStats: { flexDirection: 'row', gap: 16, marginTop: 8 },
  statItem: { flexDirection: 'row', alignItems: 'baseline', gap: 4 },
  statLabel: { fontSize: 12, color: '#64748B' },
  statValue: { fontSize: 12, fontWeight: '700', color: '#052E22' },
  viewDetailsBtn: { paddingHorizontal: 12, paddingVertical: 6, backgroundColor: '#052E22', borderRadius: 8 },
  viewDetailsText: { color: 'white', fontWeight: '700', fontSize: 12 },
  emptyState: { alignItems: 'center', padding: 32, marginHorizontal: 16, marginTop: 20, borderRadius: 12, backgroundColor: 'white', borderWidth: 1, borderColor: '#E2E8F0' },
  emptyText: { fontSize: 16, color: '#94A3B8', marginBottom: 12 },
  linkBtn: { paddingHorizontal: 20, paddingVertical: 10, backgroundColor: '#052E22', borderRadius: 8 },
  linkBtnText: { color: 'white', fontWeight: '700' },
});

export default DashboardScreen;