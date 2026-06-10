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

  it('passes the current admin to feedback list service', async () => {
    feedbackService.getAll.mockResolvedValue([{ id: 'feedback-1' }]);
    const request = { user: { id: 'admin-1', role: 'SUPER_ADMIN' } };

    await expect(controller.getAll(request)).resolves.toEqual([
      { id: 'feedback-1' },
    ]);
    expect(feedbackService.getAll).toHaveBeenCalledWith(request.user);
  });
});
