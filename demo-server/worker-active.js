// WalkPad Sync Demo API - ACTIVE WORKOUT
// Steps increment in real-time to simulate active walking
// Deploy: npx wrangler deploy --config wrangler-active.toml

// Seeded random for consistent data (deterministic based on date string)
function seededRandom(seed) {
  const x = Math.sin(seed) * 10000;
  return x - Math.floor(x);
}

// Get "today" in user's timezone based on tz_offset parameter
function getUserToday(tzOffsetSeconds) {
  const now = new Date();
  const userTime = new Date(now.getTime() + tzOffsetSeconds * 1000);
  return userTime.toISOString().split('T')[0];
}

// Format date as YYYY-MM-DD
function formatDate(date) {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  const day = String(date.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

// Generate mock data for 60 days ending at userToday
function generateMockData(userToday, tzOffsetSeconds = 0) {
  const summaries = [];
  const [year, month, day] = userToday.split('-').map(Number);
  const todayDate = new Date(Date.UTC(year, month - 1, day, 12, 0, 0));
  const baseSeed = year * 10000 + month * 100 + day;

  for (let i = 0; i < 60; i++) {
    const date = new Date(todayDate);
    date.setUTCDate(date.getUTCDate() - i);
    const dateStr = formatDate(date);

    const dayOfWeek = date.getUTCDay();
    const isWeekend = dayOfWeek === 0 || dayOfWeek === 6;
    const isToday = i === 0;

    const dateSeed = baseSeed - i * 7;
    const rand1 = seededRandom(dateSeed);
    const rand2 = seededRandom(dateSeed + 1);
    const rand3 = seededRandom(dateSeed + 2);
    const rand4 = seededRandom(dateSeed + 3);

    // Always include today + yesterday + day before
    if (i > 2) {
      if (isWeekend && rand1 > 0.6) continue;
      if (!isWeekend && rand1 > 0.9) continue;
    }

    let baseSteps, variance;
    if (isToday) {
      // ACTIVE WORKOUT: Steps increment in real-time
      const now = new Date();
      const userNow = new Date(now.getTime() + tzOffsetSeconds * 1000);
      const currentHour = userNow.getUTCHours();
      const currentMinute = userNow.getUTCMinutes();
      const currentSecond = userNow.getUTCSeconds();

      const secondsSince9am = Math.max(0, ((currentHour - 9) * 60 + currentMinute) * 60 + currentSecond);
      const fiveSecondIntervals = Math.floor(secondsSince9am / 5);
      const timeBasedSteps = Math.floor(fiveSecondIntervals * 1.5);

      baseSteps = 2000 + timeBasedSteps;
      variance = 100;
    } else if (isWeekend) {
      baseSteps = 2000;
      variance = 3000;
    } else {
      baseSteps = 6000;
      variance = 5000;
    }

    const steps = Math.max(1000, Math.floor(baseSteps + rand2 * variance));
    const distanceMeters = Math.floor(steps * 0.4 + rand3 * 100);
    const calories = Math.floor(steps * 0.04 + rand3 * 20);
    const durationSeconds = Math.floor(steps * 1.1 + rand4 * 300);
    const avgSpeed = 0.5 + rand2 * 1.0;
    const maxSpeed = avgSpeed + 0.3 + rand3 * 0.5;

    summaries.push({
      date: dateStr,
      total_samples: Math.max(10, Math.floor(durationSeconds / 10)),
      duration_seconds: durationSeconds,
      distance_meters: distanceMeters,
      calories: calories,
      steps: steps,
      avg_speed: Math.round(avgSpeed * 100) / 100,
      max_speed: Math.round(maxSpeed * 100) / 100,
    });
  }

  return summaries.sort((a, b) => b.date.localeCompare(a.date));
}

// Generate samples for a specific date
function generateSamplesForDate(dateStr, summary) {
  const samples = [];
  const [year, month, day] = dateStr.split('-').map(Number);
  const baseDate = new Date(Date.UTC(year, month - 1, day, 9, 0, 0));

  const numSamples = summary.total_samples;
  const avgInterval = summary.duration_seconds / numSamples;

  let currentTime = baseDate.getTime() / 1000;
  let cumulativeSteps = 0;
  let cumulativeDistance = 0;
  let cumulativeCalories = 0;

  const sampleSeed = year * 10000 + month * 100 + day;

  for (let i = 0; i < numSamples; i++) {
    const stepsDelta = Math.floor(summary.steps / numSamples);
    const distanceDelta = Math.floor(summary.distance_meters / numSamples);
    const caloriesDelta = Math.floor(summary.calories / numSamples);

    cumulativeSteps += stepsDelta;
    cumulativeDistance += distanceDelta;
    cumulativeCalories += caloriesDelta;

    const speedVariance = seededRandom(sampleSeed + i) - 0.5;

    samples.push({
      timestamp: Math.floor(currentTime),
      speed: Math.max(0.3, summary.avg_speed + speedVariance * 0.4),
      distance_total: cumulativeDistance,
      calories_total: cumulativeCalories,
      steps_total: cumulativeSteps,
      distance_delta: distanceDelta,
      calories_delta: caloriesDelta,
      steps_delta: stepsDelta,
    });

    currentTime += avgInterval + (seededRandom(sampleSeed + i + 1000) - 0.5) * 5;
  }

  return samples;
}

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

    const tzOffsetParam = url.searchParams.get('tz_offset');
    const tzOffsetSeconds = tzOffsetParam ? parseInt(tzOffsetParam, 10) : 0;
    const userToday = getUserToday(tzOffsetSeconds);
    const summaries = generateMockData(userToday, tzOffsetSeconds);

    if (path === '/api/health') {
      return new Response(JSON.stringify({
        status: 'ok',
        demo_mode: 'active',
        description: 'Steps increment in real-time (active workout)'
      }), { headers: corsHeaders });
    }

    if (path === '/api/dates') {
      const dates = summaries.map(s => s.date);
      return new Response(JSON.stringify({ dates }), { headers: corsHeaders });
    }

    if (path === '/api/dates/summaries') {
      return new Response(JSON.stringify({ summaries }), { headers: corsHeaders });
    }

    const summaryMatch = path.match(/^\/api\/dates\/(\d{4}-\d{2}-\d{2})\/summary$/);
    if (summaryMatch) {
      const dateStr = summaryMatch[1];
      const summary = summaries.find(s => s.date === dateStr);
      if (summary) {
        return new Response(JSON.stringify(summary), { headers: corsHeaders });
      }
      return new Response(JSON.stringify({ error: 'Date not found' }), {
        status: 404, headers: corsHeaders
      });
    }

    const samplesMatch = path.match(/^\/api\/dates\/(\d{4}-\d{2}-\d{2})\/samples$/);
    if (samplesMatch) {
      const dateStr = samplesMatch[1];
      const summary = summaries.find(s => s.date === dateStr);
      if (summary) {
        const samples = generateSamplesForDate(dateStr, summary);
        return new Response(JSON.stringify({ date: dateStr, samples }), { headers: corsHeaders });
      }
      return new Response(JSON.stringify({ error: 'Date not found' }), {
        status: 404, headers: corsHeaders
      });
    }

    if (path === '/api/bluetooth/status') {
      return new Response(JSON.stringify({
        connected: false,
        device_name: null,
        message: 'Demo mode - active workout'
      }), { headers: corsHeaders });
    }

    return new Response(JSON.stringify({ error: 'Not found' }), {
      status: 404, headers: corsHeaders
    });
  },
};
