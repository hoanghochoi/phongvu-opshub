import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildPlan,
  mergeImageLinks,
  normalizeImageLinks,
  parseOptions,
  shouldUpdateExistingCreator,
} from './migrate-n8n-warranty-metadata.mjs';

const imageBaseUrl = 'https://opshub.hoanghochoi.com/uploads';

test('normalizeImageLinks maps legacy n8n app_images URLs to app upload URLs', () => {
  const links = normalizeImageLinks(
    'https://n8n.hoanghochoi.com/app_images/CP62-J12345678/CP62-J12345678-0.jpg; /uploads/CP62-J12345678/CP62-J12345678-1.png',
    imageBaseUrl,
  );

  assert.deepEqual(links, [
    'https://opshub.hoanghochoi.com/uploads/CP62-J12345678/CP62-J12345678-0.jpg',
    'https://opshub.hoanghochoi.com/uploads/CP62-J12345678/CP62-J12345678-1.png',
  ]);
});

test('mergeImageLinks preserves existing app images and deduplicates migrated links', () => {
  const merged = mergeImageLinks(
    'https://opshub.hoanghochoi.com/uploads/CP62-J12345678/existing.jpg;https://n8n.hoanghochoi.com/app_images/CP62-J12345678/CP62-J12345678-0.jpg',
    [
      'https://opshub.hoanghochoi.com/uploads/CP62-J12345678/CP62-J12345678-0.jpg',
      'https://opshub.hoanghochoi.com/uploads/CP62-J12345678/CP62-J12345678-1.jpg',
    ],
    imageBaseUrl,
  );

  assert.deepEqual(merged, [
    'https://opshub.hoanghochoi.com/uploads/CP62-J12345678/existing.jpg',
    'https://opshub.hoanghochoi.com/uploads/CP62-J12345678/CP62-J12345678-0.jpg',
    'https://opshub.hoanghochoi.com/uploads/CP62-J12345678/CP62-J12345678-1.jpg',
  ]);
});

test('buildPlan reconciles existing CP62 warranty rows instead of skipping them', () => {
  const rows = [
    {
      receipt: 'CP62-J12345678',
      legacy_user: 'tech.cp62@phongvu.vn',
      links:
        'https://n8n.hoanghochoi.com/app_images/CP62-J12345678/CP62-J12345678-0.jpg;https://n8n.hoanghochoi.com/app_images/CP62-J12345678/CP62-J12345678-1.jpg',
      created_at: '2026-05-01T00:00:00.000Z',
      updated_at: '2026-05-02T00:00:00.000Z',
    },
  ];
  const appWarranties = new Map([
    [
      'CP62-J12345678',
      {
        id: 'warranty-1',
        receipt: 'CP62-J12345678',
        imageLinks:
          'https://opshub.hoanghochoi.com/uploads/CP62-J12345678/existing.jpg',
        createdBy: {
          id: 'legacy-user',
          email: 'legacy@phongvu.vn',
          password: '',
          status: 'no',
          storeId: null,
        },
      },
    ],
  ]);
  const appUsers = new Map([
    [
      'tech.cp62@phongvu.vn',
      {
        id: 'tech-user',
        email: 'tech.cp62@phongvu.vn',
        password: 'hashed',
        status: 'yes',
        storeId: 'store-62',
      },
    ],
  ]);
  const appStores = new Map([['CP62', { id: 'store-62', storeId: 'CP62' }]]);

  const plan = buildPlan({
    rows,
    appWarranties,
    appUsers,
    appStores,
    imageBaseUrl,
    storeFilter: 'CP62',
  });

  assert.equal(plan.items.length, 1);
  assert.equal(plan.summary.existingWarrantyRows, 1);
  assert.equal(plan.summary.warrantyRowsToCreate, 0);
  assert.equal(plan.summary.existingWarrantyImageRowsToUpdate, 1);
  assert.equal(plan.summary.existingWarrantyCreatorsToUpdate, 1);
  assert.equal(plan.summary.linksToAddToExisting, 2);
});

test('buildPlan filters rows by store code for a CP62 dry run', () => {
  const rows = [
    {
      receipt: 'CP62-J12345678',
      legacy_user: 'tech.cp62@phongvu.vn',
      links: '/app_images/CP62-J12345678/CP62-J12345678-0.jpg',
      updated_at: '2026-05-02T00:00:00.000Z',
    },
    {
      receipt: 'CP01-J12345678',
      legacy_user: 'tech.cp01@phongvu.vn',
      links: '/app_images/CP01-J12345678/CP01-J12345678-0.jpg',
      updated_at: '2026-05-02T00:00:00.000Z',
    },
  ];

  const plan = buildPlan({
    rows,
    appWarranties: new Map(),
    appUsers: new Map(),
    appStores: new Map([['CP62', { id: 'store-62', storeId: 'CP62' }]]),
    imageBaseUrl,
    storeFilter: 'CP62',
  });

  assert.equal(plan.items.length, 1);
  assert.equal(plan.items[0].receipt, 'CP62-J12345678');
  assert.equal(plan.summary.rowsAfterStoreFilter, 1);
  assert.equal(plan.summary.rowsSkippedByStoreFilter, 1);
  assert.equal(plan.summary.warrantyRowsToCreate, 1);
});

test('buildPlan can explicitly reassign existing super admin creators to n8n users', () => {
  const rows = [
    {
      receipt: 'CP62-J26023452',
      legacy_user: 'vu.nl@phongvu-mna.vn',
      links: '/app_images/CP62-J26023452/CP62-J26023452-0.jpg',
      updated_at: '2026-05-02T00:00:00.000Z',
    },
  ];
  const appWarranties = new Map([
    [
      'CP62-J26023452',
      {
        id: 'warranty-1',
        receipt: 'CP62-J26023452',
        imageLinks:
          'https://opshub.hoanghochoi.com/uploads/CP62-J26023452/CP62-J26023452-0.jpg',
        createdBy: {
          id: 'super-admin',
          email: 'super_admin@phongvu-mna.vn',
          password: 'hashed',
          status: 'yes',
          storeId: 'store-62',
        },
      },
    ],
  ]);
  const appUsers = new Map([
    [
      'vu.nl@phongvu-mna.vn',
      {
        id: 'tech-user',
        email: 'vu.nl@phongvu-mna.vn',
        password: 'hashed',
        status: 'yes',
        storeId: 'store-62',
      },
    ],
  ]);
  const common = {
    rows,
    appWarranties,
    appUsers,
    appStores: new Map([['CP62', { id: 'store-62', storeId: 'CP62' }]]),
    imageBaseUrl,
    storeFilter: 'CP62',
  };

  assert.equal(buildPlan(common).summary.existingWarrantyCreatorsToUpdate, 0);
  assert.equal(
    buildPlan({ ...common, reassignExistingCreators: true }).summary
      .existingWarrantyCreatorsToUpdate,
    1,
  );
});
test('buildPlan rewrites stored legacy n8n image hosts even without new links', () => {
  const rows = [
    {
      receipt: 'CP62-J12345678',
      legacy_user: 'tech.cp62@phongvu.vn',
      links:
        'https://n8n.hoanghochoi.com/app_images/CP62-J12345678/CP62-J12345678-0.jpg',
      updated_at: '2026-05-02T00:00:00.000Z',
    },
  ];
  const appWarranties = new Map([
    [
      'CP62-J12345678',
      {
        id: 'warranty-1',
        receipt: 'CP62-J12345678',
        imageLinks:
          'https://n8n.hoanghochoi.com/app_images/CP62-J12345678/CP62-J12345678-0.jpg',
        createdBy: {
          id: 'tech-user',
          email: 'tech.cp62@phongvu.vn',
          password: 'hashed',
          status: 'yes',
          storeId: 'store-62',
        },
      },
    ],
  ]);
  const appUsers = new Map([
    [
      'tech.cp62@phongvu.vn',
      {
        id: 'tech-user',
        email: 'tech.cp62@phongvu.vn',
        password: 'hashed',
        status: 'yes',
        storeId: 'store-62',
      },
    ],
  ]);

  const plan = buildPlan({
    rows,
    appWarranties,
    appUsers,
    appStores: new Map([['CP62', { id: 'store-62', storeId: 'CP62' }]]),
    imageBaseUrl,
    storeFilter: 'CP62',
  });

  assert.equal(plan.summary.existingWarrantyRows, 1);
  assert.equal(plan.summary.existingWarrantyImageRowsToUpdate, 1);
  assert.equal(plan.summary.linksToAddToExisting, 0);
  assert.equal(plan.summary.existingWarrantyCreatorsToUpdate, 0);
});
test('parseOptions supports --store=CP62 and creator updates stay conservative', () => {
  const options = parseOptions(['--store=cp62'], {
    IMAGE_BASE_URL: imageBaseUrl,
  });
  assert.equal(options.storeFilter, 'CP62');
  assert.equal(options.apply, false);
  assert.equal(options.reassignExistingCreators, false);

  const reassignOptions = parseOptions(
    ['--apply', '--store=cp62', '--reassign-existing-creators'],
    { IMAGE_BASE_URL: imageBaseUrl },
  );
  assert.equal(reassignOptions.storeFilter, 'CP62');
  assert.equal(reassignOptions.apply, true);
  assert.equal(reassignOptions.reassignExistingCreators, true);

  assert.equal(
    shouldUpdateExistingCreator(
      {
        email: 'tech.cp62@phongvu.vn',
        status: 'yes',
        password: 'hashed',
        storeId: 'store-62',
      },
      { email: 'tech.cp62@phongvu.vn', storeId: 'store-62' },
      'tech.cp62@phongvu.vn',
    ),
    false,
  );
});
