export interface UserInfo {
  status: 'enabled' | 'disabled';
  secretKey?: string;
  policyName?: string;
  memberOf?: string[];
  updatedAt?: string;
  accessKey?: string; // Enhanced property for UI
}

export interface AddOrUpdateUserReq {
  secretKey: string;
  status: 'enabled' | 'disabled';
  policy?: string;
}

export interface GroupDesc {
  name: string;
  status: string;
  members: string[];
  policy: string;
  updatedAt?: string;
}

export interface GroupAddRemove {
  group: string;
  members: string[];
  groupStatus: 'enabled' | 'disabled';
  isRemove: boolean;
}

export interface ServiceAccountInfo {
  parentUser: string;
  accountStatus: string;
  impliedPolicy: boolean;
  accessKey: string;
  name?: string;
  description?: string;
  expiration?: string;
}

export interface AddServiceAccountReq {
  policy?: string;
  targetUser?: string;
  accessKey: string;
  secretKey: string;
  name: string;
  description?: string;
  expiration?: string;
}

export interface UpdateServiceAccountReq {
  newSecretKey?: string;
  newPolicy?: string;
  newName?: string;
  newDescription?: string;
  newExpiration?: string;
  newStatus?: 'on' | 'off';
}

export interface Policy {
  Version: string;
  Statement: PolicyStatement[];
}

export interface PolicyStatement {
  Effect: 'Allow' | 'Deny';
  Action: string | string[];
  Resource: string | string[];
  Condition?: Record<string, any>;
}

