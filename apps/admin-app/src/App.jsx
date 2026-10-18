import React from 'react'
import { NavigationContainer } from '@react-navigation/native'
import {createStackNavigator} from '@react-navigation/stack'
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs'
import { Text, StyleSheet, View, TouchableOpacity, Alert } from 'react-native'
import { AuthProvider, useAuth } from './context/AuthContext'
import ApiClient from './services/api'
import { LoginScreen } from './screens/LoginScreen'
import { DashboardScreen } from './screens/DashboardScreen'
import { StudentsScreen } from './screens/StudentsScreen'
import { TeachersScreen } from './screens/TeachersScreen'
import { ClassesScreen } from './screens/ClassesScreen'
import { SubjectsScreen } from './screens/SubjectsScreen'
import { ExamsScreen } from './screens/ExamsScreen'
import { ExamDetailScreen } from './screens/ExamDetailScreen'
import { ResultsScreen } from './screens/ResultsScreen'
import { PromotionScreen } from './screens/PromotionScreen'
import { RoutinesScreen } from './screens/RoutinesScreen'
import { NoticesScreen } from './screens/NoticesScreen'
import { SettingsScreen } from './screens/SettingsScreen'
import { SiblingReqScreen } from './screens/SiblingReqScreen'
import { DesignationScreen } from './screens/DesignationScreen'
import { ReexamScreen } from './screens/ReexamScreen'
import { MarkEditScreen } from './screens/MarkEditScreen'
import { AttendanceScreen } from './screens/AttendanceScreen'
import { LeaveScreen } from './screens/LeaveScreen'
import { ActivityLogScreen } from './screens/ActivityLogScreen'

const Stack = stacks => ({ children }) => null
const Tab = createBottomTabNavigator()

function TabIcon({ label, color, size }) {
  return <Text style={{ fontSize: size, color }}>{label}</Text>
}

function AppTabs() {
  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        tabBarIcon: ({ color, size }) => {
          let icon = '?'
          if (route.name === 'Dashboard') icon = 'D'
          else if (route.name === 'Students') icon = 'S'
          else if (route.name === 'Teachers') icon = 'T'
          else if (route.name === 'Classes') icon = 'C'
          else if (route.name === 'Exams') icon = 'E'
          else if (route.name === 'Results') icon = 'R'
          else if (route.name === 'Promotion') icon = 'P'
          else if (route.name === 'Routines') icon = 'Rt'
          else if (route.name === 'Notices') icon = 'N'
          else if (route.name === 'SiblingReq') icon = 'Sr'
          else if (route.name === 'Settings') icon = 'St'
          return <TabIcon label={icon} color={color} size={size} />
        },
        tabBarActiveTintColor: '#052E22',
        tabBarInactiveTintColor: 'gray',
        headerStyle: { backgroundColor: '#052E22' },
        headerTintColor: 'white',
      })}
    >
      <Tab.Screen name="Dashboard" component={DashboardScreen} />
      <Tab.Screen name="Students" component={StudentsScreen} />
      <Tab.Screen name="Teachers" component={TeachersScreen} />
      <Tab.Screen name="Classes" component={ClassesScreen} />
      <Tab.Screen name="Exams" component={ExamsScreen} />
      <Tab.Screen name="Results" component={ResultsScreen} />
      <Tab.Screen name="Promotion" component={PromotionScreen} />
      <Tab.Screen name="Routines" component={RoutinesScreen} />
      <Tab.Screen name="Notices" component={NoticesScreen} />
      <Tab.Screen name="SiblingReq" component={SiblingReqScreen} />
      <Tab.Screen name="Settings" component={SettingsScreen} />
    </Tab.Navigator>
  )
}

export default function App() {
  const { user, loading, logout } = useAuth()

  if (loading) {
    return (
      <View style={[styles.container, styles.centered]}>
        <Text style={styles.loadingText}>Loading Admin Panel...</Text>
      </View>
    )
  }

  if (!user) {
    return (
      <NavigationContainer>
        <createStackNavigator.Screen name="Login" component={LoginScreen} />
      </NavigationContainer>
    )
  }

  return (
    <NavigationContainer>
      <createStackNavigator.Screen name="Tabs" component={AppTabs} />
    </NavigationContainer>
  )
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f5f5f5' },
  centered: { justifyContent: 'center', alignItems: 'center' },
  loadingText: { fontSize: 16, color: '#666' }
})