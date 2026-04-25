import { Test, TestingModule } from '@nestjs/testing';
import { WarrantyController } from './warranty.controller';

describe('WarrantyController', () => {
  let controller: WarrantyController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [WarrantyController],
    }).compile();

    controller = module.get<WarrantyController>(WarrantyController);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });
});
