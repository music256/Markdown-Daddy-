// --- utils ---------------------------------------------------
const RX_FENCE = /^(`{3,}|~{3,})([^\n]*)\n([\s\S]*?)\n\1\s*$/;
const RX_MARK_START = /(<!--\s*section:template:start\s*-->)|<<<template:start>>>/i;
const RX_MARK_END   = /(<!--\s*section:template:end\s*-->)|<<<template:end>>>/i;

function stripOuterFenceIfContainsMarkers(s) {
  const m = s.match(RX_FENCE);
  if (!m) return s;
  const inner = m[3];
  // ถ้าข้างในมี marker คู่ครบ → คืน inner
  if (RX_MARK_START.test(inner) && RX_MARK_END.test(inner)) return inner;
  return s;
}

function extractRange(s) {
  // รองรับ marker 2 แบบ และเว้นวรรค/ตัวพิมพ์เล็กใหญ่
  const start = s.search(RX_MARK_START);
  const end   = s.search(RX_MARK_END);
  if (start === -1 || end === -1 || end <= start) throw new Error('missing markers');
  // slice ตั้งแต่ท้ายบรรทัด marker start ถึงก่อน marker end
  const afterStart = s.slice(start).replace(RX_MARK_START, '');
  const body = afterStart.slice(0, afterStart.search(RX_MARK_END));
  return body.trim();
}

function headingsSpace(s) {
  // เติมวรรคหลัง # โดยไม่เปลี่ยนระดับ
  return s.replace(/^(\#{1,6})(\S)/gm, (_, h, x) => `${h} ${x}`);
}

function normalizeLists(s) {
  // แทน •, *, ▪ ด้วย '-' และบีบไม่เกิน 3 ชั้น
  s = s.replace(/^[ \t]*[•*▪]\s+/gm, m => m.replace(/^[ \t]*[•*▪]\s+/, '- '));
  // ตัดชั้นเกิน 3: ลบ indent เกินสองระดับ
  return s.replace(/^( {6,})- /gm, '      - ');
}

function moveLinksToEnd(s) {
  const links = [];
  s = s.replace(/$begin:math:text$https?:\\/\\/[^\\s)]+$end:math:text$/g, (m) => { links.push(m.slice(1, -1)); return ''; });
  s = s.replace(/$begin:math:display$oai_citation:[^$end:math:display$]+\]/g, (m) => { links.push(m); return ''; });
  if (!links.length) return s;
  return s.trim() + '\n\n## รวมลิงก์อ้างอิง\n' + links.map(u => '- ' + u).join('\n') + '\n';
}

// ซ่อมรั้ว: outer เลือก ~, ยาว = max(inner same-type) + 1
function fixFences(s) {
  // เติมวรรคก่อน/หลัง fenced และบาลานซ์ backticks/tilde ที่พบบ่อย
  // เบา ๆ: ปิดที่ขาด, ถ้าเปิดด้วย ``` ก็ปิดด้วย ```; ถ้า ~~~ ก็ ~~~
  return s.replace(/(^|\n)(```+|~~~+)([^\n]*?)\n([\s\S]*?)(\n)(```+|~~~+)(?=\n|$)/g,
    (m, pre, open, info, body, br, close) => {
      const isBT = open.startsWith('`');
      const innerMax = Math.max(
        0,
        ...Array.from(body.matchAll(isBT ? /`{3,}/g : /~{3,}/g)).map(x => x[0].length)
      );
      const outerLen = Math.max(open.length, close.length, innerMax + 1);
      const fence = (isBT ? '`' : '~').repeat(outerLen);
      return `${pre}${fence}${info ? info : ''}\n${body}\n${fence}`;
    });
}

function formatMd(text, { doRange=false, doFix=false } = {}) {
  let t = text;
  // 1) กันกรณีแอปครอบเป็น code fence
  t = stripOuterFenceIfContainsMarkers(t);
  // 2) ตัดช่วง
  if (doRange) t = extractRange(t);
  // 3) ซ่อมเนื้อหา
  if (doFix) {
    t = headingsSpace(t);
    t = normalizeLists(t);
    t = fixFences(t);
    t = moveLinksToEnd(t);
  }
  return t.trim() + '\n';
}

// --- handler -------------------------------------------------
export default {
  async fetch(req) {
    if (req.method !== 'POST') return new Response('method not allowed', { status: 405 });
    const url = new URL(req.url);
    const { text = '', mode = 'fix' } = await req.json().catch(() => ({}));

    try {
      const doRange = /range/.test(mode);
      const doFix   = /fix/.test(mode);
      const out = formatMd(String(text), { doRange, doFix });
      return new Response(out, { headers: { 'content-type': 'text/plain; charset=utf-8' }});
    } catch (e) {
      return new Response(`❌ ${e.message}`, { status: 400, headers: { 'content-type': 'text/plain; charset=utf-8' }});
    }
  }
};