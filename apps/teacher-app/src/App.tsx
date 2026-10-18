import React, { useState, useEffect } from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createStackNavigator } from '@react-navigation/stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { Provider as PaperProvider } from 'react-native-paper';
import { useAuth } from './context/AuthContext';
import { LoginScreen } from './screens/LoginScreen';
import { DashboardScreen } from './screens/DashboardScreen';
import { AttendanceScreen } from './screens/AttendanceScreen';
import { ExamsScreen } from './screens/ExamsScreen';
import { ExamDetailScreen } from './screens/ExamDetailScreen';
import { EventDetailScreen } from './screens/EventDetailScreen';
import { HomeworkScreen } from './screens/HomeworkScreen';
import { RoutineScreen } from './screens/RoutineScreen';
import { ClassStudentsScreen } from './screens/ClassStudentsScreen';
import { WhoIsFreeScreen } from './screens/WhoIsFreeScreen';
import { ProfileScreen } from './screens/ProfileScreen';
import { AttendanceAnalyticsScreen } from './screens/AttendanceAnalyticsScreen';
import { StudentRegistrationScreen } from './screens/StudentRegistrationScreen';
import { CreateExamScreen } from './screens/CreateExamScreen';
import { ExamDetailScreen as ExamDetailScreenTeacher } from './screens/ExamDetailScreen';
import { OcrCaptureScreen } from './screens/OcrCaptureScreen';
import { ClassAlertsScreen } from './screens/ClassAlertsScreen';
import { SettingsScreen } from './screens/SettingsScreen';
import { SplashScreen } from './screens/SplashScreen';

const Stack = createStackNavigator();
const Tab = createBottomTabNavigator();

function AppTabs() {
  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        tabBarIcon: ({ focused, color, size }) => {
          let iconName;
          if (route.name === 'Dashboard') iconName = 'home';
          else if (route.name === 'Exams') iconName = 'quiz';
          else if (route.name === 'Attendance') iconName = 'clipboard-check';
          else if (route.name === 'Homework') iconName = 'book-open';
          else if (route.name === 'Routine') iconName = 'calendar';
          return <Icon name={iconName} size={size} color={color} />;
        },
        tabBarActiveTintColor: '#052E22',
        tabBarInactiveTintColor: 'gray',
      })}
    >
      <Tab.Screen name="Dashboard" component={DashboardScreen} />
      <Tab.Screen name="Exams" component={ExamsScreen} />
      <Tab.Screen name="Attendance" component={AttendanceScreen} />
      <Tab.Screen name="Homework" component={HomeworkScreen} />
      <Tab.Screen name="Routine" component={RoutineScreen} />
    </Tab.Navigator>
  );
}

export default function App() {
  const { user, loading, login, logout, checkAuth } = useAuth();

  useEffect(() => {
    checkAuth();
  }, []);

  if (loading) {
    return <SplashScreen />;
  }

  if (!user) {
    return (
      <NavigationContainer>
        <Stack.Navigator screenOptions={{ headerShown: false }}>
          <Stack.Screen name="Login" component={LoginScreen} />
        </Stack.Navigator>
      </NavigationContainer>
    );
  }

  return (
    <PaperProvider>
      <NavigationContainer>
        <Stack.Navigator screenOptions={{ headerShown: false }}>
          <Stack.Screen name="Tabs" component={AppTabs} />
          <Stack.Screen name="Dashboard" component={DashboardScreen} />
          <Stack.Screen name="Attendance" component={AttendanceScreen} />
          <Stack.Screen name="Exams" component={ExamsScreen} />
          <Stack.Screen name="ExamDetail" component={ExamDetailScreen} />
          <Stack.Screen name="EventDetail" component={EventDetailScreen} />
          <Stack.Screen name="Homework" component={HomeworkScreen} />
          <Stack.Screen name="Routine" component={RoutineScreen} />
          <Stack.Screen name="ClassStudents" component={ClassStudentsScreen} />
          <Stack.Screen name="WhoIsFree" component={WhoIsFreeScreen} />
          <Stack.Screen name="Profile" component={ProfileScreen} />
          <Stack.Screen name="AttendanceAnalytics" component={AttendanceAnalyticsScreen} />
          <Stack.Screen name="StudentRegistration" component={StudentRegistrationScreen} />
          <Stack.Screen name="CreateExam" component={CreateExamScreen} />
          <Stack.Screen name="ExamDetailTeacher" component={ExamDetailScreenTeacher} />
          <Stack.Screen name="OcrCapture" component={OcrCaptureScreen} />
          <Stack.Screen name="ClassAlerts" component={ClassAlertsScreen} />
          <Stack.Screen name="Settings" component={SettingsScreen} />
          <Stack.Screen name="Profile" component={ProfileScreen} />
        </Stack.Navigator>
      </NavigationContainer>
    </PaperProvider>
  );
}

// Icon component
import { createFromIconfontCN } from '@react-native-vector-icons/iconfont';
const Icon = createFromIconfontCN({
  scriptUrl: '//at.alicdn.com/t/font_1234567_abcdefg.js',
});

// Dummy Icon for now
const Icon = ({ name, size, color }: any) => (
  <Text style={{ fontSize: size, color }}>{name}</Text>
);

import { Text } from 'react-native';