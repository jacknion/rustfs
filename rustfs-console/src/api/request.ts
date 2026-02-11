import axios, { type InternalAxiosRequestConfig } from 'axios';
import { SignatureV4 } from '@aws-sdk/signature-v4';
import { Sha256 } from '@aws-crypto/sha256-browser';
import { HttpRequest } from '@aws-sdk/protocol-http';
import { useAuthStore } from '@/stores/auth';

const EMPTY_SHA256_HEX = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

const toHex = (bytes: Uint8Array) => Array.from(bytes).map((b) => b.toString(16).padStart(2, '0')).join('');

const sha256Hex = async (payload: string) => {
  const hasher = new Sha256();
  hasher.update(new TextEncoder().encode(payload));
  const digest = (await hasher.digest()) as Uint8Array;
  return toHex(digest);
};

const getHeaderValue = (headers: any, name: string): string | undefined => {
  if (!headers) return undefined;
  const lower = name.toLowerCase();

  // AxiosHeaders instance
  if (typeof headers.get === 'function') {
    const v = headers.get(name);
    if (typeof v === 'string') return v;
  }

  // Plain object
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() === lower) {
      const v = headers[key];
      if (typeof v === 'string') return v;
    }
  }
  return undefined;
};

const api = axios.create({
  baseURL: '/rustfs/admin/v3',
  timeout: 10000,
});

export const s3Api = axios.create({
  baseURL: '/s3api',
  timeout: 30000,
});

const signRequest = async (config: InternalAxiosRequestConfig) => {
  const authStore = useAuthStore();
  
  if (!authStore.accessKey || !authStore.secretKey) {
    return config;
  }

  const { method, url, params, data, baseURL } = config;

  // Construct full path
  let fullPath = url || '';
  if (baseURL && !fullPath.startsWith('http')) {
      const cleanBase = baseURL.replace(/\/$/, '');
      const cleanUrl = fullPath.startsWith('/') ? fullPath : '/' + fullPath;
      fullPath = cleanBase + cleanUrl;
  }

  // Rewrite path for signing to match what the server receives after proxy rewrite
  let signPath = fullPath;
  if (signPath.startsWith('/s3api')) {
      signPath = signPath.replace(/^\/s3api/, '');
      if (signPath === '') signPath = '/';
  }
  // Note: /rustfs/admin/ paths are passed through to RustFS as-is

  // Extract query string embedded in URL path (e.g. "/{bucket}?policy&key=val")
  // SigV4 requires path and query to be separate for correct canonical request
  let urlQuery: Record<string, string> = {};
  const qIdx = signPath.indexOf('?');
  if (qIdx >= 0) {
      const qs = signPath.slice(qIdx + 1);
      signPath = signPath.slice(0, qIdx);
      for (const part of qs.split('&')) {
          const eqIdx = part.indexOf('=');
          if (eqIdx >= 0) {
              urlQuery[decodeURIComponent(part.slice(0, eqIdx))] = decodeURIComponent(part.slice(eqIdx + 1));
          } else {
              urlQuery[decodeURIComponent(part)] = '';
          }
      }
  }

  // Handle Body
  let body = data;
  const axiosHeaders = config.headers as any;
  let headers = { ...axiosHeaders } as any;

  // If uploading a file, use UNSIGNED-PAYLOAD to avoid memory issues and calculating hash of large files
  if (data instanceof File || data instanceof Blob) {
    headers['x-amz-content-sha256'] = 'UNSIGNED-PAYLOAD';
    body = undefined; // Do not pass body to signer if unsigned
  } else if (data && typeof data === 'object') {
    // Prepare JSON body for signer
    body = JSON.stringify(data);
    if (!headers['content-type'] && !headers['Content-Type']) {
      headers['content-type'] = 'application/json';
    }
  }

  // Some S3-compatible servers (and many SigV4 verifiers) require x-amz-content-sha256.
  // Ensure it is always present and matches the payload we sign.
  if (!headers['x-amz-content-sha256']) {
    if (body === undefined || body === null || body === '') {
      headers['x-amz-content-sha256'] = EMPTY_SHA256_HEX;
    } else if (typeof body === 'string') {
      headers['x-amz-content-sha256'] = await sha256Hex(body);
    }
  }

  // In SigV4, the canonical request includes the exact `host` header value.
  // In production, the browser sends the Host header for the public domain.
  // In development, Vite proxy (changeOrigin: true) sends Host: 127.0.0.1:9000 to the backend.
  // We must sign with the same host value the backend will verify.
  const requestHost = import.meta.env.DEV ? '127.0.0.1:9000' : window.location.host;
  const protocol = import.meta.env.DEV ? 'http:' : window.location.protocol;

  // Parse hostname/port for HttpRequest. (Host header itself is provided via `signHeaders.host`.)
  let hostname = requestHost;
  let port: number | undefined;
  if (requestHost.startsWith('[')) {
    const end = requestHost.indexOf(']');
    if (end > 0) {
      hostname = requestHost.slice(1, end);
      const rest = requestHost.slice(end + 1);
      if (rest.startsWith(':')) port = parseInt(rest.slice(1), 10);
    }
  } else {
    const parts = requestHost.split(':');
    if (parts.length === 2 && parts[0] && parts[1]) {
      hostname = parts[0];
      port = parseInt(parts[1], 10);
    }
  }

  // IMPORTANT: avoid signing transient/proxy-mutated headers (accept, user-agent, etc).
  // Sign the minimal stable set to prevent SignatureDoesNotMatch.
  const contentType = getHeaderValue(headers, 'content-type');
  const signHeaders: Record<string, string> = {
    host: requestHost,
    'x-amz-content-sha256': headers['x-amz-content-sha256'],
  };
  if (contentType) signHeaders['content-type'] = contentType;
  if (authStore.sessionToken) signHeaders['x-amz-security-token'] = authStore.sessionToken;

  // Ensure all query params are strings for signing to match how they are sent on the wire
  // (Fixes SignatureDoesNotMatch when params contains numbers like list-type=2)
  const signQuery: Record<string, string> = { ...urlQuery };
  if (params) {
    for (const key in params) {
       const val = params[key];
       if (val !== undefined && val !== null) {
           signQuery[key] = String(val);
       }
    }
  }

  const httpRequest = new HttpRequest({
    method: method?.toUpperCase() || 'GET',
    protocol,
    hostname,
    port,
    path: signPath,
    query: signQuery,
    headers: signHeaders,
    body: body
  });

  const signer = new SignatureV4({
    credentials: {
      accessKeyId: authStore.accessKey,
      secretAccessKey: authStore.secretKey,
      sessionToken: authStore.sessionToken || undefined,
    },
    region: authStore.region,
    service: 's3',
    sha256: Sha256, // @aws-crypto/sha256-browser
  });

  try {
    const signed = await signer.sign(httpRequest);

    // Sync signature headers back to axios config.
    // Important: config.headers might be an AxiosHeaders instance, which requires specialized handling or replacement.
    // Using simple spread on AxiosHeaders instance can fail to copy internal map.
    // We create a fresh object and cast it.
    
    // 1. Get existing headers safely
    const originalHeaders = config.headers && typeof config.headers.toJSON === 'function' 
        ? (config.headers as any).toJSON() 
        : { ...config.headers };

    // 2. Merge strict components
    const finalHeaders = {
        ...originalHeaders,
        ...signed.headers,
    };
    
    // Remove "host" header to avoid browser warnings (Refused to set unsafe header "host")
    // Use delete operator or object destructuring
    delete finalHeaders['host'];
    delete finalHeaders['Host'];

    if (headers['x-amz-content-sha256']) {
        finalHeaders['x-amz-content-sha256'] = headers['x-amz-content-sha256'];
    }

    config.headers = finalHeaders;

  } catch (error) {
    console.error('Signing failed:', error);
  }

  return config;
};

api.interceptors.request.use(signRequest, (error) => Promise.reject(error));
s3Api.interceptors.request.use(signRequest, (error) => Promise.reject(error));

export default api;
