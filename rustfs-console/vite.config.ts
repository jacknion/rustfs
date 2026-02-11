import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import path from 'path'

// https://vite.dev/config/
export default defineConfig({
  base: '/rustfs/console/',
  plugins: [vue()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      'buffer': 'buffer',
    }
  },
  define: {
    'process.env': {},
  },
  server: {
    proxy: {
      '/rustfs': {
        target: 'http://127.0.0.1:9000',
        changeOrigin: true,
      },
      '/s3api': {
        target: 'http://127.0.0.1:9000',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/s3api/, '')
      }
    }
  }
})
