import { ValidationPipe } from '@nestjs/common';
import {
  GetHomeSummaryDetailsQueryDto,
  GetHomeSummaryDetailsV2QueryDto,
  GetHomeSummaryQueryDto,
} from './home-summary.dto';

describe('GetHomeSummaryQueryDto', () => {
  function createPipe() {
    return new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: true },
    });
  }

  it('accepts the date query used by the home dashboard', async () => {
    const pipe = createPipe();

    await expect(
      pipe.transform(
        { date: '2026-07-04' },
        { type: 'query', metatype: GetHomeSummaryQueryDto, data: '' },
      ),
    ).resolves.toMatchObject({ date: '2026-07-04' });
  });

  it.each(['true', 'false'])(
    'accepts the strict daily series value %s',
    async (includeDailySeries) => {
      const pipe = createPipe();

      await expect(
        pipe.transform(
          { includeDailySeries },
          { type: 'query', metatype: GetHomeSummaryQueryDto, data: '' },
        ),
      ).resolves.toMatchObject({ includeDailySeries });
    },
  );

  it.each(['true', 'false'])(
    'accepts the strict comparison value %s',
    async (includeComparisons) => {
      const pipe = createPipe();

      await expect(
        pipe.transform(
          { includeComparisons },
          { type: 'query', metatype: GetHomeSummaryQueryDto, data: '' },
        ),
      ).resolves.toMatchObject({ includeComparisons });
    },
  );

  it.each(['TRUE', '1', 'yes', ''])(
    'rejects the non-contract comparison value %s',
    async (includeComparisons) => {
      const pipe = createPipe();

      await expect(
        pipe.transform(
          { includeComparisons },
          { type: 'query', metatype: GetHomeSummaryQueryDto, data: '' },
        ),
      ).rejects.toMatchObject({
        response: {
          message: expect.arrayContaining([
            'Tùy chọn so sánh theo kỳ chỉ nhận true hoặc false.',
          ]),
          statusCode: 400,
        },
      });
    },
  );

  it.each(['TRUE', '1', 'yes', ''])(
    'rejects the non-contract daily series value %s',
    async (includeDailySeries) => {
      const pipe = createPipe();

      await expect(
        pipe.transform(
          { includeDailySeries },
          { type: 'query', metatype: GetHomeSummaryQueryDto, data: '' },
        ),
      ).rejects.toMatchObject({
        response: {
          message: expect.arrayContaining([
            'Tùy chọn chuỗi theo ngày chỉ nhận true hoặc false.',
          ]),
          statusCode: 400,
        },
      });
    },
  );

  it('does not accept the summary-only option on detail routes', async () => {
    const pipe = createPipe();

    await expect(
      pipe.transform(
        { includeDailySeries: 'true' },
        {
          type: 'query',
          metatype: GetHomeSummaryDetailsQueryDto,
          data: '',
        },
      ),
    ).rejects.toMatchObject({
      response: {
        message: expect.arrayContaining([
          'property includeDailySeries should not exist',
        ]),
        statusCode: 400,
      },
    });
  });

  it('does not accept comparisons on detail routes', async () => {
    const pipe = createPipe();

    await expect(
      pipe.transform(
        { includeComparisons: 'true' },
        {
          type: 'query',
          metatype: GetHomeSummaryDetailsQueryDto,
          data: '',
        },
      ),
    ).rejects.toMatchObject({
      response: {
        message: expect.arrayContaining([
          'property includeComparisons should not exist',
        ]),
        statusCode: 400,
      },
    });
  });

  it('still rejects unexpected query properties', async () => {
    const pipe = createPipe();

    await expect(
      pipe.transform(
        { date: '2026-07-04', unexpected: 'x' },
        { type: 'query', metatype: GetHomeSummaryQueryDto, data: '' },
      ),
    ).rejects.toMatchObject({
      response: {
        message: expect.arrayContaining([
          'property unexpected should not exist',
        ]),
        statusCode: 400,
      },
    });
  });

  it('accepts bounded detail limits for dashboard detail tables', async () => {
    const pipe = createPipe();

    await expect(
      pipe.transform(
        { startDate: '2026-07-04', endDate: '2026-07-04', limit: '200' },
        {
          type: 'query',
          metatype: GetHomeSummaryDetailsQueryDto,
          data: '',
        },
      ),
    ).resolves.toMatchObject({
      startDate: '2026-07-04',
      endDate: '2026-07-04',
      limit: 200,
    });
  });

  it('rejects oversized dashboard detail limits', async () => {
    const pipe = createPipe();

    await expect(
      pipe.transform(
        { limit: '501' },
        {
          type: 'query',
          metatype: GetHomeSummaryDetailsQueryDto,
          data: '',
        },
      ),
    ).rejects.toMatchObject({
      response: {
        message: expect.arrayContaining(['limit must not be greater than 500']),
        statusCode: 400,
      },
    });
  });

  it('accepts bounded cursor detail v2 queries', async () => {
    const pipe = createPipe();

    await expect(
      pipe.transform(
        {
          kind: 'NOT_PURCHASED',
          cursor: 'cursor-value',
          limit: '100',
        },
        {
          type: 'query',
          metatype: GetHomeSummaryDetailsV2QueryDto,
          data: '',
        },
      ),
    ).resolves.toMatchObject({
      kind: 'NOT_PURCHASED',
      cursor: 'cursor-value',
      limit: 100,
    });
  });

  it('rejects unknown detail v2 kinds and limits above 100', async () => {
    const pipe = createPipe();

    await expect(
      pipe.transform(
        { kind: 'RAW_DATABASE_ROWS', limit: '101' },
        {
          type: 'query',
          metatype: GetHomeSummaryDetailsV2QueryDto,
          data: '',
        },
      ),
    ).rejects.toMatchObject({
      response: {
        message: expect.arrayContaining([
          expect.stringContaining('kind must be one of'),
          'limit must not be greater than 100',
        ]),
        statusCode: 400,
      },
    });
  });
});
