import api from '@/api/request';
import type { Policy } from '@/types/iam';

export const getPolicies = () => {
  return api.get<Record<string, Policy>>('/list-canned-policies'); // Adjust return type if it's map
};

export const getPolicyInfo = (name: string) => {
  return api.get<Policy>('/info-canned-policy', { params: { name } });
};

export const addPolicy = (name: string, policy: Policy) => {
  // Policy needs to be stringified JSON or object depending on backend
  // RustFS handler reads body as bytes and parses? 
  // policies.rs: let body = req.input... let policy: Policy = serde_json::from_slice(&body)
  return api.put('/add-canned-policy', policy, { params: { name } });
};

export const removePolicy = (name: string) => {
  return api.delete('/remove-canned-policy', { params: { name } });
};

export const setPolicy = (policyName: string, userOrGroup: string, isGroup: boolean) => {
  return api.put('/set-user-or-group-policy', null, { 
    params: { policyName, userOrGroup, isGroup: isGroup.toString() } 
  });
};
