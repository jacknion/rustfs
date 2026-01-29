import { defineStore } from 'pinia';
import { ref, computed } from 'vue';

export const useAuthStore = defineStore('auth', () => {
  const accessKey = ref(localStorage.getItem('accessKey') || '');
  const secretKey = ref(localStorage.getItem('secretKey') || '');
  const sessionToken = ref(localStorage.getItem('sessionToken') || '');
  const region = ref(localStorage.getItem('region') || 'us-east-1');

  const isAuthenticated = computed(() => !!accessKey.value && !!secretKey.value);

  function login(ak: string, sk: string, token: string = '', reg: string = 'us-east-1') {
    accessKey.value = ak;
    secretKey.value = sk;
    sessionToken.value = token;
    region.value = reg;
    
    localStorage.setItem('accessKey', ak);
    localStorage.setItem('secretKey', sk);
    if (token) localStorage.setItem('sessionToken', token);
    localStorage.setItem('region', reg);
  }

  function logout() {
    accessKey.value = '';
    secretKey.value = '';
    sessionToken.value = '';
    
    localStorage.removeItem('accessKey');
    localStorage.removeItem('secretKey');
    localStorage.removeItem('sessionToken');
  }

  return {
    accessKey,
    secretKey,
    sessionToken,
    region,
    isAuthenticated,
    login,
    logout
  };
});
