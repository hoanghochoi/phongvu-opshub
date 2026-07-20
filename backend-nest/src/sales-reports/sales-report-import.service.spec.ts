import { SalesReportImportService } from './sales-report-import.service';

describe('SalesReportImportService', () => {
  const file = {
    size: 128,
    buffer: Buffer.from('file'),
  } as Express.Multer.File;
  const hash = 'a'.repeat(64);
  const actor = {
    id: 'manager-1',
    email: 'manager@example.com',
    firstName: 'Quản lý',
    lastName: 'SR',
    role: 'USER',
    store: { storeId: 'CP02' },
    organizationAssignments: [],
  };

  function setup() {
    const parsedRows = [
      parsedRow({
        rowNumber: 2,
        salespersonEmail: 'sa@example.com',
        fingerprint: 'fingerprint-1',
      }),
      parsedRow({
        rowNumber: 3,
        salespersonEmail: 'missing@example.com',
        fingerprint: 'fingerprint-2',
      }),
    ];
    const prisma = {
      store: {
        findMany: jest.fn().mockResolvedValue([
          {
            storeId: 'CP02',
            storeName: 'Showroom CP02',
            organizationNodeId: 'node-cp02',
            organizationNode: { displayName: 'CP02' },
            areaCode: 'HCM',
            area: { code: 'HCM', region: { code: 'SOUTH' } },
          },
        ]),
      },
      user: {
        findUnique: jest.fn().mockResolvedValue(actor),
        findMany: jest.fn().mockResolvedValue([
          {
            id: 'sa-1',
            email: 'sa@example.com',
            firstName: 'Nhân viên',
            lastName: 'A',
            status: 'yes',
            store: { storeId: 'CP02' },
            organizationAssignments: [],
          },
        ]),
      },
      salesReport: {
        findMany: jest.fn().mockResolvedValue([]),
        create: jest.fn().mockResolvedValue({ id: 'report-1' }),
      },
      salesReportImportBatch: {
        create: jest.fn().mockResolvedValue({ id: 'batch-1' }),
        update: jest.fn().mockResolvedValue({ id: 'batch-1' }),
      },
    };
    const parser = {
      parse: jest.fn().mockReturnValue({
        fileName: 'khach-chua-mua.xlsx',
        fileHash: hash,
        totalRows: parsedRows.length,
        rows: parsedRows,
      }),
    };
    const categories = {
      listCategories: jest.fn().mockResolvedValue([
        {
          id: 'LAPTOP',
          catGroupName: 'Laptop',
          catGroupNameVi: 'Laptop',
        },
      ]),
    };
    return {
      prisma,
      parser,
      service: new SalesReportImportService(
        prisma as never,
        parser as never,
        categories as never,
      ),
    };
  }

  it('previews valid rows and keeps unmatched employees unassigned', async () => {
    const { service } = setup();

    const preview = await service.preview(actor, file);

    expect(preview).toMatchObject({
      totalRows: 2,
      validRows: 2,
      invalidRows: 0,
      duplicateRows: 0,
      purchasedRows: 0,
      unassignedRows: 1,
    });
    expect(preview.rows[1]).toMatchObject({
      rowNumber: 3,
      status: 'VALID',
    });
    expect(preview.rows[1].warnings).toContain(
      'Chưa khớp được nhân viên đang hoạt động tại SR; hồ sơ sẽ để chưa phân công.',
    );
  });

  it('commits the previewed file idempotently with follow-up cases', async () => {
    const { service, prisma } = setup();

    const result = await service.commit(actor, file, hash);

    expect(result).toMatchObject({
      batchId: 'batch-1',
      importedRows: 2,
      unassignedRows: 1,
    });
    expect(prisma.salesReport.create).toHaveBeenCalledTimes(2);
    expect(prisma.salesReport.create.mock.calls[0][0].data).toMatchObject({
      reportType: 'NOT_PURCHASED',
      entrySource: 'HISTORICAL_IMPORT',
      importFingerprint: 'fingerprint-1',
      consultedSolutionAnswer: 'NOT_CAPTURED',
      experiencedAnswer: 'NOT_CAPTURED',
      sourceSalespersonCode: 'NV001',
      createdBy: { connect: { id: 'sa-1' } },
      sourceFollowUpCase: {
        create: {
          status: 'OPEN',
          assigneeUserId: 'sa-1',
          priorityAt: new Date('2026-07-20T03:15:00.000Z'),
        },
      },
    });
    expect(prisma.salesReport.create.mock.calls[1][0].data).toMatchObject({
      createdByEmail: 'missing@example.com',
      createdByName: null,
      sourceFollowUpCase: {
        create: { assigneeUserId: null, assigneeEmail: null },
      },
    });
    expect(prisma.salesReportImportBatch.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'batch-1' },
        data: expect.objectContaining({
          status: 'COMPLETED',
          importedRows: 2,
        }),
      }),
    );
  });

  it('separates purchased, duplicate and invalid rows from valid imports', async () => {
    const { service, prisma, parser } = setup();
    parser.parse.mockReturnValue({
      fileName: 'khach-chua-mua.xlsx',
      fileHash: hash,
      totalRows: 4,
      rows: [
        parsedRow({ fingerprint: 'valid' }),
        parsedRow({
          rowNumber: 3,
          fingerprint: 'purchased',
          purchased: true,
          notPurchasedReason: null,
        }),
        parsedRow({ rowNumber: 4, fingerprint: 'duplicate' }),
        parsedRow({
          rowNumber: 5,
          fingerprint: 'invalid',
          storeCode: 'OUTSIDE_SCOPE',
        }),
      ],
    });
    prisma.salesReport.findMany.mockResolvedValue([
      { importFingerprint: 'duplicate' },
    ]);

    const preview = await service.preview(actor, file);

    expect(preview).toMatchObject({
      totalRows: 4,
      validRows: 1,
      purchasedRows: 1,
      duplicateRows: 1,
      invalidRows: 1,
    });
    expect(preview.rows.map((row) => row.status)).toEqual([
      'VALID',
      'PURCHASED',
      'DUPLICATE',
      'INVALID',
    ]);
    expect(preview.rows[3].errors).toContain(
      'SR không tồn tại hoặc không thuộc phạm vi được gán.',
    );
  });

  it('rejects commit when the selected file changed after preview', async () => {
    const { service, prisma } = setup();

    await expect(service.commit(actor, file, 'b'.repeat(64))).rejects.toThrow(
      'File đã thay đổi sau khi xem trước',
    );
    expect(prisma.salesReportImportBatch.create).not.toHaveBeenCalled();
  });
});

function parsedRow(overrides: Record<string, unknown>) {
  return {
    rowNumber: 2,
    submittedAt: new Date('2026-07-20T03:15:00.000Z'),
    salespersonEmail: 'sa@example.com',
    sourceSalespersonCode: 'NV001',
    customerName: 'Khách A',
    customerPhone: '0912345678',
    customerNeed: 'MacBook Air',
    categoryValue: 'Laptop',
    purchased: false,
    notPurchasedReason: 'CUSTOMER_BROWSING',
    notPurchasedOtherReason: null,
    storeCode: 'CP02',
    customerContactChannels: ['PHONE'],
    errors: [],
    warnings: [],
    fingerprint: 'fingerprint-1',
    ...overrides,
  };
}
