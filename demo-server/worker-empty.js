// WalkPad Sync Demo API - EMPTY STATE
// No data at all (shows empty states on both tabs)
// Deploy: npx wrangler deploy --config wrangler-empty.toml

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Content-Type': 'application/json',
};

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    if (path === '/api/health') {
      return new Response(JSON.stringify({
        status: 'ok',
        demo_mode: 'empty',
        description: 'Empty state (no data)'
      }), { headers: corsHeaders });
    }

    if (path === '/api/dates') {
      return new Response(JSON.stringify({ dates: [] }), { headers: corsHeaders });
    }

    if (path === '/api/dates/summaries') {
      return new Response(JSON.stringify({ summaries: [] }), { headers: corsHeaders });
    }

    const summaryMatch = path.match(/^\/api\/dates\/(\d{4}-\d{2}-\d{2})\/summary$/);
    if (summaryMatch) {
      return new Response(JSON.stringify({ error: 'No data available' }), {
        status: 404, headers: corsHeaders
      });
    }

    const samplesMatch = path.match(/^\/api\/dates\/(\d{4}-\d{2}-\d{2})\/samples$/);
    if (samplesMatch) {
      return new Response(JSON.stringify({ error: 'No data available' }), {
        status: 404, headers: corsHeaders
      });
    }

    if (path === '/api/bluetooth/status') {
      return new Response(JSON.stringify({
        connected: false,
        device_name: null,
        message: 'Demo mode - empty state'
      }), { headers: corsHeaders });
    }

    return new Response(JSON.stringify({ error: 'Not found' }), {
      status: 404, headers: corsHeaders
    });
  },
};
