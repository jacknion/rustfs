import api from '@/api/request';
import type { ServiceAccountInfo, AddServiceAccountReq, UpdateServiceAccountReq } from '@/types/iam';

export const getServiceAccounts = () => {
  return api.get<{accounts: ServiceAccountInfo[]}>('/list-service-accounts');
};

export const getServiceAccountInfo = (accessKey: string) => {
  return api.get<ServiceAccountInfo>('/info-service-account', { params: { accessKey } });
};

export const addServiceAccount = (data: AddServiceAccountReq) => {
  return api.put('/add-service-accounts', data);
};

export const updateServiceAccount = (accessKey: string, data: UpdateServiceAccountReq) => {
  return api.post('/update-service-account', data, { params: { accessKey } });
};

export const deleteServiceAccount = (accessKey: string) => {
  return api.delete('/delete-service-accounts', { params: { accessKey } });
};

