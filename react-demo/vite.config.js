import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const API_URL = `${env.VITE_API_URL}/api`;
  const isDev = mode === 'development'

  console.log("🚀 ~ defineConfig ~ API_URL:", API_URL)
  
  return {
    define: {
      'process.env': {}
    },
    server: {
      port: 5174,
      proxy: {
        '^/proxy/capitolai/api': {
          target: 'http://localhost:8000/api',
          changeOrigin: isDev,
          secure: !isDev,
          rewrite: (path) => path.replace(/^\/proxy\/capitolai\/api/, ''),
        },
        '^/proxy/platform': {
          target: 'http://localhost:8811',
          changeOrigin: isDev,
          secure: !isDev,
          rewrite: (path) => path.replace(/^\/proxy\/platform/, ''),
        },
      },
    },
    plugins: [react()],
  }}
)
