import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, SafeAreaView, ScrollView, FlatList, Alert } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import ApiClient from '../services/api';

export const RoutinesScreen: React.FC = () => {
  const [routines, setRoutines] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [search, setSearch] = useState('');

  const loadRoutines = async () => {
    try {
      const data = await ApiClient.get('/admin/routines');
      setRoutines(Array.isArray(data) ? data : data.routines || []);
    } catch (e) {
      console.error('Failed to load routines:', e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const onRefresh = async () => {
    const data = await fetch('https://school-management-system-5jqj.onrender.com/api/admin/routines', {
      headers: { Authorization: `Bearer ${localStorage.getItem('auth_token')}` }
    }).then(r => r.json());
    setRoutines(Array.isArray(data) ? data : data.routines || []);
    setRefreshing(false);
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Routines</Text>
        <TouchableOpacity style={styles.addBtn}>
          <Text style={styles.addBtnText}>+ Add Routine</Text>
        </TouchableOpacity>
      </View>

      <FlatList
        data={routines.filter(r => r.subject_name?.toLowerCase().includes(search.toLowerCase()))}
        keyExtractor={(item) => item.id.toString()}
        renderItem={({ item }) => (
          <TouchableOpacity style={styles.routineCard}>
            <View style={styles.routineInfo}>
              <Text style={styles.routineSubject}>{item.subject_name}</Text>
              <Text style={styles.routineDetails}>
                {item.teacher_name} • {item.class_name} • {item.day_name} • {item.slot_label}
              </Text>
            </View>
          </TouchableOpacity>
        )}
        keyExtractor={(item) => item.id.toString()}
        ListEmptyComponent={<View style={styles.emptyState}><Text style={styles.emptyText}>No routines found</Text></View>}
        refreshControl={<RefreshControl refreshing={false} onRefresh={async () => {}} colors={['#16A34A']} />
      />
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#F8FAFC' },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12, backgroundColor: 'white', borderBottomWidth: 1, borderColor: '#E2E8F0' },
  headerTitle: { fontSize: 18, fontWeight: '800', color: '#0F172A' },
  addBtn: { backgroundColor: '#16A34A', paddingHorizontal: 16, paddingVertical: 8, borderRadius: 8 },
  addBtnText: { color: 'white', fontWeight: '700', fontSize: 14 },
  emptyState: { flex: 1, justifyContent: 'center', alignItems: 'center', marginTop: 50 },
  emptyText: { fontSize: 16, color: '#94A3B8' },
});

export default RoutinesScreen;