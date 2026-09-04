// 硅基流动 TTS 代理
// POST /api/siliconflow/tts
// body: { model, input, voice, speed, response_format }
// headers: Authorization: Bearer sk-xxx
// 返回: 音频二进制

export async function onRequestPost(context) {
  const { request } = context;
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders() });

  try {
    const authHeader = request.headers.get('Authorization');
    if (!authHeader) return new Response(JSON.stringify({ error: '缺少 Authorization 头' }), { status: 400, headers: corsHeaders() });

    const body = await request.json();
    const { model = 'fnlp/MOSS-TTSD-v0.5', input, voice, speed = 1.0, response_format = 'mp3' } = body;

    if (!input || !voice) return new Response(JSON.stringify({ error: 'input 和 voice 为必填' }), { status: 400, headers: corsHeaders() });

    const resp = await fetch('https://api.siliconflow.com/v1/audio/speech', {
      method: 'POST',
      headers: { 'Authorization': authHeader, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, input, voice, speed, response_format }),
    });

    if (!resp.ok) {
      const errText = await resp.text();
      return new Response(JSON.stringify({ error: '硅基流动API错误', status: resp.status, detail: errText }), { status: resp.status, headers: corsHeaders() });
    }

    const audioBuffer = await resp.arrayBuffer();
    return new Response(audioBuffer, {
      status: 200,
      headers: { 'Content-Type': 'audio/mpeg', 'Content-Length': audioBuffer.byteLength, 'Access-Control-Allow-Origin': '*' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: '代理错误', detail: String(err) }), { status: 500, headers: corsHeaders() });
  }
}

function corsHeaders() {
  return { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization' };
}
export async function onRequestOptions() { return new Response(null, { status: 204, headers: corsHeaders() }); }
