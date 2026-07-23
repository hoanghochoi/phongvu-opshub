import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { MapVietinBigQueryBackfillService } from './map-vietin-bigquery-backfill.service';
import { MapVietinBigQueryRowMapper } from './map-vietin-bigquery-row.mapper';
import { MapVietinBigQueryStorageWriterService } from './map-vietin-bigquery-storage-writer.service';
import { MapVietinBigQueryWorkerService } from './map-vietin-bigquery-worker.service';

@Module({
  imports: [PrismaModule],
  providers: [
    MapVietinBigQueryBackfillService,
    MapVietinBigQueryRowMapper,
    MapVietinBigQueryStorageWriterService,
    MapVietinBigQueryWorkerService,
  ],
})
export class MapVietinBigQueryModule {}
