// Kho Blob giả + mấy thứ của Node mà trình duyệt không có, để chạy thử được
// nguyên hàm sao-luu.js mà không cần cài Node.
export const kho = new Map(); // pathname -> {bytes, uploadedAt}
export const gioGia = { lech: 0 }; // day lui thoi diem tai len, de thu don rac

const enc = new TextEncoder();
const dec = new TextDecoder();

function b64ToBytes(s) {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export class Buffer extends Uint8Array {
  static from(v, kieu) {
    if (typeof v === 'string') return new Buffer(kieu === 'base64' ? b64ToBytes(v) : enc.encode(v));
    if (v instanceof ArrayBuffer) return new Buffer(new Uint8Array(v));
    return new Buffer(v);
  }
}

export function timingSafeEqual(a, b) {
  if (a.length !== b.length) throw new Error('do dai khac nhau');
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}

export const process = { env: { CANXE_TOKEN: 'token-thu', BLOB_READ_WRITE_TOKEN: 'blob-thu' } };

export async function put(pathname, body, opts) {
  if (!opts || opts.access !== 'private') throw new Error('phai la private: ' + pathname);
  kho.set(pathname, {
    bytes: typeof body === 'string' ? enc.encode(body) : new Uint8Array(body),
    uploadedAt: new Date(Date.now() - gioGia.lech).toISOString(),
  });
  return { pathname };
}

export async function list({ prefix = '', limit = 1000, cursor } = {}) {
  const blobs = [...kho.entries()]
    .filter(([k]) => k.startsWith(prefix))
    .map(([k, v]) => ({ pathname: k, size: v.bytes.length, uploadedAt: v.uploadedAt }));
  return { blobs, hasMore: false, cursor: undefined };
}

export async function del(paths) {
  for (const x of [].concat(paths)) kho.delete(x);
}

export async function get(pathname, opts) {
  if (!opts || opts.access !== 'private') throw new Error('phai la private');
  if (!kho.has(pathname)) return null;
  return { stream: new Response(kho.get(pathname).bytes).body };
}

/** Giả đối tượng res của Node, ghi lại thứ hàm trả về. */
export function taoRes() {
  const r = { ma: 0, than: null };
  r.status = (n) => { r.ma = n; return r; };
  r.setHeader = () => r;
  r.end = (b) => { r.than = b; return r; };
  r.json = () => JSON.parse(typeof r.than === 'string' ? r.than : dec.decode(r.than));
  return r;
}

export function taoReq(method, query, body, token = 'token-thu') {
  return {
    method,
    query,
    body,
    headers: token === null ? {} : { authorization: 'Bearer ' + token },
  };
}
