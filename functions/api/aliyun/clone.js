// Cloudflare Pages Function: 阿里云百炼声音克隆代理
// 前端调用: POST /api/aliyun/clone
// body: { audio_base64, mime_type, prefix, target_model }
// headers: Authorization: Bearer sk-xxx
// 返回: { voice_id }

export async function onRequestPost(context) {
  const { request } = context;

  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders() });
  }

  try {
    const authHeader = request.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: '缺少 Authorization 头' }), {
        status: 400, headers: corsHeaders(),
      });
    }

    const body = await request.json();
    const { audio_base64, mime_type = 'audio/mpeg', prefix = 'voice', target_model = 'cosyvoice-v3.5-flash' } = body;

    if (!audio_base64) {
      return new Response(JSON.stringify({ error: '缺少音频数据' }), {
        status: 400, headers: corsHeaders(),
      });
    }

    // 构造 data URI
    const dataUri = `data:${mime_type};base64,${audio_base64}`;

    // 调用阿里云百炼声音复刻 API
    const apiUrl = 'https://dashscope.aliyuncs.com/api/v1/services/audio/tts/customization';

    const cloneResponse = await fetch(apiUrl, {
      method: 'POST',
      headers: {
        'Authorization': authHeader,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'voice-enrollment',
        input: {
          action: 'create_voice',
          target_model: target_model,
          prefix: prefix,
          url: dataUri,
        },
      }),
    });

    const cloneData = await cloneResponse.json();

    if (!cloneResponse.ok) {
      return new Response(JSON.stringify({
        error: '阿里云克隆失败',
        status: cloneResponse.status,
        detail: cloneData,
      }), {
        status: cloneResponse.status,
        headers: corsHeaders(),
      });
    }

    // 提取 voice_id（不同模型返回字段可能不同）
    const voiceId = cloneData?.output?.voice_id || cloneData?.output?.voice || cloneData?.voice_id || cloneData?.voice;

    if (!voiceId) {
      return new Response(JSON.stringify({
        error: '未返回音色ID',
        detail: cloneData,
      }), {
        status: 502,
        headers: corsHeaders(),
      });
    }

    return new Response(JSON.stringify({ voice_id: voiceId, raw: cloneData }), {
      status: 200,
      headers: corsHeaders(),
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: '代理错误', detail: String(err) }), {
      status: 500,
      headers: corsHeaders(),
    });
  }
}

function corsHeaders() {
  return {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };
}

export async function onRequestOptions(context) {
  return new Response(null, { status: 204, headers: corsHeaders() });
}
