/**
 * OCR Service — multi-provider receipt extraction.
 *
 * Supported providers (set OCR_PROVIDER in .env):
 *   'veryfi'   — Veryfi API (recommended, structured output)
 *   'textract' — AWS Textract (fallback, requires more parsing)
 *
 * All providers return the same normalized shape:
 * {
 *   provider:      string,
 *   store_name:    string | null,
 *   purchase_date: string (YYYY-MM-DD) | null,
 *   total_amount:  number | null,
 *   currency:      string,
 *   confidence:    number (0–100),
 *   items: [{ description, barcode, quantity, unit_price, total_price }]
 * }
 */

const https  = require('https');
const crypto = require('crypto');
const logger = require('../config/logger');

async function extractReceipt(s3Key) {
  const provider = (process.env.OCR_PROVIDER || 'veryfi').toLowerCase();
  logger.info('ocr_start', { provider, s3Key });

  try {
    let result;
    if (provider === 'veryfi')   result = await extractVeryfi(s3Key);
    else if (provider === 'textract') result = await extractTextract(s3Key);
    else throw new Error(`Unknown OCR provider: ${provider}`);

    logger.info('ocr_done', {
      provider,
      s3Key,
      store:      result.store_name,
      date:       result.purchase_date,
      items:      result.items.length,
      confidence: result.confidence,
    });

    return result;
  } catch (err) {
    logger.error('ocr_failed', { provider, s3Key, error: err.message });
    throw err;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Veryfi
// ─────────────────────────────────────────────────────────────────────────────

async function extractVeryfi(s3Key) {
  const s3Url  = buildS3Url(s3Key);
  const body   = JSON.stringify({ file_url: s3Url, auto_delete: true });
  const authHeader = buildVeryfiAuth(body);

  const raw = await httpsRequest({
    hostname: 'api.veryfi.com',
    path:     '/api/v8/partner/documents',
    method:   'POST',
    headers: {
      'Content-Type':  'application/json',
      'Accept':        'application/json',
      'CLIENT-ID':     process.env.VERYFI_CLIENT_ID,
      'AUTHORIZATION': authHeader,
    },
    body,
  });

  if (raw.error) throw new Error(`Veryfi error: ${raw.error}`);
  return normalizeVeryfi(raw);
}

function buildVeryfiAuth(bodyStr) {
  // Veryfi uses apikey authentication for most plans
  return `apikey ${process.env.VERYFI_USERNAME}:${process.env.VERYFI_API_KEY}`;
}

function normalizeVeryfi(raw) {
  const dateStr = extractDate(raw.date);

  const items = (raw.line_items || [])
    .filter((li) => li.description || li.total)
    .map((li) => ({
      description: cleanText(li.description),
      barcode:     li.sku || li.barcode || null,
      quantity:    parseFloat(li.quantity) || 1,
      unit_price:  parseFloat(li.unit_price) || null,
      total_price: parseFloat(li.total) || null,
    }));

  // Veryfi gives a confidence score per document
  const confidence = typeof raw.ocr_confidence === 'number'
    ? Math.round(raw.ocr_confidence * 100)
    : 80; // assume reasonable if not present

  return {
    provider:      'veryfi',
    store_name:    raw.vendor?.name ?? null,
    purchase_date: dateStr,
    total_amount:  parseFloat(raw.total) || null,
    currency:      raw.currency_code || 'USD',
    confidence,
    items,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// AWS Textract
// ─────────────────────────────────────────────────────────────────────────────

async function extractTextract(s3Key) {
  // Textract requires the AWS SDK — loaded lazily so the rest of the app
  // doesn't break if @aws-sdk packages are not available.
  const {
    TextractClient,
    AnalyzeExpenseCommand,
  } = require('@aws-sdk/client-textract');

  const client = new TextractClient({ region: process.env.AWS_REGION });

  const command = new AnalyzeExpenseCommand({
    Document: {
      S3Object: {
        Bucket: process.env.S3_BUCKET,
        Name:   s3Key,
      },
    },
  });

  const response = await client.send(command);
  return normalizeTextract(response);
}

function normalizeTextract(response) {
  // Textract AnalyzeExpense returns ExpenseDocuments[]
  const doc = response.ExpenseDocuments?.[0];
  if (!doc) throw new Error('Textract returned no expense documents');

  const summaryFields = doc.SummaryFields || [];
  const lineItems     = doc.LineItemGroups?.[0]?.LineItems || [];

  const get = (type) =>
    summaryFields.find((f) => f.Type?.Text === type)?.ValueDetection?.Text ?? null;

  const storeName    = get('NAME') ?? get('VENDOR_NAME');
  const dateStr      = extractDate(get('INVOICE_RECEIPT_DATE') ?? get('ORDER_DATE'));
  const totalStr     = get('TOTAL') ?? get('AMOUNT_DUE') ?? get('SUBTOTAL');
  const totalAmount  = totalStr ? parseFloat(totalStr.replace(/[^0-9.]/g, '')) : null;

  const items = lineItems.map((li) => {
    const expFields = li.LineItemExpenseFields || [];
    const getF = (t) =>
      expFields.find((f) => f.Type?.Text === t)?.ValueDetection?.Text ?? null;

    return {
      description: cleanText(getF('ITEM') ?? getF('PRODUCT_CODE')),
      barcode:     null, // Textract doesn't extract barcodes from expense docs
      quantity:    parseFloat(getF('QUANTITY') || '1') || 1,
      unit_price:  parseFloat((getF('UNIT_PRICE') || '').replace(/[^0-9.]/g, '')) || null,
      total_price: parseFloat((getF('PRICE') || '').replace(/[^0-9.]/g, '')) || null,
    };
  });

  // Textract returns per-block confidence — average the summary field confidences
  const confs = summaryFields.map((f) => f.ValueDetection?.Confidence ?? 0);
  const confidence = confs.length
    ? Math.round(confs.reduce((a, b) => a + b, 0) / confs.length)
    : 70;

  return {
    provider:      'textract',
    store_name:    storeName,
    purchase_date: dateStr,
    total_amount:  totalAmount,
    currency:      'USD',
    confidence,
    items,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

function buildS3Url(key) {
  return `https://${process.env.S3_BUCKET}.s3.${process.env.AWS_REGION}.amazonaws.com/${key}`;
}

/**
 * Parse various date formats into YYYY-MM-DD.
 * Handles: "2024-03-15", "03/15/2024", "15-Mar-2024", "March 15, 2024"
 */
function extractDate(raw) {
  if (!raw) return null;
  const str = raw.trim();

  // Already ISO
  if (/^\d{4}-\d{2}-\d{2}/.test(str)) return str.slice(0, 10);

  // Try native Date parse (handles most common formats)
  const d = new Date(str);
  if (!isNaN(d.getTime())) {
    return d.toISOString().slice(0, 10);
  }

  // MM/DD/YYYY or DD/MM/YYYY (ambiguous — assume MM/DD for US receipts)
  const slashMatch = str.match(/^(\d{1,2})\/(\d{1,2})\/(\d{2,4})$/);
  if (slashMatch) {
    const [, m, d2, y] = slashMatch;
    const year = y.length === 2 ? `20${y}` : y;
    return `${year}-${m.padStart(2, '0')}-${d2.padStart(2, '0')}`;
  }

  logger.warn('ocr_date_parse_failed', { raw });
  return null;
}

function cleanText(str) {
  if (!str) return null;
  return str.trim().replace(/\s+/g, ' ') || null;
}

function httpsRequest({ hostname, path, method, headers, body }) {
  return new Promise((resolve, reject) => {
    const req = https.request({ hostname, path, method, headers }, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch {
          reject(new Error(`Failed to parse response from ${hostname}`));
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

module.exports = { extractReceipt };
