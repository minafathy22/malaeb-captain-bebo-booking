// Online-first shell: never cache availability, customer data, requests or RPC responses.
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('fetch',event=>{
  if(event.request.mode!=='navigate')return;
  event.respondWith(fetch(event.request,{cache:'no-store'}).catch(()=>new Response('<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ملاعب كابتن بيبو</title><body style="background:#0d1912;color:white;font:20px sans-serif;text-align:center;padding:40px">الاتصال بالإنترنت مطلوب لمعرفة المواعيد وإرسال طلب الحجز. جرّب تاني لما الشبكة ترجع.</body></html>',{headers:{'Content-Type':'text/html; charset=utf-8'}})));
});