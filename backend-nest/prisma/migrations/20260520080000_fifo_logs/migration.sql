-- CreateEnum
CREATE TYPE "FifoLogType" AS ENUM ('FIFO_CHECK', 'FIFO_SORT');

-- CreateTable
CREATE TABLE "fifo_logs" (
    "id" TEXT NOT NULL,
    "type" "FifoLogType" NOT NULL,
    "query" TEXT NOT NULL,
    "result" TEXT,
    "result_json" JSONB,
    "userId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "fifo_logs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "fifo_logs_userId_idx" ON "fifo_logs"("userId");

-- CreateIndex
CREATE INDEX "fifo_logs_createdAt_idx" ON "fifo_logs"("createdAt");

-- AddForeignKey
ALTER TABLE "fifo_logs" ADD CONSTRAINT "fifo_logs_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
