import { FeedbackService } from './feedback.service';

describe('FeedbackService', () => {
  let service: FeedbackService;
  let prisma: {
    feedback: {
      create: jest.Mock;
      update: jest.Mock;
      findMany: jest.Mock;
    };
  };
  let uploadService: { saveFeedbackImages: jest.Mock };

  beforeEach(() => {
    prisma = {
      feedback: {
        create: jest.fn(),
        update: jest.fn(),
        findMany: jest.fn(),
      },
    };
    uploadService = { saveFeedbackImages: jest.fn() };
    service = new FeedbackService(prisma as any, uploadService as any);
  });

  it('creates text-only feedback using function and description fields', async () => {
    const created = { id: 'feedback-1', content: 'created' };
    prisma.feedback.create.mockResolvedValue(created);

    await expect(
      service.create('user-1', {
        functionName: 'FIFO',
        description: 'Sort result is confusing',
      }),
    ).resolves.toBe(created);

    expect(prisma.feedback.create).toHaveBeenCalledWith({
      data: {
        userId: 'user-1',
        content: 'Chức năng: FIFO\nMô tả: Sort result is confusing',
        rating: 5,
      },
    });
    expect(uploadService.saveFeedbackImages).not.toHaveBeenCalled();
  });

  it('appends uploaded image links to feedback content', async () => {
    const file = { originalname: 'image.jpg' } as Express.Multer.File;
    prisma.feedback.create.mockResolvedValue({
      id: 'feedback-1',
      content: 'base',
    });
    prisma.feedback.update.mockResolvedValue({
      id: 'feedback-1',
      content: 'updated',
    });
    uploadService.saveFeedbackImages.mockResolvedValue([
      'https://img.example.com/feedback/feedback-1/feedback-1-0.jpg',
    ]);

    await expect(
      service.create('user-1', { content: 'Raw content', rating: 4 }, [file]),
    ).resolves.toEqual({ id: 'feedback-1', content: 'updated' });

    expect(uploadService.saveFeedbackImages).toHaveBeenCalledWith(
      'feedback-1',
      [file],
    );
    expect(prisma.feedback.update).toHaveBeenCalledWith({
      where: { id: 'feedback-1' },
      data: {
        content:
          'Raw content\nHình ảnh: https://img.example.com/feedback/feedback-1/feedback-1-0.jpg',
      },
    });
  });
});
