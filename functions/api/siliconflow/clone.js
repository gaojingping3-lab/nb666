// 硅基流动声音克隆代理
// POST /api/siliconflow/clone
// body: { model, customName, audio_base64, mime_type, text }
// headers: Authorization: Bearer sk-xxx
// 返回: { uri }

export async function onRequestPost(context) {
  const { request } = context;
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders() });

  try {
    const authHeader = request.headers.get('Authorization');
    if (!authHeader) return new Response(JSON.stringify({ error: '缺少 Authorization 头' }), { status: 400, headers: corsHeaders() });

    const body = await request.json();
    const { model = 'fnlp/MOSS-TTSD-v0.5', customName = 'voice', audio_base64, mime_type = 'audio/mpeg', text = '' } = body;

    if (!audio_base64) return new Response(JSON.stringify({ error: '缺少音频数据' }), { status: 400, headers: corsHeaders() });

    const dataUri = `data:${mime_type};base64,${audio_base64}`;

    const resp = await fetch('https://api.siliconflow.com/v1/uploads/audio/voice', {
      method: 'POST',
      headers: { 'Authorization': authHeader, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, customName, audio: dataUri, text }),
    });

    const data = await resp.json();

    if (!resp.ok) {
      return new Response(JSON.stringify({ error: '克隆失败', status: resp.status, detail: data }), { status: resp.status, headers: corsHeaders() });
    }

    const uri = data?.uri;
    if (!uri) return new Response(JSON.stringify({ error: '未返回音色uri', detail: data }), { status: 502, headers: corsHeaders() });

    return new Response(JSON.stringify({ uri, raw: data }), { status: 200, headers: corsHeaders() });
  } catch (err) {
    return new Response(JSON.stringify({ error: '代理错误', detail: String(err) }), { status: 500, headers: corsHeaders() });
  }
}

function corsHeaders() {
  return { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization' };
}
export async function onRequestOptions() { return new Response(null, { status: 204, headers: corsHeaders() }); }
