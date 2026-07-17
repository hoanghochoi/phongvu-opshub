import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { RequireFeature } from '../feature/feature.decorator';
import { FeatureGuard } from '../feature/feature.guard';
import {
  CreateContractAppendixDto,
  ListContractAppendicesDto,
  PreviewContractAppendixDto,
} from './contract-appendices.dto';
import { ContractAppendicesService } from './contract-appendices.service';

@Controller('contract-appendices')
@UseGuards(AuthGuard('jwt'), FeatureGuard)
@RequireFeature(FEATURE_KEYS.CONTRACT_APPENDIX)
export class ContractAppendicesController {
  constructor(private readonly service: ContractAppendicesService) {}

  @Post('preview')
  preview(@Request() req: any, @Body() body: PreviewContractAppendixDto) {
    return this.service.preview(req.user, body);
  }

  @Post()
  create(@Request() req: any, @Body() body: CreateContractAppendixDto) {
    return this.service.create(req.user, body);
  }

  @Get()
  list(@Request() req: any, @Query() query: ListContractAppendicesDto) {
    return this.service.list(req.user, query);
  }

  @Get(':id')
  detail(@Request() req: any, @Param('id') id: string) {
    return this.service.detail(req.user, id);
  }
}
