import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5175,
    host: '0.0.0.0'
  },
  resolve: {
    alias: {
      'react-native': 'react-native-web',
      'react-native-vector-icons': 'react-native-vector-icons-web',
    }
  }
})