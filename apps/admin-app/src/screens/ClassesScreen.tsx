import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, SafeAreaView, ScrollView, FlatList, Alert } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import ApiClient from '../services/api';

interface Class {
  id: number;
  name: string;
  section: string;
  group_name?: string;
  session_id?: number;
  teacher_id?: number;
}

export const ClassesScreen: React.FC = () => {
  const navigation = useNavigation();
  const [classes, setClasses] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [search, setSearch] = useState('');
  const [modalVisible, setModalVisible] = useState(false);
  const [editingClass, setEditingClass] = useState<any>(null);
  const [formData, setFormData] = useState({
    name: '', section: '', group_name: '', session_id: '', teacher_id: '',
  });

  const loadClasses = async () => {
    try {
      const data = await ApiClient.get('/admin/classes');
      setClasses(Array.isArray(data) ? data : data.classes || []);
    } catch (e) {
      console.error('Failed to load classes:', e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const onRefresh = async () => {
    const data = await fetch('https://school-management-system-5jqj.onrender.com/api/admin/classes', {
      headers: { Authorization: `Bearer ${localStorage.getItem('auth_token')}` }
    }).then(r => r.json());
    setClasses(Array.isArray(data) ? data : data.classes || []);
    setRefreshing(false);
  };

  const openAddModal = () => {
    setEditingClass(null);
    setFormData({ name: '', section: '', group_name: '', session_id: '', teacher_id: '' });
    setModalVisible(true);
  };

  const openEditModal = (cls: any) => {
    setEditingClass(cls);
    setFormData({ name: cls.name || '', section: cls.section || '', group_name: cls.group_name || '', session_id: cls.session_id || '', teacher_id: cls.teacher_id || '' });
    setModalVisible(true);
  };

  const handleSubmit = async () => {
    try {
      const url = editingClass 
        ? `https://school-management-system-5jqj.onrender.com/api/admin/classes/${editingClass.id}`
        : 'https://school-management-system-5jqj.onrender.com/api/admin/classes';
      const method = editingClass ? 'PUT' : 'POST';
      
      const res = await fetch(`https://school-management-system-5jqj.onrender.com/api/admin/classes${editingClass ? `/${editingClass.id}` : ''}`, {
        method: editingClass ? 'PUT' : 'POST',
        headers: { 
          'Content-Type': 'application/json',
          Authorization: `Bearer ${localStorage.getItem('auth_token')}`
        },
        body: JSON.stringify(formData)
      });
      
      if (res.ok) {
        setModalVisible(false);
        loadClasses();
        Alert.alert('Success', editingClass ? 'Class updated' : 'Class added');
      } else {
        const err = await res.json();
        Alert.alert('Error', err.error || 'Failed to save');
      }
    } catch (e) {
      Alert.alert('Error', 'Failed to save class');
    }
  };

  const handleDelete = async (id: number) => {
    Alert.alert('Delete Class', 'Are you sure?', [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Delete', style: 'destructive', onPress: async () => {
        try {
          await fetch(`https://school-management-system-5jqj.onrender.com/api/admin/classes/${editingClass.id}`, {
            method: 'DELETE',
            headers: { Authorization: `Bearer ${localStorage.getItem('auth_token')}` }
          });
          loadClasses();
        } catch (e) {
          Alert.alert('Error', 'Failed to delete');
        }
      }}
    ]);
  });

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Classes</Text>
        <TouchableOpacity onPress={openAddModal} style={styles.addBtn}>
          <Text style={styles.addBtnText}>+ Add Class</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.searchContainer}>
        <TextInput
          style={styles.searchInput}
          placeholder="Search by name or section..."
          value={search}
          onChangeText={setSearch}
          placeholderTextColor="#94A3B8"
        />
      </View>

      <FlatList
        data={classes.filter(c => c.name?.toLowerCase().includes(search.toLowerCase()) || c.section?.toLowerCase().includes(search.toLowerCase()))}
        keyExtractor={(item) => item.id.toString()}
        renderItem={({ item }) => (
          <TouchableOpacity style={styles.classCard}>
            <View style={styles.classInfo}>
              <Text style={styles.className}>{item.name} {item.section}</Text>
              <Text style={styles.classCode}>{item.group_name ? `Group: ${item.group_name}` : ''} • Teacher ID: {item.teacher_id || 'N/A'}</Text>
            </View>
            <View style={styles.cardActions}>
              <TouchableOpacity onPress={() => openEditModal(item)} style={styles.actionBtn}>
                <Text style={styles.actionBtnText}>Edit</Text>
              </TouchableOpacity>
              <TouchableOpacity onPress={() => Alert.alert('Delete Class', 'Are you sure?', [
                { text: 'Cancel', style: 'cancel' },
                { text: 'Delete', style: 'destructive', onPress: async () => {
                  try {
                    await fetch(`https://school-management-system-5jqj.onrender.com/api/admin/classes/${item.id}`, {
                      method: 'DELETE',
                      headers: { Authorization: `Bearer ${localStorage.getItem('auth_token')}` }
                    });
                    Alert.alert('Success', 'Class deleted');
                  } catch (e) {
                    Alert.alert('Error', 'Failed to delete');
                  }
                }}
              ])} style={[styles.actionBtn, styles.deleteBtn]}>
                <Text style={styles.deleteBtnText}>Delete</Text>
              </TouchableOpacity>
            </View>
          </TouchableOpacity>
        )}
        keyExtractor={(item) => item.id.toString()}
        ListEmptyComponent={<View style={styles.emptyState}><Text style={styles.emptyText}>No classes found</Text></View>}
        refreshControl={<RefreshControl refreshing={false} onRefresh={async () => {}} colors={['#7C3AED']} />
      />
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#F8FAFC' },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12, backgroundColor: 'white', borderBottomWidth: 1, borderColor: '#E2E8F0' },
  headerTitle: { fontSize: 18, fontWeight: '800', color: '#0F172A' },
  addBtn: { backgroundColor: '#7C3AED', paddingHorizontal: 16, paddingVertical: 8, borderRadius: 8 },
  addBtnText: { color: 'white', fontWeight: '700', fontSize: 14 },
  searchContainer: { paddingHorizontal: 16, paddingVertical: 12 },
  searchInput: { backgroundColor: 'white', borderWidth: 1, borderColor: '#E2E8F0', borderRadius: 8, padding: 12, fontSize: 16 },
  emptyState: { flex: 1, justifyContent: 'center', alignItems: 'center', marginTop: 50 },
  emptyText: { fontSize: 16, color: '#94A3B8' },
});

export default ClassesScreen;