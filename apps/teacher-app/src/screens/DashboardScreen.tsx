import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, SafeAreaView, ScrollView, FlatList, Alert, Modal, TextInput } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import ApiClient from '../services/api';

export const DashboardScreen: React.FC = () => {
  const navigation = useNavigation();
  const { user, logout } = useAuth();
  const [exams, setExams] = useState<any[]>([]);
  const [events, setEvents] = useState<any[]>([]);
  const [routine, setRoutine] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const loadData = async () => {
    try {
      const [examsRes, eventsRes, routineRes] = await Promise.all([
        ApiClient.get('/teacher/exams'),
        ApiClient.get('/teacher/events'),
        ApiClient.get('/routine/teacher/mine'),
      ]);
      setExams(Array.isArray(examsRes) ? examsRes : examsRes.exams || []);
      setEvents(Array.isArray(eventsRes) ? eventsRes : eventsRes.events || []);
      setRoutine(Array.isArray(routineRes) ? routineRes : routineRes.routine || []);
    } catch (e) {
      console.error('Failed to load data:', e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const onRefresh = async () => {
    await loadData();
  };

  const handleLogout = () => {
    Alert.alert('Sign Out', 'Are you sure you want to log out?', [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Logout', style: 'destructive', onPress: () => logout() },
    ]);
  };

  const myPending = exams.filter((e: any) => 
    (e.status === 'draft' || e.status === 'submitted') && e.subject_mine
  );

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Teacher Dashboard</Text>
        <TouchableOpacity onPress={handleLogout} style={styles.logoutBtn}>
          <Text style={styles.logoutText}>Logout</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.heroCard}>
        <Text style={styles.greeting}>Good Morning!</Text>
        <Text style={styles.teacherName}>{user?.name || 'Teacher'}</Text>
        <Text style={styles.subText}>Liakat Hossain Jewel • Class Teacher</Text>
        <View style={styles.statsRow}>
          <View style={styles.statBox}>
            <Text style={styles.statLabel}>Pending Entry</Text>
            <Text style={styles.statValue}>{myPending.length}</Text>
          </View>
          <View style={styles.statBox}>
            <Text style={styles.statLabel}>My Classes</Text>
            <Text style={styles.statValue}>5</Text>
          </View>
          <View style={styles.statBox}>
            <Text style={styles.statLabel}>Today's Periods</Text>
            <Text style={styles.statValue}>{routine.length}</Text>
          </View>
        </View>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Quick Actions</Text>
        <View style={styles.actionGrid}>
          <TouchableOpacity style={[styles.actionCard, { borderColor: '#0D9488' }]} onPress={() => navigation.navigate('Attendance')}>
            <View style={{ backgroundColor: '#0D948820' }}><Text style={{ fontSize: 24 }}>📋</Text></View>
            <Text style={{ color: '#0D9488', fontWeight: '700' }}>Attendance</Text>
            <Text style={styles.actionSub}>10:15-11:10 AM</Text>
          </TouchableOpacity>
          <TouchableOpacity style={[styles.actionCard, { borderColor: '#F59E0B' }]} onPress={() => navigation.navigate('Exams')}>
            <View style={{ backgroundColor: '#F59E0B20' }}><Text style={{ fontSize: 24 }}>📝</Text></View>
            <Text style={{ color: '#F59E0B', fontWeight: '700' }}>Exams</Text>
            <Text style={styles.actionSub}>{myPending.length} pending</Text>
          </TouchableOpacity>
          <TouchableOpacity style={[styles.actionCard, { borderColor: '#8B5CF6' }]} onPress={() => navigation.navigate('Homework')}>
            <View style={{ backgroundColor: '#8B5CF620' }}><Text style={{ fontSize: 24 }}>📚</Text></View>
            <Text style={{ color: '#8B5CF6', fontWeight: '700' }}>Homework</Text>
            <Text style={styles.actionSub}>Assign & Track</Text>
          </TouchableOpacity>
          <TouchableOpacity style={[styles.actionCard, { borderColor: '#3B82F6' }]} onPress={() => navigation.navigate('Routine')}>
            <View style={{ backgroundColor: '#3B82F620' }}><Text style={{ fontSize: 24 }}>📅</Text></View>
            <Text style={{ color: '#3B82F6', fontWeight: '700' }}>Routine</Text>
            <Text style={styles.actionSub}>My Schedule</Text>
          </TouchableOpacity>
        </View>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Today's Routine</Text>
        <FlatList
          data={routine.slice(0, 5)}
          keyExtractor={(item) => item.id.toString()}
          renderItem={({ item }) => (
            <TouchableOpacity style={styles.routineItem}>
              <View style={styles.routineTime}>
                <Text style={styles.routineSlot}>{item.slot_label}</Text>
                <Text style={styles.routineSubject}>{item.subject_name}</Text>
              </View>
              <View style={styles.routineDetails}>
                <Text style={styles.routineClass}>{item.class_name}</Text>
                <Text style={styles.teacherName}>{item.teacher_name}</Text>
              </View>
            </TouchableOpacity>
          )}
        keyExtractor={(item) => item.id.toString()}
        ListEmptyComponent={<Text style={styles.emptyText}>No routine today</Text>}
        />
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Marking Tasks</Text>
        {myPending.length === 0 ? (
          <Text style={styles.emptyText}>All entries complete ✓</Text>
        ) : (
          <FlatList
            data={myPending}
            keyExtractor={(item) => item.id.toString()}
            renderItem={({ item }) => (
              <TouchableOpacity style={styles.taskCard} onPress={() => navigation.navigate('ExamDetail', { examId: item.id })}>
                <View style={styles.taskInfo}>
                  <Text style={styles.taskName}>{item.name}</Text>
                  <Text style={styles.taskDetails}>{item.subject_name} • {item.class_name}</Text>
                  <Text style={[styles.taskStatus, { color: item.entry_open ? '#D97706' : '#DC2626' }]}>
                    {item.entry_open ? 'Entry Open' : 'Entry Closed'}
                  </Text>
                </View>
              </TouchableOpacity>
            )}
            keyExtractor={(item) => item.id.toString()}
          />
        )}
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Running Events</Text>
        <FlatList
          data={events}
          keyExtractor={(item) => item.id.toString()}
          renderItem={({ item }) => (
            <TouchableOpacity style={styles.eventCard}>
              <Text style={styles.eventName}>{item.name}</Text>
              <Text style={styles.eventDetails}>{item.year ? `${item.year} • ` : ''}{item.event_kind}</Text>
            </TouchableOpacity>
          )}
          keyExtractor={(item) => item.id.toString()}
          ListEmptyComponent={<Text style={styles.emptyText}>No running events</Text>}
        />
      </View>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f5f5f5' },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12, backgroundColor: 'white', borderBottomWidth: 1, borderColor: '#E2E8F0' },
  headerTitle: { fontSize: 18, fontWeight: '800', color: '#0F172A' },
  logoutBtn: { padding: 8 },
  logoutText: { color: '#DC2626', fontWeight: '700', fontSize: 14 },
  heroCard: { backgroundColor: '#052E22', marginHorizontal: 16, marginTop: 16, marginBottom: 12, borderRadius: 16, padding: 20 },
  greeting: { fontSize: 14, color: 'rgba(255,255,255,0.8)', marginBottom: 4 },
  teacherName: { fontSize: 22, fontWeight: '800', color: 'white' },
  subText: { fontSize: 13, color: 'rgba(255,255,255,0.8)', marginTop: 2 },
  statsRow: { flexDirection: 'row', justifyContent: 'space-around', marginTop: 16 },
  statBox: { alignItems: 'center' },
  statLabel: { fontSize: 11, color: 'rgba(255,255,255,0.8)' },
  statValue: { fontSize: 20, fontWeight: '800', color: 'white' },
  section: { paddingHorizontal: 16, marginBottom: 16 },
  sectionTitle: { fontSize: 16, fontWeight: '800', color: '#0F172A', marginBottom: 12 },
  actionGrid: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between', gap: 10 },
  actionCard: { width: '48%', aspectRatio: 1.2, backgroundColor: 'white', borderRadius: 12, padding: 16, borderWidth: 1, alignItems: 'center', justifyContent: 'center' },
  actionSub: { fontSize: 11, color: '#64748B', marginTop: 4 },
  routineItem: { backgroundColor: 'white', padding: 16, marginHorizontal: 16, marginBottom: 10, borderRadius: 12, borderWidth: 1, borderColor: '#E2E8F0', flexDirection: 'row', justifyContent: 'space-between' },
  routineTime: { flex: 1 },
  routineSlot: { fontSize: 12, color: '#64748B' },
  routineSubject: { fontSize: 16, fontWeight: '700', color: '#0F172A', marginTop: 4 },
  routineDetails: { alignItems: 'flex-end' },
  routineClass: { fontSize: 13, color: '#64748B' },
  teacherName: { fontSize: 12, color: '#94A3B8' },
  taskCard: { backgroundColor: '#FFF7ED', padding: 16, marginHorizontal: 16, marginBottom: 10, borderRadius: 12, borderWidth: 1, borderColor: '#FED7AA' },
  taskName: { fontSize: 16, fontWeight: '700', color: '#0F172A' },
  taskDetails: { fontSize: 12, color: '#64748B', marginTop: 2 },
  taskStatus: { fontSize: 11, fontWeight: '600', marginTop: 4 },
  eventCard: { backgroundColor: 'white', padding: 16, marginHorizontal: 16, marginBottom: 10, borderRadius: 12, borderWidth: 1, borderColor: '#E2E8F0' },
  eventName: { fontSize: 16, fontWeight: '700', color: '#0F172A' },
  eventDetails: { fontSize: 12, color: '#64748B', marginTop: 4 },
  emptyText: { fontSize: 13, color: '#94A3B8', textAlign: 'center', marginVertical: 16 },
});

export default DashboardScreen;