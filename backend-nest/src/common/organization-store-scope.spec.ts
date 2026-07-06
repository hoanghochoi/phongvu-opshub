import {
  organizationNodeStoreTreeInclude,
  storesForOrganizationNodeTree,
} from './organization-store-scope';

describe('organization store scope helpers', () => {
  it('loads the direct parent subtree needed by inherited Lv5 scopes', () => {
    const include = organizationNodeStoreTreeInclude(2) as any;

    expect(include.parent.include.children).toBeDefined();
    expect(include.parent.include.children.include.children).toBeDefined();
  });

  it('collects descendant showroom stores for assigned region nodes', () => {
    const stores = storesForOrganizationNodeTree({
      id: 'region-hcm',
      stores: [],
      children: [
        {
          id: 'store-cp62',
          stores: [{ storeId: 'CP62', storeName: 'CP62' }],
          children: [],
        },
        {
          id: 'store-cp75',
          stores: [{ storeId: 'CP75', storeName: 'CP75' }],
          children: [],
        },
      ],
    });

    expect(stores.map((store) => store.storeId)).toEqual(['CP62', 'CP75']);
  });

  it('keeps Lv5 assignments scoped to the direct parent showroom', () => {
    const stores = storesForOrganizationNodeTree({
      id: 'store-cp62-pos-cash',
      type: 'LV5_POSITION',
      stores: [],
      children: [],
      parent: {
        id: 'store-cp62',
        type: 'LV4_STORE',
        stores: [{ storeId: 'CP62', storeName: 'CP62' }],
        children: [
          {
            id: 'store-cp75',
            stores: [{ storeId: 'CP75', storeName: 'CP75' }],
            children: [],
          },
        ],
      },
    });

    expect(stores.map((store) => store.storeId)).toEqual(['CP62']);
  });

  it('inherits every descendant showroom when an Lv5 position is under an area', () => {
    const stores = storesForOrganizationNodeTree({
      id: 'area-hcm-1-pos-manager',
      type: 'LV5_POSITION',
      stores: [],
      children: [],
      parent: {
        id: 'area-hcm-1',
        type: 'LV3_AREA',
        stores: [],
        children: [
          {
            id: 'store-cp62',
            type: 'LV4_STORE',
            stores: [{ storeId: 'CP62', storeName: 'CP62' }],
            children: [],
          },
          {
            id: 'store-cp75',
            type: 'LV4_STORE',
            stores: [{ storeId: 'CP75', storeName: 'CP75' }],
            children: [],
          },
        ],
      },
    });

    expect(stores.map((store) => store.storeId)).toEqual(['CP62', 'CP75']);
  });
});
