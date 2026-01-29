<template>
  <a-layout class="login-layout">
    <a-layout-content class="login-content">
      <div class="login-panel">
        <div class="brand">
          <div class="brand-logo">RustFS</div>
          <div class="brand-subtitle">Console</div>
        </div>

        <a-card class="login-card" :bordered="false">
          <a-typography-title :level="3" class="login-title">Sign in</a-typography-title>
          <a-typography-paragraph class="login-desc">
            Use your RustFS access key and secret key.
          </a-typography-paragraph>

          <a-form layout="vertical" :model="formState" @finish="handleLogin">
            <a-form-item
              label="Access Key"
              name="accessKey"
              :rules="[{ required: true, message: 'Please input Access Key' }]"
            >
              <a-input
                v-model:value="formState.accessKey"
                placeholder="AKIA..."
                size="large"
                autocomplete="username"
              >
                <template #prefix>
                  <UserOutlined />
                </template>
              </a-input>
            </a-form-item>

            <a-form-item
              label="Secret Key"
              name="secretKey"
              :rules="[{ required: true, message: 'Please input Secret Key' }]"
            >
              <a-input-password
                v-model:value="formState.secretKey"
                placeholder="••••••••••••••••"
                size="large"
                autocomplete="current-password"
              >
                <template #prefix>
                  <LockOutlined />
                </template>
              </a-input-password>
            </a-form-item>

            <a-form-item style="margin-bottom: 0">
              <a-button type="primary" html-type="submit" block size="large" :loading="loading">
                Login
              </a-button>
            </a-form-item>
          </a-form>
        </a-card>

        <div class="login-footer">
          <span class="footer-text">RustFS Console</span>
          <span class="footer-dot">•</span>
          <span class="footer-text">Independent UI</span>
        </div>
      </div>
    </a-layout-content>
  </a-layout>
</template>

<script setup lang="ts">
import { reactive, ref } from 'vue';
import { useAuthStore } from '@/stores/auth';
import { useRouter } from 'vue-router';
import { UserOutlined, LockOutlined } from '@ant-design/icons-vue';
import { message } from 'ant-design-vue';
import api from '@/api/request';

const authStore = useAuthStore();
const router = useRouter();
const loading = ref(false);

const formState = reactive({
  accessKey: '',
  secretKey: '',
});

const handleLogin = async () => {
  loading.value = true;
  // Local check first
  authStore.login(formState.accessKey, formState.secretKey);
  
  try {
    // Verify credentials by calling a lightweight API
    await api.get('/info');
    message.success('Login success');
    router.push('/');
  } catch (error) {
    console.error(error);
    message.error('Login failed: Invalid credentials or network error');
    authStore.logout();
  } finally {
    loading.value = false;
  }
};
</script>

<style scoped>
.login-layout {
  min-height: 100vh;
  background:
    radial-gradient(1200px 600px at 20% 10%, rgba(24, 144, 255, 0.18), transparent 55%),
    radial-gradient(900px 500px at 90% 30%, rgba(82, 196, 26, 0.14), transparent 60%),
    #f5f7fb;
}

.login-content {
  display: flex;
  justify-content: center;
  align-items: center;
  padding: 24px;
}

.login-panel {
  width: 420px;
  max-width: 92vw;
}

.brand {
  text-align: center;
  margin-bottom: 16px;
}

.brand-logo {
  font-size: 28px;
  font-weight: 800;
  letter-spacing: 0.5px;
  color: rgba(0, 0, 0, 0.88);
  line-height: 1.1;
}

.brand-subtitle {
  margin-top: 4px;
  font-size: 14px;
  color: rgba(0, 0, 0, 0.55);
}

.login-card {
  border-radius: 14px;
  box-shadow: 0 14px 45px rgba(15, 23, 42, 0.10);
}

.login-title {
  margin-bottom: 4px !important;
}

.login-desc {
  margin-bottom: 20px;
  color: rgba(0, 0, 0, 0.55);
}

.login-footer {
  text-align: center;
  margin-top: 14px;
  font-size: 12px;
  color: rgba(0, 0, 0, 0.45);
}

.footer-dot {
  margin: 0 8px;
}
</style>
