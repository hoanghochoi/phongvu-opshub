import { FeedbackController } from './feedback.controller';

describe('FeedbackController', () => {
  let controller: FeedbackController;
  let feedbackService: {
    create: jest.Mock;
    getAll: jest.Mock;
  };

  beforeEach(() => {
    feedbackService = {
      create: jest.fn(),
      getAll: jest.fn(),
    };
    controller = new FeedbackController(feedbackService as any);
  });

  it('maps multipart feedback body into service input', async () => {
    const file = { originalname: 'feedback.jpg' } as Express.Multer.File;
    feedbackService.create.mockResolvedValue({ id: 'feedback-1' });

    await expect(
      controller.create(
        { user: { id: 'user-1' } },
        { function: 'Sort', description: 'Needs detail' },
        [file],
      ),
    ).resolves.toEqual({ id: 'feedback-1' });

    expect(feedbackService.create).toHaveBeenCalledWith(
      'user-1',
      {
        content: undefined,
        functionName: 'Sort',
        description: 'Needs detail',
        rating: 5,
      },
      [file],
    );
  });

  it('returns all feedback records', async () => {
    feedbackService.getAll.mockResolvedValue([{ id: 'feedback-1' }]);

    await expect(controller.getAll()).resolves.toEqual([{ id: 'feedback-1' }]);
  });
});
