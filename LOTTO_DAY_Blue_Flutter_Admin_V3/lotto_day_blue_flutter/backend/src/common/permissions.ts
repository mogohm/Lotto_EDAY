import { Role } from '@prisma/client';

export const PERMISSIONS = [
  'dashboard.view',
  'users.view',
  'users.manage',
  'roles.manage',
  'markets.manage',
  'draws.manage',
  'results.edit',
  'results.review',
  'results.publish',
  'catalog.manage',
  'orders.view',
  'orders.manage',
  'announcements.manage',
  'reports.view',
  'settings.manage',
  'audit.view',
] as const;
export type Permission = (typeof PERMISSIONS)[number];

export const ROLE_PERMISSIONS: Record<Role, readonly Permission[]> = {
  SUPER_ADMIN: PERMISSIONS,
  ADMIN: PERMISSIONS.filter((p) => p !== 'roles.manage'),
  RESULT_EDITOR: ['dashboard.view', 'draws.manage', 'results.edit', 'audit.view'],
  REVIEWER: ['dashboard.view', 'results.review', 'results.publish', 'audit.view'],
  AUDITOR: ['dashboard.view', 'users.view', 'orders.view', 'reports.view', 'audit.view'],
  USER: [],
};

export const ROLE_LABEL_TH: Record<Role, string> = {
  SUPER_ADMIN: 'ผู้ดูแลสูงสุด',
  ADMIN: 'ผู้ดูแลระบบ',
  RESULT_EDITOR: 'ผู้บันทึกผล',
  REVIEWER: 'ผู้ตรวจสอบ/อนุมัติ',
  AUDITOR: 'ผู้ตรวจสอบบัญชี (อ่านอย่างเดียว)',
  USER: 'สมาชิก',
};

export function hasPermission(role: Role, permission: Permission) {
  return ROLE_PERMISSIONS[role]?.includes(permission) ?? false;
}
export function isStaff(role: Role) { return role !== Role.USER; }
