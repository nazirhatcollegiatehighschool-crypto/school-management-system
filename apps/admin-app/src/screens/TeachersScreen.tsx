import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, SafeAreaView, ScrollView, FlatList, Modal, TextInput, Alert } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import ApiClient from '../services/api';

interface Teacher {
  id: number;
  username: string;
  name: string;
  email?: string;
  phone?: string;
  designation?: string;
  active: number;
  is_class_teacher?: string;
}

export const TeachersScreen: React.FC = () => {
  const navigation = useNavigation();
  const [teachers, setTeachers] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [search, setSearch] = useState('');
  const [modalVisible, setModalVisible] = useState(false);
  const [editingTeacher, setEditingTeacher] = useState<any>(null);
  const [formData, setFormData] = useState({
    username: '', name: '', email: '', phone: '', designation: '', role: 'teacher', password: '',
  });

  const loadTeachers = async () => {
    try {
      const data = await ApiClient.get('/admin/teachers');
      setTeachers(Array.isArray(data) ? data : data.teachers || []);
    } catch (e) {
      console.error('Failed to load teachers:', e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const onRefresh = async () => {
    await loadTeachers();
  };

  const openAddModal = () => {
    setEditingTeacher(null);
    setFormData({ username: '', name: '', email: '', phone: '', designation: '', role: 'teacher', password: '' });
    setModalVisible(true);
  };

  const openEditModal = (teacher: any) => {
    setEditingTeacher(teacher);
    setFormData({
      username: teacher.username || '',
      name: teacher.name || '',
      email: teacher.email || '',
      phone: teacher.phone || '',
      designation: teacher.designation || '',
      role: teacher.role || 'teacher',
      password: '',
    });
    setModalVisible(true);
  };

  const handleSubmit = async () => {
    try {
      const url = editingTeacher 
        ? `https://school-management-system-5jqj.onrender.com/api/admin/teachers/${editingTeacher.id}`
        : 'https://school-management-system-5jqj.onrender.com/api/admin/teachers';
      const method = editingTeacher ? 'PUT' : 'POST';
      
      const res = await fetch(`https://school-management-system-5jqj.onrender.com/api/admin/teachers${editingTeacher ? `/${editingTeacher.id}` : ''}`, {
        method,
        headers: { 
          'Content-Type': 'application/json',
          Authorization: `Bearer ${localStorage.getItem('auth_token')}`
        },
        body: JSON.stringify(formData)
      });
      
      if (res.ok) {
        setModalVisible(false);
        loadTeachers();
        Alert.alert('Success', editingTeacher ? 'Teacher updated' : 'Teacher added');
      } else {
        const err = await res.json();
        Alert.alert('Error', err.error || 'Failed to save');
      }
    } catch (e) {
      Alert.alert('Error', 'Failed to save teacher');
    }
  };

  const handleDelete = async (id: number) => {
    Alert.alert('Delete Teacher', 'Are you sure?', [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Delete', style: 'destructive', onPress: async () => {
        try {
          await fetch(`https://school-management-system-5jqj.onrender.com/api/admin/teachers/${id}`, {
            method: 'DELETE',
            headers: { Authorization: `Bearer ${localStorage.getItem('auth_token')}` }
          });
          loadTeachers();
        } catch (e) {
          Alert.alert('Error', 'Failed to delete');
        }
      }}
    ]);
  };

  const filteredTeachers = teachers.filter(t => 
    t.name?.toLowerCase().includes(search.toLowerCase()) ||
    t.username?.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Teachers</Text>
        <TouchableOpacity onPress={openAddModal} style={styles.addBtn}>
          <Text style={styles.addBtnText}>+ Add Teacher</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.searchContainer}>
        <TextInput
          style={styles.searchInput}
          placeholder="Search by name or username..."
          value={search}
          onChangeText={setSearch}
          placeholderTextColor="#94A3B8"
        />
      </View>

      <FlatList
        data={teachers.filter(t => 
          t.name?.toLowerCase().includes(search.toLowerCase()) ||
          t.username?.toLowerCase().includes(search.toLowerCase())
        )}
        keyExtractor={(item) => item.id.toString()}
        renderItem={({ item }) => (
          <TouchableOpacity style={styles.teacherCard} onPress={() => openEditModal(item)}>
            <View style={styles.teacherInfo}>
              <Text style={styles.teacherName}>{item.name}</Text>
              <Text style={styles.teacherCode}>@{item.username} • {item.designation || 'Teacher'}</Text>
              <Text style={styles.teacherClass}>{item.email || ''} • {item.phone || ''}</Text>
            </View>
            <View style={styles.cardActions}>
              <TouchableOpacity onPress={() => openEditModal(item)} style={styles.actionBtn}>
                <Text style={styles.actionBtnText}>Edit</Text>
              </TouchableOpacity>
              <TouchableOpacity onPress={() => Alert.alert('Delete Teacher', 'Are you sure?', [
                { text: 'Cancel', style: 'cancel' },
                { text: 'Delete', style: 'destructive', onPress: async () => {
                  try {
                    await fetch(`https://school-management-system-5jqj.onrender.com/api/admin/teachers/${item.id}`, {
                      method: 'DELETE',
                      headers: { Authorization: `Bearer ${localStorage.getItem('auth_token')}` }
                    });
                    Alert.alert('Success', 'Teacher deleted');
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
        ListEmptyComponent={<View style={styles.emptyState}><Text style={styles.emptyText}>No teachers found</Text></View>}
        refreshControl={<RefreshControl refreshing={false} onRefresh={async () => {}} colors={['#052E22']} />
      />
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#F8FAFC' },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12, backgroundColor: 'white', borderBottomWidth: 1, borderColor: '#E2E8F0' },
  headerTitle: { fontSize: 18, fontWeight: '800', color: '#0F172A' },
  addBtn: { backgroundColor: '#0D9488', paddingHorizontal: 16, paddingVertical: 8, borderRadius: 8 },
  addBtnText: { color: 'white', fontWeight: '700', fontSize: 14 },
  searchContainer: { paddingHorizontal: 16, paddingVertical: 12 },
  searchInput: { backgroundColor: 'white', borderWidth: 1, borderColor: '#E2E8F0', borderRadius: 8, padding: 12, fontSize: 16 },
  teacherCard: { backgroundColor: 'white', padding: 16, marginHorizontal: 16, marginBottom: 10, borderRadius: 12, borderWidth: 1, borderColor: '#E2E8F0', shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.05, shadowRadius: 8, elevation: 2 },
  teacherInfo: { flex: 1 },
  teacherName: { fontSize: 16, fontWeight: '700', color: '#0F172A' },
  teacherCode: { fontSize: 12, color: '#64748B', marginTop: 2 },
  teacherClass: { fontSize: 12, color: '#0D9488', fontWeight: '600', marginTop: 2 },
  cardActions: { flexDirection: 'row', gap: 8, marginTop: 12 },
  actionBtn: { flex: 1, paddingVertical: 8, paddingHorizontal: 12, borderRadius: 8, backgroundColor: '#0D9488', alignItems: 'center' },
  actionBtnText: { color: 'white', fontWeight: '700', fontSize: 12 },
  deleteBtn: { backgroundColor: '#DC2626' },
  deleteBtnText: { color: 'white', fontWeight: '700', fontSize: 12 },
  emptyState: { flex: 1, justifyContent: 'center', alignItems: 'center', marginTop: 50 },
  emptyText: { fontSize: 16, color: '#94A3B8' },
});

export default TeachersScreen;