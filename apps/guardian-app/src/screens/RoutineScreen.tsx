import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, SafeAreaView, ScrollView, FlatList } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import ApiClient from '../services/api';

export const RoutineScreen: React.FC = () => {
  const [routine, setRoutine] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const loadRoutine = async () => {
    try {
      const data = await ApiClient.get('/guardian/routine');
      setRoutine(Array.isArray(data) ? data : data.routine || []);
    } catch (e) {
      console.error('Failed to load routine:', e);
    } finally {
      setLoading(false);
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Routine</Text>
      </View>

      <FlatList
        data={routine}
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
        ListEmptyComponent={<View style={styles.emptyState}><Text style={styles.emptyText}>No routine</Text></View>}
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
});

export default RoutineScreen;