import api from '@/api/request';

// Notification Target Types
export type TargetType = 'webhook' | 'amqp' | 'kafka' | 'mqtt' | 'nats' | 'nsq' | 'elasticsearch' | 'redis' | 'mysql' | 'postgresql';

export interface NotificationTarget {
    id: string;
    type: TargetType;
    arn: string;
    status: 'online' | 'offline';
    config: Record<string, any>;
}

export interface NotificationTargetListResponse {
    targets: NotificationTarget[];
}

export interface WebhookConfig {
    endpoint: string;
    authToken?: string;
    queueDir?: string;
    queueLimit?: number;
    clientCert?: string;
    clientKey?: string;
}

export interface KafkaConfig {
    brokers: string[];
    topic: string;
    saslUsername?: string;
    saslPassword?: string;
    saslMechanism?: string;
    tlsClientAuth?: string;
    tlsSkipVerify?: boolean;
    version?: string;
}

export interface AddTargetRequest {
    type: TargetType;
    id?: string;
    config: Record<string, any>;
}

// API Functions
export const listNotificationTargets = () => {
    return api.get<NotificationTargetListResponse>('/target/list');
};

export const addNotificationTarget = (data: AddTargetRequest) => {
    return api.post('/target/add', data);
};

export const removeNotificationTarget = (arn: string) => {
    return api.delete('/target/remove', { params: { arn } });
};

export const testNotificationTarget = (arn: string) => {
    return api.post('/target/test', { arn });
};

// Get bucket notification configuration
export const getBucketNotification = (bucket: string) => {
    return api.get('/get-bucket-notification', { params: { bucket } });
};

// Set bucket notification configuration  
export const setBucketNotification = (bucket: string, config: any) => {
    return api.put('/set-bucket-notification', { bucket, ...config });
};
