// Cloudflare Pages Function: 阿里云百炼 CosyVoice TTS 代理
// 前端调用: POST /api/aliyun/tts
// body: { model, text, voice, rate, format }
// headers: Authorization: Bearer sk-xxx
// 返回: 音频二进制（代理自动下载阿里云返回的音频URL）

export async function onRequestPost(context) {
  const { request } = context;

  // CORS 预检
  if (request.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      },
    });
  }

  try {
    const authHeader = request.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: '缺少 Authorization 头' }), {
        status: 400,
        headers: corsHeaders(),
      });
    }

    const body = await request.json();
    const { model = 'cosyvoice-v3.5-flash', text, voice, rate = 1.0, format = 'mp3' } = body;

    if (!text || !voice) {
      return new Response(JSON.stringify({ error: 'text 和 voice 为必填项' }), {
        status: 400,
        headers: corsHeaders(),
      });
    }

    // 调用阿里云百炼 TTS API
    const apiUrl = 'https://dashscope.aliyuncs.com/api/v1/services/audio/tts/SpeechSynthesizer';

    const ttsResponse = await fetch(apiUrl, {
      method: 'POST',
      headers: {
        'Authorization': authHeader,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        input: {
          text,
          voice,
          format,
          rate,
        },
      }),
    });

    const ttsData = await ttsResponse.json();

    if (!ttsResponse.ok) {
      return new Response(JSON.stringify({
        error: '阿里云 API 错误',
        status: ttsResponse.status,
        detail: ttsData,
      }), {
        status: ttsResponse.status,
        headers: corsHeaders(),
      });
    }

    const audioUrl = ttsData?.output?.audio?.url;
    if (!audioUrl) {
      return new Response(JSON.stringify({
        error: '阿里云未返回音频URL',
        detail: ttsData,
      }), {
        status: 502,
        headers: corsHeaders(),
      });
    }

    // 下载音频文件
    const audioResponse = await fetch(audioUrl);
    if (!audioResponse.ok) {
      return new Response(JSON.stringify({ error: '音频下载失败' }), {
        status: 502,
        headers: corsHeaders(),
      });
    }

    const audioBuffer = await audioResponse.arrayBuffer();
    const contentType = audioResponse.headers.get('Content-Type') || 'audio/mpeg';

    return new Response(audioBuffer, {
      status: 200,
      headers: {
        'Content-Type': contentType,
        'Content-Length': audioBuffer.byteLength,
        'Access-Control-Allow-Origin': '*',
        'X-Audio-Characters': String(ttsData?.usage?.characters || ''),
      },
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

// 同时处理 OPTIONS 预检
export async function onRequestOptions(context) {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    },
  });
}
