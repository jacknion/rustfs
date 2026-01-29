import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import LoginView from '../views/auth/LoginView.vue'
import AppLayout from '../components/layout/AppLayout.vue'
import DashboardView from '../views/dashboard/DashboardView.vue'
import UsersView from '../views/iam/UsersView.vue'
import GroupsView from '../views/iam/GroupsView.vue'
import PoliciesView from '../views/iam/PoliciesView.vue'
import ServiceAccountsView from '../views/iam/ServiceAccountsView.vue'
import BucketsView from '../views/storage/BucketsView.vue'
import ObjectBrowser from '../views/storage/ObjectBrowser.vue'
import PoolsView from '../views/storage/PoolsView.vue'
import StorageInfoView from '../views/monitoring/StorageInfoView.vue'
import DataUsageView from '../views/monitoring/DataUsageView.vue'
import MetricsView from '../views/monitoring/MetricsView.vue'
import HealView from '../views/maintenance/HealView.vue'
import TierView from '../views/maintenance/TierView.vue'
import RebalanceView from '../views/maintenance/RebalanceView.vue'
import KMSView from '../views/security/KMSView.vue'
import ReplicationView from '../views/settings/ReplicationView.vue'
import NotificationsView from '../views/settings/NotificationsView.vue'
import MetadataQueryView from '../views/tools/MetadataQueryView.vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/login',
      name: 'Login',
      component: LoginView
    },
    {
      path: '/',
      component: AppLayout,
      meta: { requiresAuth: true },
      children: [
        {
          path: '',
          name: 'Dashboard',
          component: DashboardView
        },
        {
          path: 'iam/users',
          name: 'Users',
          component: UsersView
        },
        {
          path: 'iam/groups',
          name: 'Groups',
          component: GroupsView
        },
        {
          path: 'iam/policies',
          name: 'Policies',
          component: PoliciesView
        },
        {
          path: 'iam/service-accounts',
          name: 'ServiceAccounts',
          component: ServiceAccountsView
        },
        {
          path: 'storage/buckets',
          name: 'Buckets',
          component: BucketsView
        },
        {
          path: 'storage/buckets/:name',
          name: 'ObjectBrowser',
          component: ObjectBrowser
        },
        {
          path: 'storage/pools',
          name: 'Pools',
          component: PoolsView
        },
        // Monitoring routes
        {
          path: 'monitoring/storage',
          name: 'StorageInfo',
          component: StorageInfoView
        },
        {
          path: 'monitoring/usage',
          name: 'DataUsage',
          component: DataUsageView
        },
        {
          path: 'monitoring/metrics',
          name: 'Metrics',
          component: MetricsView
        },
        // Maintenance routes
        {
          path: 'maintenance/heal',
          name: 'Heal',
          component: HealView
        },
        {
          path: 'maintenance/tier',
          name: 'Tier',
          component: TierView
        },
        {
          path: 'maintenance/rebalance',
          name: 'Rebalance',
          component: RebalanceView
        },
        // Security routes
        {
          path: 'security/kms',
          name: 'KMS',
          component: KMSView
        },
        // Settings routes
        {
          path: 'settings/replication',
          name: 'Replication',
          component: ReplicationView
        },
        {
          path: 'settings/notifications',
          name: 'Notifications',
          component: NotificationsView
        },
        // Tools routes
        {
          path: 'tools/metadata-query',
          name: 'MetadataQuery',
          component: MetadataQueryView
        }
      ]
    }
  ]
})

router.beforeEach((to, _from, next) => {
  const authStore = useAuthStore()
  if (to.meta.requiresAuth && !authStore.isAuthenticated) {
    next({ name: 'Login' })
  } else {
    next()
  }
})

export default router



