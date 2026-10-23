const fs = require('fs');
const path = require('path');

const BUCKET = (process.env.SUPABASE_LOGO_BUCKET || 'school-assets').trim();

function supabaseConfig() {
  const url = String(process.env.SUPABASE_URL || '').replace(/\/+$/, '');
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
  return url && key ? { url, key } : null;
}

async function uploadSchoolLogo(pngBuffer) {
  const config = supabaseConfig();
  if (config) {
    const bucketUrl = `${config.url}/storage/v1/bucket`;
    const headers = {
      apikey: config.key,
      Authorization: `Bearer ${config.key}`,
      'Content-Type': 'application/json',
    };
    const create = await fetch(bucketUrl, {
      method: 'POST', headers,
      body: JSON.stringify({ id: BUCKET, name: BUCKET, public: true }),
      signal: AbortSignal.timeout(10000),
    });
    if (!create.ok && create.status !== 409 && create.status !== 400) {
      const detail = await create.text().catch(() => '');
      throw new Error(`Supabase Storage bucket setup failed (${create.status}): ${detail.slice(0, 180)}`);
    }
    if (!create.ok) {
      const info = await fetch(`${bucketUrl}/${encodeURIComponent(BUCKET)}`, {
        headers: { apikey: config.key, Authorization: `Bearer ${config.key}` },
        signal: AbortSignal.timeout(10000),
      });
      if (!info.ok) {
        const detail = await info.text().catch(() => '');
        throw new Error(`Supabase Storage bucket could not be opened (${info.status}): ${detail.slice(0, 180)}`);
      }
      const bucket = await info.json();
      if (bucket.public !== true) {
        const update = await fetch(`${bucketUrl}/${encodeURIComponent(BUCKET)}`, {
          method: 'PUT',
          headers,
          body: JSON.stringify({ public: true }),
          signal: AbortSignal.timeout(10000),
        });
        if (!update.ok) {
          const detail = await update.text().catch(() => '');
          throw new Error(`Supabase logo bucket must allow public reads (${update.status}): ${detail.slice(0, 180)}`);
        }
      }
    }

    const objectPath = 'school/logo.png';
    const upload = await fetch(
      `${config.url}/storage/v1/object/${encodeURIComponent(BUCKET)}/${objectPath}`,
      {
        method: 'POST',
        headers: {
          apikey: config.key,
          Authorization: `Bearer ${config.key}`,
          'Content-Type': 'image/png',
          'x-upsert': 'true',
          'cache-control': '3600',
        },
        body: pngBuffer,
        signal: AbortSignal.timeout(20000),
      },
    );
    if (!upload.ok) {
      const detail = await upload.text().catch(() => '');
      throw new Error(`Supabase logo upload failed (${upload.status}): ${detail.slice(0, 180)}`);
    }
    return `${config.url}/storage/v1/object/public/${encodeURIComponent(BUCKET)}/${objectPath}?v=${Date.now()}`;
  }

  if (process.env.VERCEL) {
    throw new Error('Supabase Storage is not configured. Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the Vercel project settings.');
  }

  const logoDir = process.env.VERCEL_UPLOAD_DIR
    ? path.join(process.env.VERCEL_UPLOAD_DIR, 'logos')
    : path.join(__dirname, '..', 'uploads', 'logos');
  fs.mkdirSync(logoDir, { recursive: true });
  fs.writeFileSync(path.join(logoDir, 'school_logo.png'), pngBuffer);
  return '/uploads/logos/school_logo.png';
}

async function loadSchoolLogo(source) {
  if (!source) {
    const bundled = path.join(__dirname, '..', 'assets', 'school_logo.png');
    return fs.existsSync(bundled) ? bundled : null;
  }
  const value = String(source);
  if (/^https?:\/\//i.test(value)) {
    try {
      const response = await fetch(value, { signal: AbortSignal.timeout(8000) });
      if (!response.ok) return null;
      return Buffer.from(await response.arrayBuffer());
    } catch (_) {
      return null;
    }
  }
  const filename = path.basename(value);
  const localPath = value.startsWith('/uploads/logos/')
    ? path.join(process.env.VERCEL_UPLOAD_DIR || path.join(__dirname, '..', 'uploads'), 'logos', filename)
    : path.resolve(value);
  if (fs.existsSync(localPath)) return localPath;
  const bundled = path.join(__dirname, '..', 'assets', 'school_logo.png');
  return fs.existsSync(bundled) ? bundled : null;
}

module.exports = { uploadSchoolLogo, loadSchoolLogo };
