const { S3Client, PutObjectCommand, GetObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl }                                 = require('@aws-sdk/s3-request-presigner');
const { randomUUID }                                   = require('crypto');

// Singleton — shared across the entire process (presign + job fetch)
const s3 = new S3Client({
  region:      process.env.AWS_REGION,
  credentials: {
    accessKeyId:     process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
  },
});

const BUCKET  = process.env.S3_BUCKET;
const EXPIRY  = parseInt(process.env.S3_PRESIGN_EXPIRY || '300', 10);

/**
 * Generate a presigned PUT URL so the Flutter app can upload directly to S3.
 * Returns { key, uploadUrl }.
 */
async function createPresignedUploadUrl(userId, mimeType = 'image/jpeg') {
  const key = `receipts/${userId}/${randomUUID()}`;
  const command = new PutObjectCommand({
    Bucket:      BUCKET,
    Key:         key,
    ContentType: mimeType,
  });
  const uploadUrl = await getSignedUrl(s3, command, { expiresIn: EXPIRY });
  return { key, uploadUrl };
}

/**
 * Fetch an S3 object and return its contents as a Buffer.
 */
async function getObjectBuffer(s3Key) {
  const { Body } = await s3.send(new GetObjectCommand({ Bucket: BUCKET, Key: s3Key }));
  const chunks = [];
  for await (const chunk of Body) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

module.exports = { createPresignedUploadUrl, getObjectBuffer };
