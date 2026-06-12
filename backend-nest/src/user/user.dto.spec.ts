import { validate } from 'class-validator';
import { AdminUserDto } from './user.dto';

describe('AdminUserDto', () => {
  it('accepts organizationNodeId for tree-only user scope assignment', async () => {
    const dto = Object.assign(new AdminUserDto(), {
      email: 'staff@phongvu.vn',
      firstName: 'Staff',
      workScopeType: 'STORE',
      organizationNodeId: 'org-store-cp62',
    });

    await expect(validate(dto)).resolves.toHaveLength(0);
  });
});
