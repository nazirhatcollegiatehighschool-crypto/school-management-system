import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, SafeAreaView, ScrollView, FlatList, Alert } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import ApiClient from '../services/api';

export const PromotionScreen: React.FC = () => {
  const navigation = useNavigation();
  const [promotions, setPromotions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [search, setSearch] = useState('');

  const loadPromotions = async () => {
    try {
      const data = await ApiClient.get('/admin/promotions');
      setPromotions(Array.isArray(data) ? data : data.promotions || []);
    } catch (e) {
      console.error('Failed to load promotions:', e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const onRefresh = async () => {
    const data = await fetch('https://school-management-system-5jqj.onrender.com/api/admin/promotions', {
      headers: { Authorization: `Bearer ${localStorage.getItem('auth_token')}` }
    }).then(r => r.json());
    setPromotions(Array.isArray(data) ? data : data.promotions || []);
    setRefreshing(false);
  };

  const handlePromote = async (studentId: number) => {
    Alert.alert('Promote Student', 'Confirm promotion?', [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Promote', onPress: async () => {
        try {
          await fetch('https://school-management-system-5jqj.onrender.com/api/admin/promote', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${localStorage.getItem('auth_token')}` },
            body: JSON.stringify({ student_id: studentId })
          });
          Alert.alert('Success', 'Student promoted');
        } catch (e) {
          Alert.alert('Error', 'Failed to promote');
        }
      }}
    ]);
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Promotion → SSC</Text>
        <TouchableOpacity style={styles.addBtn}>
          <Text style={styles.addBtnText}>+ Run Promotion</Text>
        </TouchableOpacity>
      </View>

      <FlatList
        data={promotions.filter(p => p.student_name?.toLowerCase().includes(search.toLowerCase()))}
        keyExtractor={(item) => item.id.toString()}
        renderItem={({ item }) => (
          <TouchableOpacity style={styles.promoCard}>
            <View style={styles.promoInfo}>
              <Text style={styles.promoName}>{item.student_name || `Student ${item.student_id}`}</Text>
              <Text style={styles.promoClass}>{item.from_class} → {item.to_class}</Text>
              <Text style={[styles.promoStatus, { color: item.decision === 'promoted' ? '#16A34A' : '#DC2626' }]}>
                {item.decision?.toUpperCase() || 'PENDING'}
              </Text>
            </View>
            <TouchableOpacity onPress={() => handlePromote(item.student_id)} style={styles.promoBtn}>
              <Text style={styles.promoBtnText}>Promote</Text>
            </TouchableOpacity>
          </TouchableOpacity>
        )}
        keyExtractor={(item) => item.id.toString()}
        ListEmptyComponent={<View style={styles.emptyState}><Text style={styles.emptyText}>No promotions found</Text></View>}
        refreshControl={<RefreshControl refreshing={false} onRefresh={async () => {}} colors={['#4F46E5']} />
      />
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#F8FAFC' },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12, backgroundColor: 'white', borderBottomWidth: 1, borderColor: '#E2E8F0' },
  headerTitle: { fontSize: 18, fontWeight: '800', color: '#0F172A' },
  addBtn: { backgroundColor: '#4F46E5', paddingHorizontal: 16, paddingVertical: 8, borderRadius: 8 },
  addBtnText: { color: 'white', fontWeight: '700', fontSize: 14 },
  emptyState: { flex: 1, justifyContent: 'center', alignItems: 'center', marginTop: 50 },
  emptyText: { fontSize: 16, color: '#94A3B8' },
  promoCard: { backgroundColor: 'white', padding: 16, marginHorizontal: 16, marginBottom: 10, borderRadius: 12, borderWidth: 1, borderColor: '#E2E8F0', flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  promoInfo: { flex: 1 },
  promoName: { fontSize: 16, fontWeight: '700', color: '#0F172A' },
  promoClass: { fontSize: 12, color: '#64748B', marginTop: 2 },
  promoStatus: { fontSize: 12, fontWeight: '600', marginTop: 4 },
  promoBtn: { backgroundColor: '#4F46E5', paddingHorizontal: 16, paddingVertical: 8, borderRadius: 8 },
  promoBtnText: { color: 'white', fontWeight: '700', fontSize: 12 },
});

export default PromotionScreen;