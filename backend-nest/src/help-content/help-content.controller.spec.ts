import { HelpContentController } from './help-content.controller';

describe('HelpContentController', () => {
  function createController() {
    const service = {
      getPublicContent: jest.fn().mockResolvedValue({ source: 'runtime' }),
      getAdminPages: jest.fn().mockResolvedValue({ pages: [] }),
      createPage: jest.fn().mockResolvedValue({ key: 'guide' }),
      updatePage: jest.fn().mockResolvedValue({ key: 'guide' }),
      seedFromDocs: jest.fn().mockResolvedValue({ seeded: true }),
      uploadAsset: jest.fn().mockResolvedValue({ imageUrl: '/uploads/help.png' }),
    };
    return {
      controller: new HelpContentController(service as any),
      service,
    };
  }

  it('returns the public help runtime snapshot', async () => {
    const { controller, service } = createController();
    const req = { user: null };

    await expect(controller.getPublicContent(req)).resolves.toEqual({
      source: 'runtime',
    });
    expect(service.getPublicContent).toHaveBeenCalledWith(null);
  });

  it('forwards authenticated admin users to the page list service', async () => {
    const { controller, service } = createController();
    const req = { user: { id: 'admin-1', role: 'SUPER_ADMIN' } };

    await expect(controller.getAdminPages(req)).resolves.toEqual({ pages: [] });
    expect(service.getAdminPages).toHaveBeenCalledWith(req.user);
  });

  it('forwards create, update, and seed requests with the authenticated user', async () => {
    const { controller, service } = createController();
    const req = { user: { id: 'admin-1', role: 'SUPER_ADMIN' } };

    await controller.createPage(req, { key: 'guide', title: 'Guide' } as any);
    await controller.updatePage(req, 'guide', { title: 'Guide mới' } as any);
    await controller.seedFromDocs(req, { overwriteExisting: true } as any);

    expect(service.createPage).toHaveBeenCalledWith(req.user, {
      key: 'guide',
      title: 'Guide',
    });
    expect(service.updatePage).toHaveBeenCalledWith(req.user, 'guide', {
      title: 'Guide mới',
    });
    expect(service.seedFromDocs).toHaveBeenCalledWith(req.user, {
      overwriteExisting: true,
    });
  });

  it('forwards help image uploads with the authenticated user', async () => {
    const { controller, service } = createController();
    const req = { user: { id: 'admin-1', role: 'SUPER_ADMIN' } };
    const file = { originalname: 'setup.png', size: 1200 } as any;

    await expect(
      controller.uploadAsset(req, { pageKey: 'guide' } as any, file),
    ).resolves.toEqual({ imageUrl: '/uploads/help.png' });

    expect(service.uploadAsset).toHaveBeenCalledWith(
      req.user,
      { pageKey: 'guide' },
      file,
    );
  });
});
