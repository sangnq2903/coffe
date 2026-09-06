import { put, list, del, get } from '@vercel/blob';
import { timingSafeEqual } from 'node:crypto';

/**
 * Kho cất bản sao lưu cơ sở dữ liệu cân xe.
 *
 * Đây KHÔNG phải máy chủ cân xe chạy trên Vercel — máy chủ vẫn chạy ở nhà, vì
 * nó phải mở cổng COM nối đầu cân và phải giữ được một cơ sở dữ liệu nằm yên
 * một chỗ. Hàm này làm đúng một việc: nhận gói sao lưu **đã mã hoá sẵn** rồi
 * cất vào Vercel Blob, cho danh sách, cho tải về, và dọn bản cũ.
 *
 * Hai lớp khoá, cố ý chồng lên nhau:
 *   1. Blob để chế độ riêng tư — không có chìa khoá thì không đọc được.
 *   2. Nội dung đã mã hoá từ máy chủ ở nhà — nên kể cả kho lưu trữ bị lộ, hay
 *      chính Vercel đọc file, cũng chỉ thấy byte ngẫu nhiên.
 * Chỉ dựa vào lớp 1 là đặt toàn bộ sổ lương và sổ mua bán vào tay cấu hình
 * đúng của một dịch vụ bên ngoài. Lớp 2 mới là thứ mình tự nắm.
 *
 * Đường đi:
 *   POST   ?viec=phan&ban=<ten>&so=<i>  {du_lieu: base64}  — gửi từng phần
 *   POST   ?viec=xong&ban=<ten>         {so_phan, meta, giu_ban}
 *   GET    ?viec=danh-sach
 *   GET    ?viec=tai&ban=<ten>          — số phần và phần mô tả
 *   GET    ?viec=phan&ban=<ten>&so=<i>  — byte thô của một phần
 *   GET    ?viec=suc-khoe
 *   DELETE ?ban=<ten>
 */

const THU_MUC = 'sao-luu';
const RIENG_TU = { access: 'private' };

export default async function handler(req, res) {
  try {
    // Không tham số, không cần chìa khoá: chỉ để kiểm tra đã triển khai chưa.
    // Cố ý không tiết lộ gì ngoài việc "có tồn tại".
    if (req.method === 'GET' && Object.keys(req.query ?? {}).length === 0) {
      return json(res, 200, { ok: true, ten: 'canxe-sao-luu' });
    }

    if (!duocPhep(req)) {
      return json(res, 401, { loi: 'Sai hoặc thiếu token.' });
    }
    if (!process.env.BLOB_READ_WRITE_TOKEN) {
      return json(res, 500, {
        loi: 'Dự án chưa nối kho Blob (thiếu biến BLOB_READ_WRITE_TOKEN).',
      });
    }

    const viec = req.query.viec ?? '';
    if (req.method === 'GET') {
      if (viec === 'suc-khoe') return await sucKhoe(res);
      if (viec === 'danh-sach') return await danhSach(res);
      if (viec === 'tai') return await tai(req, res);
      if (viec === 'phan') return await taiPhan(req, res);
    }
    if (req.method === 'POST') {
      if (viec === 'phan') return await nhanPhan(req, res);
      if (viec === 'xong') return await ghiXong(req, res);
    }
    if (req.method === 'DELETE') return await xoa(req, res);

    return json(res, 400, { loi: `Không hiểu yêu cầu (${req.method} viec=${viec}).` });
  } catch (e) {
    return json(res, 500, { loi: String(e?.message ?? e) });
  }
}

// --------------------------------------------------------------- từng việc

async function sucKhoe(res) {
  const blobs = await liet(`${THU_MUC}/`);
  const manifests = blobs.filter((b) => b.pathname.endsWith('/manifest.json'));
  return json(res, 200, {
    ok: true,
    blob: true,
    so_ban: manifests.length,
    tong_bytes: blobs.reduce((t, b) => t + (b.size ?? 0), 0),
  });
}

async function nhanPhan(req, res) {
  const ban = tenBan(req.query.ban);
  const so = soPhanHopLe(req.query.so);
  const b64 = req.body?.du_lieu;
  if (typeof b64 !== 'string' || b64.length === 0) {
    return json(res, 400, { loi: 'Thiếu trường du_lieu.' });
  }

  const bytes = Buffer.from(b64, 'base64');
  await put(`${THU_MUC}/${ban}/${tenPhan(so)}`, bytes, {
    ...RIENG_TU,
    addRandomSuffix: false,
    allowOverwrite: true,
    contentType: 'application/octet-stream',
  });
  return json(res, 200, { ok: true, bytes: bytes.length });
}

/**
 * Ghi phần mô tả — bước cuối cùng, và chính nó đánh dấu bản sao lưu là hoàn
 * chỉnh. Bản nào không có file này thì bị bỏ qua khi liệt kê và khi tải, nên
 * đứt mạng giữa chừng chỉ để lại rác chứ không tạo ra một bản thiếu ruột mà
 * trông vẫn lành lặn — thứ chỉ vỡ lẽ đúng hôm cần dùng tới.
 */
async function ghiXong(req, res) {
  const ban = tenBan(req.query.ban);
  const { so_phan: soPhan, meta, bytes, giu_ban: giuBan } = req.body ?? {};
  if (!Number.isInteger(soPhan) || soPhan < 1) {
    return json(res, 400, { loi: 'so_phan không hợp lệ.' });
  }

  // Đếm lại phần thật sự nằm trong kho thay vì tin con số máy chủ gửi lên:
  // thiếu một phần thì gói ghép lại sẽ hỏng, mà lúc đó đã quá muộn để biết.
  const co = (await liet(`${THU_MUC}/${ban}/`)).filter((b) =>
    b.pathname.endsWith('.bin'),
  ).length;
  if (co !== soPhan) {
    return json(res, 400, {
      loi: `Kho chỉ nhận được ${co}/${soPhan} phần — bản sao lưu chưa đủ.`,
    });
  }

  await put(
    `${THU_MUC}/${ban}/manifest.json`,
    JSON.stringify({ ten: ban, so_phan: soPhan, bytes: bytes ?? 0, meta: meta ?? null }),
    {
      ...RIENG_TU,
      addRandomSuffix: false,
      allowOverwrite: true,
      contentType: 'application/json; charset=utf-8',
    },
  );

  const daXoa = await donBanCu(Number.isInteger(giuBan) ? giuBan : 30);
  return json(res, 200, { ok: true, so_phan: soPhan, xoa: daXoa });
}

async function danhSach(res) {
  return json(res, 200, { ban: await docManifest() });
}

async function tai(req, res) {
  const ten = tenBan(req.query.ban);
  const mo = await docJson(`${THU_MUC}/${ten}/manifest.json`);
  if (!mo) {
    return json(res, 404, { loi: `Không có bản sao lưu hoàn chỉnh tên "${ten}".` });
  }

  const co = (await liet(`${THU_MUC}/${ten}/`)).filter((b) =>
    b.pathname.endsWith('.bin'),
  ).length;
  if (co !== mo.so_phan) {
    return json(res, 409, {
      loi: `Bản "${ten}" thiếu phần: có ${co}, cần ${mo.so_phan}.`,
    });
  }
  return json(res, 200, { ten, so_phan: mo.so_phan, bytes: mo.bytes, meta: mo.meta });
}

/** Trả byte thô của một phần. Mỗi phần đã được cắt nhỏ nên vừa hạn của Vercel. */
async function taiPhan(req, res) {
  const ten = tenBan(req.query.ban);
  const so = soPhanHopLe(req.query.so);
  const kq = await get(`${THU_MUC}/${ten}/${tenPhan(so)}`, RIENG_TU);
  if (!kq) return json(res, 404, { loi: `Không có phần ${so} của bản "${ten}".` });

  const buf = Buffer.from(await new Response(kq.stream).arrayBuffer());
  res.status(200).setHeader('content-type', 'application/octet-stream');
  return res.end(buf);
}

async function xoa(req, res) {
  const ten = tenBan(req.query.ban);
  const blobs = await liet(`${THU_MUC}/${ten}/`);
  if (blobs.length === 0) return json(res, 404, { loi: `Không có bản "${ten}".` });
  await del(blobs.map((b) => b.pathname));
  return json(res, 200, { ok: true, xoa: blobs.length });
}

// ----------------------------------------------------------------- tiện ích

/** Liệt kê hết, lật trang cho tới khi hết — kho có thể trả về từng trang một. */
async function liet(prefix) {
  const tatCa = [];
  let cursor;
  do {
    const kq = await list({ ...RIENG_TU, prefix, limit: 1000, cursor });
    tatCa.push(...kq.blobs);
    cursor = kq.hasMore ? kq.cursor : undefined;
  } while (cursor);
  return tatCa;
}

async function docJson(pathname) {
  try {
    const kq = await get(pathname, RIENG_TU);
    if (!kq) return null;
    return await new Response(kq.stream).json();
  } catch {
    return null;
  }
}

async function docManifest() {
  const ten = (await liet(`${THU_MUC}/`))
    .filter((b) => b.pathname.endsWith('/manifest.json'))
    .map((b) => b.pathname)
    .sort((a, b) => b.localeCompare(a));

  const ban = await Promise.all(ten.map(docJson));
  return ban.filter(Boolean);
}

/**
 * Dọn kho: giữ [giu] bản hoàn chỉnh mới nhất, và hót rác của những lần đẩy bị đứt.
 *
 * Chỉ bản CÓ phần mô tả mới được tính vào hạn giữ. Tính cả thư mục dở dang thì
 * một lần đứt mạng sẽ chiếm mất một suất và đẩy một bản tốt ra ngoài — mất bản
 * sao lưu thật để giữ lại rác.
 */
async function donBanCu(giu) {
  const blobs = await liet(`${THU_MUC}/`);

  const theoBan = new Map();
  for (const b of blobs) {
    const ten = b.pathname.split('/')[1];
    if (!ten) continue;
    if (!theoBan.has(ten)) theoBan.set(ten, []);
    theoBan.get(ten).push(b);
  }

  const xong = [];
  const doDang = [];
  for (const [ten, ds] of theoBan) {
    (ds.some((b) => b.pathname.endsWith('/manifest.json')) ? xong : doDang).push(ten);
  }

  const bo = [];
  // Tên bản bắt đầu bằng ngày giờ dạng 20260906-013000, nên xếp theo tên giảm
  // dần là mới nhất đứng đầu.
  if (giu > 0) bo.push(...xong.sort((a, b) => b.localeCompare(a)).slice(giu));

  // Rác của lần đẩy bị đứt. Chỉ dọn thứ đã quá một ngày: máy trung tâm và máy
  // trạm dùng chung kho này, nên rất có thể một thư mục chưa có mô tả là vì
  // máy kia đang đẩy dở ngay lúc mình dọn.
  const hanRac = Date.now() - 24 * 60 * 60 * 1000;
  for (const ten of doDang) {
    const moiNhat = Math.max(
      ...theoBan.get(ten).map((b) => new Date(b.uploadedAt ?? 0).getTime()),
    );
    if (moiNhat < hanRac) bo.push(ten);
  }

  for (const t of bo) {
    await del(theoBan.get(t).map((b) => b.pathname));
  }
  return bo;
}

function tenBan(raw) {
  const ten = String(raw ?? '');
  // Chặn "../" và mọi thứ lạ: tên bản do máy chủ đặt, nhưng nó đi thẳng vào
  // đường dẫn trong kho nên vẫn không được tin.
  if (!/^[A-Za-z0-9._-]{1,120}$/.test(ten)) {
    throw new Error(`Tên bản sao lưu không hợp lệ: "${ten}"`);
  }
  return ten;
}

function soPhanHopLe(raw) {
  const so = Number.parseInt(raw ?? '', 10);
  if (!Number.isInteger(so) || so < 0 || so > 99999) {
    throw new Error(`Số thứ tự phần không hợp lệ: "${raw}"`);
  }
  return so;
}

const tenPhan = (so) => `p${String(so).padStart(5, '0')}.bin`;

/** So chìa khoá không phụ thuộc nội dung, để không lộ dần qua thời gian đáp. */
function duocPhep(req) {
  const mong = process.env.CANXE_TOKEN ?? '';
  if (mong.length === 0) return false;
  const gui = String(req.headers.authorization ?? '').replace(/^Bearer\s+/i, '');
  const a = Buffer.from(gui);
  const b = Buffer.from(mong);
  return a.length === b.length && timingSafeEqual(a, b);
}

function json(res, status, body) {
  res.status(status).setHeader('content-type', 'application/json; charset=utf-8');
  return res.end(JSON.stringify(body));
}
