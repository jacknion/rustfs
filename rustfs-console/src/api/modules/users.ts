import api from '@/api/request';
import type { UserInfo, AddOrUpdateUserReq } from '@/types/iam';

export const getUsers = () => {
  return api.get<Record<string, UserInfo>>('/list-users');
};

export const getUserInfo = (accessKey: string) => {
  return api.get<UserInfo>('/user-info', { params: { accessKey } });
};

export const addUser = (accessKey: string, data: AddOrUpdateUserReq) => {
  return api.put('/add-user', data, { params: { accessKey } });
};

export const deleteUser = (accessKey: string) => {
  return api.delete('/remove-user', { params: { accessKey } });
};

export const setUserStatus = (accessKey: string, status: 'enabled' | 'disabled') => {
  return api.put('/set-user-status', null, { params: { accessKey, status } });
};
