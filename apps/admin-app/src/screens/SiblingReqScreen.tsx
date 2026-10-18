import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, SafeAreaView, ScrollView, FlatList, Alert } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import ApiClient from '../services/api';

export const SiblingReqScreen: React.FC = () => {
  const [requests, setRequests] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const loadRequests = async () => {
    try {
      const data = await ApiClient.get('/admin/sibling-requests');
      setRequests(Array.isArray(data) ? data : data.requests || []);
    } catch (e) {
      console.error('Failed to load sibling requests:', e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const onRefresh = async () => {
    const data = await fetch('https://school-management-system-5jqj.onrender.com/api/admin/sibling-requests', {
      headers: { Authorization: `Bearer ${localStorage.getItem('auth_token')}` }
    }).then(r => r.json());
    setRequests(Array.isArray(data) ? data : data.requests || []);
    setRefreshing(false);
  };

  const handleAction = async (id: number, action: string) => {
    try {
      const res = await fetch(`https://school-management-system-5jqj.onrender.com/api/admin/sibling-requests/${id}/${action}`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${localStorage.getItem('auth_token')}` }
      });
      if (res.ok) {
        Alert.alert('Success', `Request ${action}d`);
        loadRequests();
      } else {
        Alert.alert('Error', 'Failed to process');
      }
    } catch (e) {
      Alert.alert('Error', 'Failed to process');
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Sibling Requests</Text>
      </View>

      <FlatList
        data={requests}
        keyExtractor={(item) => item.id.toString()}
        renderItem={({ item }) => (
          <TouchableOpacity style={styles.requestCard}>
            <View style={styles.requestInfo}>
              <Text style={styles.requestGuardian}>Guardian: {item.guardian_name}</Text>
              <Text style={styles.requestStudent}>Student: {item.student_name}</Text>
              <Text style={styles.requestStatus}>Status: {item.status?.toUpperCase() || 'PENDING'}</Text>
            </View>
            {item.status === 'pending' && (
              <View style={styles.requestActions}>
                <TouchableOpacity onPress={() => handleAction(item.id, 'approve')} style={styles.approveBtn}>
                  <Text style={styles.actionBtnText}>Approve</Text>
                </TouchableOpacity>
                <TouchableOpacity onPress={() => handleAction(item.id, 'reject')} style={[styles.actionBtn, styles.rejectBtn]}>
                  <Text style={styles.actionBtnText}>Reject</Text>
                </TouchableOpacity>
              </View>
            )}
          </TouchableOpacity>
        )}
        keyExtractor={(item) => item.id.toString()}
        ListEmptyComponent={<View style={styles.emptyState}><Text style={styles.emptyText}>No sibling requests</Text></View>}
        refreshControl={<RefreshControl refreshing={false} onRefresh={async () => {}} colors={['#0284C7']} />
      />
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#F8FAFC' },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12, backgroundColor: 'white', borderBottomWidth: 1, borderColor: '#E2E8F0' },
  headerTitle: { fontSize: 18, fontWeight: '800', color: '#0F172A' },
  emptyState: { flex: 1, justifyContent: 'center', alignItems: 'center', marginTop: 50 },
  emptyText: { fontSize: 16, color: '#94A3B8' },
  requestCard: { backgroundColor: 'white', padding: 16, marginHorizontal: 16, marginBottom: 10, borderRadius: 12, borderWidth: 1, borderColor: '#E2E8F0', flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  requestInfo: { flex: 1 },
  requestGuardian: { fontSize: 16, fontWeight: '700', color: '#0F172A' },
  requestStudent: { fontSize: 12, color: '#64748B', marginTop: 2 },
  requestStatus: { fontSize: 12, fontWeight: '600', color: '#0284C7', marginTop: 2 },
  requestActions: { flexDirection: 'row', gap: 8 },
});

export default SiblingReqScreen;