import { BadRequestException } from '@nestjs/common';

export type PreparedAdminUserMutation = {
  email: string;
  role: string;
  workScopeType: string;
  personnel: {
    departmentCode?: string | null;
    jobRoleCode?: string | null;
    regionCode?: string | null;
    areaCode?: string | null;
    organizationNodeId?: string | null;
  };
  organizationNodeIds: string[];
  createData: Record<string, unknown>;
  updateData: Record<string, unknown>;
};

export type AdminUserRelationMutationInput = {
  storeUuid?: string | null;
  departmentCode?: string | null;
  jobRoleCode?: string | null;
  regionCode?: string | null;
  areaCode?: string | null;
  organizationNodeId?: string | null;
};

export type AdminUserRelationMutationOptions = {
  disconnectNulls?: boolean;
};

export type UserAdminMutationPreparationRuntime = {
  normalizeAccountEmail: (value: unknown) => string;
  normalizeRoleCode: (role: string, preserve?: boolean) => string;
  assertEmailCreatableByAdmin: (admin: any, email: string) => Promise<void>;
  resolveAssignableRole: (roleInput: string) => Promise<string>;
  assertRoleEditable: (
    admin: any,
    role: string,
    currentRole?: string,
  ) => Promise<void>;
  resolveUserOrganizationAssignmentNodeIds: (
    admin: any,
    body: any,
    current: any | null,
  ) => Promise<string[]>;
  resolveWorkScopeTypeForAssignment: (
    body: any,
    current: any | null,
    role: string,
  ) => Promise<string>;
  resolveUserAssignmentStoreUuid: (
    admin: any,
    body: any,
    options: { current?: any; workScopeType: string },
  ) => Promise<string | null>;
  resolvePersonnelAssignment: (
    admin: any,
    body: any,
    options: {
      current?: any;
      role: string;
      storeUuid?: string | null;
      workScopeType: string;
    },
  ) => Promise<
    PreparedAdminUserMutation['personnel'] & { workScopeType: string }
  >;
  userRelationMutationData: (
    input: AdminUserRelationMutationInput,
    options?: AdminUserRelationMutationOptions,
  ) => Record<string, unknown>;
};

/**
 * Prepares the shared create/update payload used by admin mutation and import
 * flows. Authorization and access-change decisions stay with their callers;
 * this collaborator only coordinates the already-owned policy/data helpers.
 */
export class UserAdminMutationPreparationService {
  constructor(private readonly runtime: UserAdminMutationPreparationRuntime) {}

  async prepareAdminUserMutation(
    admin: any,
    body: any,
    current: any | null,
  ): Promise<PreparedAdminUserMutation> {
    const email = current
      ? String(current.email || '')
          .trim()
          .toLowerCase()
      : this.runtime.normalizeAccountEmail(body.email);
    if (!email) throw new BadRequestException('Email không được để trống');
    if (!current) await this.runtime.assertEmailCreatableByAdmin(admin, email);

    const role = body.role
      ? await this.runtime.resolveAssignableRole(body.role)
      : current
        ? this.runtime.normalizeRoleCode(current.role, true)
        : await this.runtime.resolveAssignableRole('USER');
    await this.runtime.assertRoleEditable(admin, role, current?.role);
    const organizationNodeIds =
      await this.runtime.resolveUserOrganizationAssignmentNodeIds(
        admin,
        body,
        current,
      );
    const primaryOrganizationNodeId = organizationNodeIds[0] ?? null;
    const assignmentBody =
      body.organizationNodeIds !== undefined
        ? { ...body, organizationNodeId: primaryOrganizationNodeId ?? '' }
        : body;
    const workScopeType = await this.runtime.resolveWorkScopeTypeForAssignment(
      assignmentBody,
      current,
      role,
    );
    const storeUuid = await this.runtime.resolveUserAssignmentStoreUuid(
      admin,
      assignmentBody,
      {
        current,
        workScopeType,
      },
    );
    const personnel = await this.runtime.resolvePersonnelAssignment(
      admin,
      assignmentBody,
      {
        current,
        role,
        storeUuid,
        workScopeType,
      },
    );
    const relationInput = {
      storeUuid,
      departmentCode: personnel.departmentCode,
      jobRoleCode: personnel.jobRoleCode,
      regionCode: personnel.regionCode,
      areaCode: personnel.areaCode,
      organizationNodeId: personnel.organizationNodeId,
    };
    const createData = {
      email,
      password: '',
      firstName: String(body.firstName || email.split('@')[0]).trim(),
      lastName: String(body.lastName || '').trim() || null,
      role,
      status:
        String(body.status || 'yes').toLowerCase() === 'no' ? 'no' : 'yes',
      workScopeType: personnel.workScopeType,
      ...this.runtime.userRelationMutationData(relationInput),
      branchLockedAt: storeUuid ? new Date() : null,
      profileCompletedAt: storeUuid ? new Date() : null,
    };
    const updateData = {
      firstName: body.firstName?.trim() || current?.firstName,
      lastName:
        body.lastName === undefined
          ? current?.lastName
          : String(body.lastName || '').trim() || null,
      role,
      status:
        body.status === undefined
          ? current?.status
          : String(body.status).toLowerCase() === 'no'
            ? 'no'
            : 'yes',
      workScopeType: personnel.workScopeType,
      ...this.runtime.userRelationMutationData(relationInput, {
        disconnectNulls: true,
      }),
      branchLockedAt: storeUuid
        ? (current?.branchLockedAt ?? new Date())
        : null,
      profileCompletedAt: storeUuid
        ? (current?.profileCompletedAt ?? new Date())
        : current?.profileCompletedAt,
    };
    return {
      email,
      role,
      workScopeType: personnel.workScopeType,
      personnel,
      organizationNodeIds,
      createData,
      updateData,
    };
  }
}
