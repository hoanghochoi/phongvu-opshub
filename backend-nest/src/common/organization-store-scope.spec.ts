import { storesForOrganizationNodeTree } from './organization-store-scope';

describe('organization store scope helpers', () => {
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
      stores: [],
      children: [],
      parent: {
        id: 'store-cp62',
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
});
