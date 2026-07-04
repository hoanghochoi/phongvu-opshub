import { ValidationPipe } from '@nestjs/common';
import { GetHomeSummaryQueryDto } from './home-summary.dto';

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

  it('still rejects unexpected query properties', async () => {
    const pipe = createPipe();

    await expect(
      pipe.transform(
        { date: '2026-07-04', unexpected: 'x' },
        { type: 'query', metatype: GetHomeSummaryQueryDto, data: '' },
      ),
    ).rejects.toMatchObject({
      response: {
        message: expect.arrayContaining(['property unexpected should not exist']),
        statusCode: 400,
      },
    });
  });
});
