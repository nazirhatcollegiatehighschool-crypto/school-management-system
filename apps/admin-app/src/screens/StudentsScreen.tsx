import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, TextInput, StyleSheet, SafeAreaView, ScrollView, FlatList, ActivityIndicator, Alert, Modal } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import ApiClient from '../services/api';

interface Student {
  id: number;
  student_code: string;
  name: string;
  roll: number;
  class_name?: string;
  section?: string;
  guardian_name?: string;
  guardian_phone?: string;
}

export const StudentsScreen: React.FC = () => {
  const navigation = useNavigation();
  const [students, setStudents] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [search, setSearch] = useState('');
  const [modalVisible, setModalVisible] = useState(false);
  const [editingStudent, setEditingStudent] = useState<any>(null);
  const [formData, setFormData] = useState({
    student_code: '', name: '', roll: '', class_id: '', section: '',
    guardian_name: '', guardian_phone: '', guardian_email: '',
    father_name: '', mother_name: '', dob: '', gender: '', religion: '',
    blood_group: '', address: '', phone: '', email: '',
  });

  const loadStudents = async () => {
    try {
      const data = await ApiClient.get('/admin/students');
      setStudents(Array.isArray(data) ? data : data.students || []);
    } catch (e) {
      console.error('Failed to load students:', e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const loadClasses = async () => {
    try {
      const data = await ApiClient.get('/admin/classes');
      return Array.isArray(data) ? data : data.classes || [];
    } catch (e) {
      return [];
    }
  };

  const onRefresh = async () => {
    const data = await fetch('https://school-management-system-5jqj.onrender.com/api/admin/students', {
      headers: { Authorization: `Bearer ${localStorage.getItem('auth_token')}` }
    }).then(r => r.json());
    setStudents(Array.isArray(data) ? data : data.students || []);
    setRefreshing(false);
  };

  const openAddModal = () => {
    setEditingStudent(null);
    setFormData({
      student_code: '', name: '', roll: '', class_id: '', section: '',
      guardian_name: '', guardian_phone: '', guardian_email: '',
      father_name: '', mother_name: '', dob: '', gender: '', religion: '',
      blood_group: '', address: '', phone: '', email: '',
    });
    setModalVisible(true);
  };

  const openEditModal = (student: any) => {
    setEditingStudent(student);
    setFormData({
      student_code: student.student_code || '',
      name: student.name || '',
      roll: student.roll || '',
      class_id: student.class_id || '',
      section: student.section || '',
      guardian_name: student.guardian_name || '',
      guardian_phone: student.guardian_phone || '',
      guardian_email: student.guardian_email || '',
      father_name: student.father_name || '',
      mother_name: student.mother_name || '',
      dob: student.dob ? student.dob.split('T')[0] : '',
      gender: student.gender || '',
      religion: student.religion || '',
      blood_group: student.blood_group || '',
      address: student.address || '',
      phone: student.phone || '',
      email: student.email || '',
    });
    setModalVisible(true);
  };

  const handleSubmit = async () => {
    try {
      const url = editingStudent 
        ? `https://school-management-system-5jqj.onrender.com/api/admin/students/${editingStudent.id}`
        : 'https://school-management-system-5jqj.onrender.com/api/admin/students';
      const method = editingStudent ? 'PUT' : 'POST';
      
      const res = await fetch(`https://school-management-system-5jqj.onrender.com/api/admin/students${editingStudent ? `/${editingStudent.id}` : ''}`, {
        method,
        headers: { 
          'Content-Type': 'application/json',
          Authorization: `Bearer ${localStorage.getItem('auth_token')}`
        },
        body: JSON.stringify(formData)
      });
      
      if (res.ok) {
        setModalVisible(false);
        loadStudents();
        Alert.alert('Success', editingStudent ? 'Student updated' : 'Student added');
      } else {
        const err = await res.json();
        Alert.alert('Error', err.error || 'Failed to save');
      }
    } catch (e) {
      Alert.alert('Error', 'Failed to save student');
    }
  };

  const handleDelete = async (id: number) => {
    Alert.alert('Delete Student', 'Are you sure?', [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Delete', style: 'destructive', onPress: async () => {
        try {
          await fetch(`https://school-management-system-5jqj.onrender.com/api/admin/students/${id}`, {
            method: 'DELETE',
            headers: { Authorization: `Bearer ${localStorage.getItem('auth_token')}` }
          });
          loadStudents();
        } catch (e) {
          Alert.alert('Error', 'Failed to delete');
        }
      }}
    ]);
  };

  const filteredStudents = students.filter(s => 
    s.name?.toLowerCase().includes(search.toLowerCase()) ||
    s.student_code?.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Students</Text>
        <TouchableOpacity onPress={openAddModal} style={styles.addBtn}>
          <Text style={styles.addBtnText}>+ Add Student</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.searchContainer}>
        <TextInput
          style={styles.searchInput}
          placeholder="Search by name or code..."
          value={search}
          onChangeText={setSearch}
          placeholderTextColor="#94A3B8"
        />
      </View>

      <FlatList
        data={filteredStudents}
        keyExtractor={(item) => item.id.toString()}
        renderItem={({ item }) => (
          <TouchableOpacity style={styles.studentCard} onPress={() => openEditModal(item)}>
            <View style={styles.studentInfo}>
              <Text style={styles.studentName}>{item.name}</Text>
              <Text style={styles.studentCode}>Code: {item.student_code} • Roll: {item.roll}</Text>
              <Text style={styles.studentClass}>{item.class_name} {item.section || ''}</Text>
            </View>
            <View style={styles.cardActions}>
              <TouchableOpacity onPress={() => openEditModal(item)} style={styles.actionBtn}>
                <Text style={styles.actionBtnText}>Edit</Text>
              </TouchableOpacity>
              <TouchableOpacity onPress={() => handleDelete(item.id)} style={[styles.actionBtn, styles.deleteBtn]}>
                <Text style={styles.deleteBtnText}>Delete</Text>
              </TouchableOpacity>
            </View>
          </TouchableOpacity>
        )}
        keyExtractor={(item) => item.id.toString()}
        ListEmptyComponent={
          <View style={styles.emptyState}>
            <Text style={styles.emptyText}>No students found</Text>
          </View>
        }
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} colors={['#052E22']} />
        }
      />

      <Modal visible={modalVisible} animationType="slide" transparent={true} onRequestClose={() => setModalVisible(false)}>
        <View style={styles.modalOverlay} onTouchStart={() => setModalVisible(false)}>
          <View style={styles.modalContainer} onTouchStart={() => {}}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>{editingStudent ? 'Edit Student' : 'Add Student'}</Text>
              <TouchableOpacity onPress={() => setModalVisible(false)} style={styles.closeBtn}>
                <Text style={styles.closeBtnText}>✕</Text>
              </TouchableOpacity>
            </View>
            <ScrollView contentContainerStyle={styles.modalContent}>
              <View style={styles.formGroup}>
                <Text style={styles.formLabel}>Student Code</Text>
                <TextInput style={styles.formInput} value={formData.student_code} onChangeText={t => setFormData({...formData, student_code: t})} placeholder="2026-10-001" />
              </View>
              <View style={styles.formGroup}>
                <Text style={styles.formLabel}>Name</Text>
                <TextInput style={styles.formInput} value={formData.name} onChangeText={t => setFormData({...formData, name: t})} placeholder="Full Name" />
              </View>
              <View style={styles.formGroup}>
                <Text style={styles.formLabel}>Roll</Text>
                <TextInput style={styles.formInput} value={formData.roll} onChangeText={t => setFormData({...formData, roll: t})} placeholder="1" keyboardType="numeric" />
              </View>
              <View style={styles.formGroup}>
                <Text style={styles.formLabel}>Class ID</Text>
                <TextInput style={styles.formInput} value={formData.class_id} onChangeText={t => setFormData({...formData, class_id: t})} placeholder="15" keyboardType="numeric" />
              </View>
              <View style={styles.formGroup}>
                <Text style={styles.formLabel}>Section</Text>
                <TextInput style={styles.formInput} value={formData.section} onChangeText={t => setFormData({...formData, section: t})} placeholder="Arts" />
              </View>
              <View style={styles.formGroup}>
                <Text style={styles.formLabel}>Guardian Name</Text>
                <TextInput style={styles.formInput} value={formData.guardian_name} onChangeText={t => setFormData({...formData, guardian_name: t})} placeholder="Guardian Name" />
              </View>
              <View style={styles.formGroup}>
                <Text style={styles.formLabel}>Guardian Phone</Text>
                <TextInput style={styles.formInput} value={formData.guardian_phone} onChangeText={t => setFormData({...formData, guardian_phone: t})} placeholder="01XXXXXXXXX" keyboardType="phone-pad" />
              </View>
              <View style={styles.formGroup}>
                <Text style={styles.formLabel}>Father Name</Text>
                <TextInput style={styles.formInput} value={formData.father_name} onChangeText={t => setFormData({...formData, father_name: t})} placeholder="Father Name" />
              </View>
              <View style={styles.formGroup}>
                <Text style={styles.formLabel}>Mother Name</Text>
                <TextInput style={styles.formInput} value={formData.mother_name} onChangeText={t => setFormData({...formData, mother_name: t})} placeholder="Mother Name" />
              </View>
              <View style={styles.formGroup}>
                <Text style={styles.formLabel}>Date of Birth</Text>
                <TextInput style={styles.formInput} value={formData.dob} onChangeText={t => setFormData({...formData, dob: t})} placeholder="YYYY-MM-DD" />
              </View>
              <View style={styles.formGroup}>
                <Text style={styles.formLabel}>Gender</Text>
                <TextInput style={styles.formInput} value={formData.gender} onChangeText={t => setFormData({...formData, gender: t})} placeholder="Male/Female" />
              </View>
              <View style={styles.formGroup}>
                <Text style={styles.formLabel}>Religion</Text>
                <TextInput style={styles.formInput} value={formData.religion} onChangeText={t => setFormData({...formData, religion: t})} placeholder="Islam" />
              </View>
              <View style={styles.formGroup}>
                <Text style={styles.formLabel}>Address</Text>
                <TextInput style={styles.formInput} value={formData.address} onChangeText={t => setFormData({...formData, address: t})} placeholder="Home Address" multiline numberOfLines={2} />
              </View>
            </ScrollView>
            <View style={styles.modalActions}>
              <TouchableOpacity onPress={() => setModalVisible(false)} style={styles.cancelBtn}>
                <Text style={styles.cancelBtnText}>Cancel</Text>
              </TouchableOpacity>
              <TouchableOpacity onPress={handleSubmit} style={styles.saveBtn}>
                <Text style={styles.saveBtnText}>{editingStudent ? 'Update' : 'Save'}</Text>
              </TouchableOpacity>
            </View>
          </View>
        </Modal>
      </SafeAreaView>
    );
  };

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#F8FAFC' },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12, backgroundColor: 'white', borderBottomWidth: 1, borderColor: '#E2E8F0' },
  headerTitle: { fontSize: 18, fontWeight: '800', color: '#0F172A' },
  addBtn: { backgroundColor: '#052E22', paddingHorizontal: 16, paddingVertical: 8, borderRadius: 8 },
  addBtnText: { color: 'white', fontWeight: '700', fontSize: 14 },
  searchContainer: { paddingHorizontal: 16, paddingVertical: 12 },
  searchInput: { backgroundColor: 'white', borderWidth: 1, borderColor: '#E2E8F0', borderRadius: 8, padding: 12, fontSize: 16 },
  studentCard: { backgroundColor: 'white', padding: 16, marginHorizontal: 16, marginBottom: 10, borderRadius: 12, borderWidth: 1, borderColor: '#E2E8F0', shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.05, shadowRadius: 8, elevation: 2 },
  studentInfo: { flex: 1 },
  studentName: { fontSize: 16, fontWeight: '700', color: '#0F172A' },
  studentCode: { fontSize: 12, color: '#64748B', marginTop: 2 },
  studentClass: { fontSize: 12, color: '#052E22', fontWeight: '600', marginTop: 2 },
  cardActions: { flexDirection: 'row', gap: 8, marginTop: 12 },
  actionBtn: { flex: 1, paddingVertical: 8, paddingHorizontal: 12, borderRadius: 8, backgroundColor: '#052E22', alignItems: 'center' },
  actionBtnText: { color: 'white', fontWeight: '700', fontSize: 12 },
  deleteBtn: { backgroundColor: '#DC2626' },
  deleteBtnText: { color: 'white', fontWeight: '700', fontSize: 12 },
  emptyState: { flex: 1, justifyContent: 'center', alignItems: 'center', marginTop: 50 },
  emptyText: { fontSize: 16, color: '#94A3B8' },
  modalOverlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.5)', justifyContent: 'center', paddingHorizontal: 16 },
  modalContainer: { backgroundColor: 'white', borderRadius: 16, maxHeight: '90%', width: '100%' },
  modalHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', padding: 16, borderBottomWidth: 1, borderColor: '#E2E8F0' },
  modalTitle: { fontSize: 18, fontWeight: '800', color: '#0F172A' },
  closeBtn: { padding: 8 },
  closeBtnText: { fontSize: 20, fontWeight: '700', color: '#64748B' },
  modalContent: { padding: 16, maxHeight: 400 },
  formGroup: { marginBottom: 16 },
  formLabel: { fontSize: 13, fontWeight: '600', color: '#334155', marginBottom: 6 },
  formInput: { backgroundColor: 'white', borderWidth: 1, borderColor: '#E2E8F0', borderRadius: 8, padding: 12, fontSize: 16 },
  modalActions: { flexDirection: 'row', justifyContent: 'flex-end', gap: 12, padding: 16, borderTopWidth: 1, borderColor: '#E2E8F0' },
  cancelBtn: { paddingHorizontal: 20, paddingVertical: 10, borderRadius: 8, borderWidth: 1, borderColor: '#E2E8F0' },
  cancelBtnText: { color: '#64748B', fontWeight: '700' },
  saveBtn: { backgroundColor: '#052E22', paddingHorizontal: 20, paddingVertical: 10, borderRadius: 8 },
  saveBtnText: { color: 'white', fontWeight: '700' },
});

export default StudentsScreen;