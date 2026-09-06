# Chạy thử hàm sao-luu.js

Máy không cần cài Node. Từ thư mục `vercel/`:

```bash
python -m http.server 9123
```

rồi mở <http://127.0.0.1:9123/kiem-thu/chay-thu.html>.

Trang này nạp thẳng `api/sao-luu.js` — bản thật sẽ chạy trên Vercel — chỉ tráo
mấy dòng `import` sang một kho Blob giả trong bộ nhớ, rồi chạy 25 phép thử:
chìa khoá, đẩy từng phần, đếm lại số phần, tải về, hạn giữ bản, dọn rác của lần
đẩy bị đứt, và chặn tên bản có `../`.
