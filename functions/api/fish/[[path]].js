/**
 * Cloudflare Pages Function: Fish Audio API 代理
 * 处理所有 /api/fish/* 请求，绕开浏览器 CORS 限制
 */

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

export async function onRequest(context) {
  const { request, params } = context;

  // CORS 预检
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  // 解析路径
  const pathParts = params.path || [];
  const subPath = "/" + pathParts.join("/");

  // 决定上游地址
  let upstreamUrl;
  if (subPath.startsWith("/wallet/")) {
    upstreamUrl = "https://api.fish.audio" + subPath;
  } else if (subPath === "/v1/tts") {
    upstreamUrl = "https://api.fish.audio/v1/tts";
  } else if (subPath === "/voices" || subPath === "/v1/voice") {
    upstreamUrl = "https://fishaudio.org/api/open/v1/voices";
  } else if (subPath === "/model") {
    upstreamUrl = "https://api.fish.audio/model";
  } else if (subPath === "/v1/models") {
    upstreamUrl = "https://api.fish.audio/wallet/self/api-credit";
  } else {
    return new Response(
      JSON.stringify({ error: "未知的 API 路径", path: subPath }),
      { status: 404, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
  }

  // 构建转发头：从原始请求复制，只删除必须跳过的
  const forwardHeaders = new Headers(request.headers);
  const skipHeaders = [
    "host",
    "connection",
    "accept-encoding",
    "cf-connecting-ip",
    "cf-ipcountry",
    "cf-ray",
    "cf-visitor",
    "x-forwarded-for",
    "x-forwarded-proto",
    "x-real-ip",
    "content-length", // 后面手动设置
  ];
  skipHeaders.forEach((h) => forwardHeaders.delete(h));

  // 读取请求体（确保完整读取，避免 stream 转发问题）
  let requestBody = null;
  if (request.method !== "GET" && request.method !== "HEAD") {
    requestBody = await request.arrayBuffer();
    forwardHeaders.set("content-length", requestBody.byteLength.toString());
  }

  try {
    const upstreamResponse = await fetch(upstreamUrl, {
      method: request.method,
      headers: forwardHeaders,
      body: requestBody,
      redirect: "follow",
    });

    // 构建响应头
    const responseHeaders = new Headers(CORS_HEADERS);
    for (const [key, value] of upstreamResponse.headers.entries()) {
      const lowerKey = key.toLowerCase();
      if (
        lowerKey !== "content-encoding" &&
        lowerKey !== "transfer-encoding" &&
        lowerKey !== "connection" &&
        lowerKey !== "access-control-allow-origin"
      ) {
        responseHeaders.set(key, value);
      }
    }

    // 读取响应体（二进制直接透传）
    const responseBody = await upstreamResponse.arrayBuffer();

    return new Response(responseBody, {
      status: upstreamResponse.status,
      statusText: upstreamResponse.statusText,
      headers: responseHeaders,
    });
  } catch (err) {
    return new Response(
      JSON.stringify({ error: "上游服务连接失败", detail: err.message }),
      { status: 502, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
  }
}
