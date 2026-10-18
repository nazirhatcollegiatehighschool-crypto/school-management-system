import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, SafeAreaView, ScrollView, FlatList, Modal, TextInput, Alert } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import ApiClient from '../services/api';

export const NoticesScreen: React.FC = () => {
  const [notices, setNotices] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [search, setSearch] = useState('');
  const [modalVisible, setModalVisible] = useState(false);
  const [formData, setFormData] = useState({
    title: '', body: '', type: 'notice', target_type: 'all', target_id: '',
  });

  const loadNotices = async () => {
    try {
      const data = await ApiClient.get('/admin/notices');
      setNotices(Array.isArray(data) ? data : data.notices || []);
    } catch (e) {
      console.error('Failed to load notices:', e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const onRefresh = async () => {
    const data = await fetch('https://school-management-system-5jqj.onrender.com/api/admin/notices', {
      headers: { Authorization: `Bearer ${localStorage.getItem('auth_token')}` }
    }).then(r => r.json());
    setNotices(Array.isArray(data) ? data : data.notices || []);
    setRefreshing(false);
  };

  const openAddModal = () => {
    setFormData({ title: '', body: '', type: 'notice', target_type: 'all', target_id: '' });
    setModalVisible(true);
  };

  const handleSubmit = async () => {
    try {
      const res = await fetch('https://school-management-system-5jqj.onrender.com/api/admin/notices', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${localStorage.getItem('auth_token')}` },
        body: JSON.stringify(formData)
      });
      if (res.ok) {
        setModalVisible(false);
        Alert.alert('Success', 'Notice sent');
      } else {
        Alert.alert('Error', 'Failed to send notice');
      }
    } catch (e) {
      Alert.alert('Error', 'Failed to send notice');
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Notices</Text>
        <TouchableOpacity onPress={openAddModal} style={styles.addBtn}>
          <Text style={styles.addBtnText}>+ Send Notice</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.searchContainer}>
        <TextInput
          style={styles.searchInput}
          placeholder="Search notices..."
          value={search}
          onChangeText={setSearch}
          placeholderTextColor="#94A3B8"
        />
      </View>

      <FlatList
        data={notices.filter(n => n.title?.toLowerCase().includes(search.toLowerCase()))}
        keyExtractor={(item) => item.id.toString()}
        renderItem={({ item }) => (
          <TouchableOpacity style={styles.noticeCard}>
            <View style={styles.noticeInfo}>
              <Text style={styles.noticeTitle}>{item.title}</Text>
              <Text style={styles.noticeBody}>{item.body}</Text>
              <Text style={styles.noticeMeta}>Type: {item.type} • Target: {item.target_type}</Text>
            </View>
          </TouchableOpacity>
        )}
        keyExtractor={(item) => item.id.toString()}
        ListEmptyComponent={<View style={styles.emptyState}><Text style={styles.emptyText}>No notices</Text></View>}
        refreshControl={<RefreshControl refreshing={false} onRefresh={async () => {}} colors={['#E11D48']} />
      />
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#F8FAFC' },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12, backgroundColor: 'white', borderBottomWidth: 1, borderColor: '#E2E8F0' },
  headerTitle: { fontSize: 18, fontWeight: '800', color: '#0F172A' },
  addBtn: { backgroundColor: '#E11D48', paddingHorizontal: 16, paddingVertical: 8, borderRadius: 8 },
  addBtnText: { color: 'white', fontWeight: '700', fontSize: 14 },
  emptyState: { flex: 1, justifyContent: 'center', alignItems: 'center', marginTop: 50 },
  emptyText: { fontSize: 16, color: '#94A3B8' },
});

export default NoticesScreen;