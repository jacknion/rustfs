import api from '@/api/request';
import type { GroupDesc, GroupAddRemove } from '@/types/iam';

export const getGroups = () => {
  return api.get<string[]>('/groups');
};

export const getGroupInfo = (group: string) => {
  return api.get<GroupDesc>('/group', { params: { group } });
};

export const updateGroupMembers = (data: GroupAddRemove) => {
  return api.put('/update-group-members', data);
};

export const setGroupStatus = (group: string, status: 'enabled' | 'disabled') => {
  return api.put('/set-group-status', null, { params: { group, status } });
};
