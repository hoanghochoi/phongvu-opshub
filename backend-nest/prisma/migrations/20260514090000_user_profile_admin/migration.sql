-- AlterTable
ALTER TABLE "Store"
ADD COLUMN "transferAccountNumber" TEXT,
ADD COLUMN "transferAccountName" TEXT,
ADD COLUMN "transferBankName" TEXT,
ADD COLUMN "transferBankBin" TEXT;

-- AlterTable
ALTER TABLE "User"
ADD COLUMN "avatarUrl" TEXT,
ADD COLUMN "profileCompletedAt" TIMESTAMP(3),
ADD COLUMN "branchLockedAt" TIMESTAMP(3);
