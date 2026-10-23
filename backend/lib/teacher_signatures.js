const fs = require('fs');
const path = require('path');
const pool = require('../db');

const bucket = (process.env.SUPABASE_LOGO_BUCKET || 'school-assets').trim();
const supabase = () => {
  const url = String(process.env.SUPABASE_URL || '').replace(/\/+$/, '');
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
  return url && key ? { url, key } : null;
};

async function uploadTeacherSignature(buffer, teacherId) {
  const cfg = supabase();
  if (cfg) {
    const headers = { apikey: cfg.key, Authorization: `Bearer ${cfg.key}`, 'Content-Type': 'application/json' };
    const bucketUrl = `${cfg.url}/storage/v1/bucket`;
    const create = await fetch(bucketUrl, { method: 'POST', headers,
      body: JSON.stringify({ id: bucket, name: bucket, public: true }), signal: AbortSignal.timeout(10000) });
    if (!create.ok && create.status !== 409 && create.status !== 400) {
      throw new Error(`Supabase Storage bucket setup failed (${create.status})`);
    }
    if (!create.ok) {
      const info = await fetch(`${bucketUrl}/${encodeURIComponent(bucket)}`, {
        headers: { apikey: cfg.key, Authorization: `Bearer ${cfg.key}` }, signal: AbortSignal.timeout(10000),
      });
      if (!info.ok) throw new Error(`Supabase Storage bucket could not be opened (${info.status})`);
      if ((await info.json()).public !== true) {
        const update = await fetch(`${bucketUrl}/${encodeURIComponent(bucket)}`, {
          method: 'PUT', headers, body: JSON.stringify({ public: true }), signal: AbortSignal.timeout(10000),
        });
        if (!update.ok) throw new Error(`Supabase signature bucket must allow public reads (${update.status})`);
      }
    }
    const object = `teachers/signatures/teacher_${teacherId}.png`;
    const upload = await fetch(`${cfg.url}/storage/v1/object/${encodeURIComponent(bucket)}/${object}`, {
      method: 'POST', headers: { apikey: cfg.key, Authorization: `Bearer ${cfg.key}`, 'Content-Type': 'image/png', 'x-upsert': 'true', 'cache-control': '3600' },
      body: buffer, signal: AbortSignal.timeout(20000),
    });
    if (!upload.ok) throw new Error(`Supabase signature upload failed (${upload.status}): ${(await upload.text().catch(() => '')).slice(0, 180)}`);
    return `${cfg.url}/storage/v1/object/public/${encodeURIComponent(bucket)}/${object}?v=${Date.now()}`;
  }
  if (process.env.VERCEL) throw new Error('Supabase Storage is not configured. Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in Vercel.');
  const dir = process.env.VERCEL_UPLOAD_DIR ? path.join(process.env.VERCEL_UPLOAD_DIR, 'signatures') : path.join(__dirname, '..', 'uploads', 'signatures');
  fs.mkdirSync(dir, { recursive: true });
  const name = `sig_t${teacherId}.png`;
  fs.writeFileSync(path.join(dir, name), buffer);
  return `/uploads/signatures/${name}`;
}

async function loadTeacherSignature(value) {
  if (!value) return null;
  const v = String(value);
  if (/^https?:\/\//i.test(v)) {
    try { const r = await fetch(v, { signal: AbortSignal.timeout(8000) }); return r.ok ? Buffer.from(await r.arrayBuffer()) : null; } catch (_) { return null; }
  }
  const filename = path.basename(v);
  const dir = process.env.VERCEL_UPLOAD_DIR ? path.join(process.env.VERCEL_UPLOAD_DIR, 'signatures') : path.join(__dirname, '..', 'uploads', 'signatures');
  const p = path.join(dir, filename);
  return fs.existsSync(p) ? fs.readFileSync(p) : null;
}

async function deleteTeacherSignature(value) {
  if (!value) return;
  const v = String(value);
  const cfg = supabase();
  if (/^https?:\/\//i.test(v) && cfg) {
    const marker = `/object/public/${encodeURIComponent(bucket)}/`;
    const index = v.indexOf(marker);
    if (index >= 0) {
      const object = decodeURIComponent(v.slice(index + marker.length).split('?')[0]);
      await fetch(`${cfg.url}/storage/v1/object/${encodeURIComponent(bucket)}/${object}`, {
        method: 'DELETE', headers: { apikey: cfg.key, Authorization: `Bearer ${cfg.key}` },
        signal: AbortSignal.timeout(10000),
      }).catch(() => {});
    }
    return;
  }
  const dir = process.env.VERCEL_UPLOAD_DIR ? path.join(process.env.VERCEL_UPLOAD_DIR, 'signatures') : path.join(__dirname, '..', 'uploads', 'signatures');
  const p = path.join(dir, path.basename(v));
  if (fs.existsSync(p)) { try { fs.unlinkSync(p); } catch (_) {} }
}

async function getClassSignatories(classId) {
  const [[ct]] = await pool.query(
    `SELECT u.id, u.name, u.designation, u.signature, u.signature_name FROM classes c
     JOIN users u ON u.id=c.teacher_id WHERE c.id=?`, [classId]);
  const [heads] = await pool.query(
    `SELECT id, name, designation, signature, signature_name FROM users WHERE role='teacher'
     AND active=1 AND LOWER(TRIM(designation)) IN ('headmaster','head teacher','principal') ORDER BY id LIMIT 1`);
  const pack = async (u, title) => {
    if (!u) return null;
    const bytes = await loadTeacherSignature(u.signature);
    return { name: u.name, designation: u.designation || title,
      data_base64: bytes ? bytes.toString('base64') : null };
  };
  return { class_teacher: await pack(ct, 'শ্রেণি শিক্ষক'), head_teacher: await pack(heads[0], 'প্রধান শিক্ষক') };
}

module.exports = { uploadTeacherSignature, loadTeacherSignature, deleteTeacherSignature, getClassSignatories };
