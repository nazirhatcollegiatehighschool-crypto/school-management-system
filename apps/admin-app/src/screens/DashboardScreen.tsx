import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, ActivityIndicator, StyleSheet, SafeAreaView, ScrollView, RefreshControl, GridView, FlatList, Alert } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useAuth } from '../context/AuthContext';
import ApiClient from '../services/api';

interface StatCardProps {
  label: string;
  value: number | string;
  icon: string;
  color: string;
  onPress?: () => void;
}

const StatCard: React.FC<StatCardProps> = ({ label, value, icon, color, onPress }) => (
  <TouchableOpacity style={[styles.statCard, { borderColor: color }]} onPress={onPress} activeOpacity={0.8}>
    <View style={[styles.statIcon, { backgroundColor: color + '20' }]}>
      <Text style={{ fontSize: 20 }}>{icon}</Text>
    </View>
    <Text style={[styles.statValue, { color }]}>{value}</Text>
    <Text style={styles.statLabel}>{label}</Text>
  </TouchableOpacity>
);

interface ModuleCardProps {
  title: string;
  subtitle: string;
  icon: string;
  color: string;
  onPress: () => void;
}

const ModuleCard: React.FC<ModuleCardProps> = ({ title, subtitle, icon, color, onPress }) => (
  <TouchableOpacity style={[styles.moduleCard, { borderColor: color }]} onPress={onPress} activeOpacity={0.8}>
    <View style={[styles.moduleIcon, { backgroundColor: color + '20' }]}>
      <Text style={{ fontSize: 24 }}>{icon}</Text>
    </View>
    <Text style={[styles.moduleTitle, { color }]}>{title}</Text>
    <Text style={styles.moduleSubtitle}>{subtitle}</Text>
  </TouchableOpacity>
);

export const DashboardScreen: React.FC = () => {
  const navigation = useNavigation();
  const { user, logout } = useAuth();
  const [loading, setLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [stats, setStats] = useState<any>(null);

  const modules = [
    { title: 'Students', subtitle: 'Admissions & Records', icon: '👥', color: '#2563EB', screen: 'Students' },
    { title: 'Teachers', subtitle: 'Faculty & Subjects', icon: '🏫', color: '#0D9488', screen: 'Teachers' },
    { title: 'Classes', subtitle: 'Sections & Groups', icon: '🏛️', color: '#7C3AED', screen: 'Classes' },
    { title: 'Exams & Marks', subtitle: 'Assessments & Entries', icon: '📝', color: '#EA580C', screen: 'Exams' },
    { title: 'Results', subtitle: 'Running / Published + PDF', icon: '🏆', color: '#B45309', screen: 'Results' },
    { title: 'Promotion → SSC', subtitle: 'Yearly Graduation', icon: '🎓', color: '#4F46E5', screen: 'Promotion' },
    { title: 'Routines', subtitle: 'Class & Bell Schedule', icon: '📅', color: '#16A34A', screen: 'Routines' },
    { title: 'Notices', subtitle: 'Broadcast Alerts', icon: '📢', color: '#E11D48', screen: 'Notices' },
    { title: 'Sibling Req.', subtitle: 'Guardian Pairings', icon: '👨‍👩‍👧', color: '#0284C7', screen: 'SiblingReq' },
    { title: 'Settings', subtitle: 'System Preferences', icon: '⚙️', color: '#475569', screen: 'Settings' },
  ];

  const loadStats = async () => {
    try {
      const data = await ApiClient.get('/admin/stats');
      setStats(data);
    } catch (e) {
      console.error('Failed to load stats:', e);
    }
  };

  const loadData = async () => {
    setLoading(true);
    try {
      const data = await ApiClient.get('/admin/stats');
      setStats(data);
    } catch (e) {
      console.error('Failed to load:', e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  useEffect(() => {
    loadData();
  }, []);

  const onRefresh = async () => {
    setRefreshing(true);
    await loadData();
  };

  const handleLogout = async () => {
    Alert.alert(
      'Sign Out',
      'Are you sure you want to log out of the admin panel?',
      [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Logout', style: 'destructive', onPress: () => logout() },
      ]
    );
  };

  const navigateTo = (screen: string) => {
    navigation.navigate(screen as any);
  };

  const renderStatCards = () => {
    if (!stats) return null;
    return (
      <View style={styles.statsRow}>
        <StatCard label="Students" value={stats.students || 0} icon="👥" color="#2563EB" />
        <StatCard label="Teachers" value={stats.teachers || 0} icon="🏫" color="#0D9488" />
        <StatCard label="Exams" value={stats.exams || 0} icon="📝" color="#EA580C" />
      </View>
    );
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <View style={styles.headerLeft}>
          <Text style={styles.headerIcon}>🛡️</Text>
          <Text style={styles.headerTitle}>Admin Dashboard</Text>
        </View>
        <TouchableOpacity onPress={loadData} disabled={loading} style={styles.refreshBtn}>
          <ActivityIndicator size="small" color="#052E22" />
        </TouchableOpacity>
        <TouchableOpacity onPress={handleLogout} style={styles.logoutBtn}>
          <Text style={styles.logoutIcon}>🚪</Text>
        </TouchableOpacity>
      </View>

      <ScrollView
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} colors={['#052E22']} />
        }
        contentContainerStyle={styles.scrollContent}
      >
        {stats && (
          <View style={styles.statsContainer}>
            <StatCard label="Students" value={stats.students || 0} icon="👥" color="#2563EB" />
            <StatCard label="Teachers" value={stats.teachers || 0} icon="🏫" color="#0D9488" />
            <StatCard label="Exams" value={stats.exams || 0} icon="📝" color="#EA580C" />
          </View>
        )}

        <View style={styles.sectionHeader}>
          <Text style={styles.sectionTitle}>Administrative Modules</Text>
          <Text style={styles.moduleCount}>{modules.length} Modules</Text>
        </View>

        <View style={styles.grid}>
          {modules.map((module, index) => (
            <ModuleCard
              key={index}
              title={module.title}
              subtitle={module.subtitle}
              icon={module.icon}
              color={module.color}
              onPress={() => navigateTo(module.screen)}
            />
          ))}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#F8FAFC' },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: 'white',
    borderBottomWidth: 1,
    borderColor: '#E2E8F0',
  },
  headerLeft: { flexDirection: 'row', alignItems: 'center' },
  headerIcon: { fontSize: 24, marginRight: 8 },
  headerTitle: { fontSize: 18, fontWeight: '800', color: '#0F172A' },
  refreshBtn: { padding: 8 },
  logoutBtn: { padding: 8 },
  scrollContent: { paddingHorizontal: 16, paddingTop: 14, paddingBottom: 20 },
  statsContainer: { flexDirection: 'row', marginBottom: 20, gap: 10 },
  statCard: {
    flex: 1,
    backgroundColor: 'white',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'transparent',
    padding: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.06,
    shadowRadius: 10,
    elevation: 2,
  },
  statIcon: { width: 36, height: 36, borderRadius: 8, alignItems: 'center', justifyContent: 'center' },
  statValue: { fontSize: 22, fontWeight: '800', letterSpacing: -0.5, marginTop: 10 },
  statLabel: { fontSize: 11, fontWeight: '600', color: '#64748B', marginTop: 2 },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
    marginTop: 8,
  },
  sectionTitle: { fontSize: 15, fontWeight: '700', color: '#0F172A', letterSpacing: -0.2 },
  moduleCount: { fontSize: 12, color: '#94A3B8', fontWeight: '500' },
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'space-between',
    gap: 12,
  },
  moduleCard: {
    width: '48%',
    aspectRatio: 1.25,
    backgroundColor: 'white',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'transparent',
    padding: 14,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.03,
    shadowRadius: 10,
    elevation: 2,
  },
  moduleIcon: { width: 42, height: 42, borderRadius: 12, alignItems: 'center', justifyContent: 'center', marginBottom: 8 },
  moduleTitle: { fontSize: 14, fontWeight: '700', color: '#0F172A', maxLines: 1 },
  moduleSubtitle: { fontSize: 11, fontWeight: '400', color: '#94A3B8', maxLines: 1, marginTop: 2 },
});

export default DashboardScreen;