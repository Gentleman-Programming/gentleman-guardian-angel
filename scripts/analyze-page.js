#!/usr/bin/env node
/**
 * analyze-page.js — Capture a web page with Playwright and analyze via Ollama.
 *
 * Usage:
 *   node scripts/analyze-page.js <url> [options]
 *
 * Options:
 *   --mode, -m      Analysis mode: ui, error, design, accessibility, performance (default: ui)
 *   --model, -l     Ollama model (default: moondream:latest)
 *   --output, -o    Save screenshot to file
 *   --wait, -w      Wait time in ms before capture (default: 2000)
 *   --full, -f      Capture full page (not just viewport)
 *   --ollama, -u    Ollama URL (default: http://localhost:11434)
 *   --no-analysis   Capture only, skip Ollama analysis
 *
 * Examples:
 *   node scripts/analyze-page.js http://localhost:3000/catalogos
 *   node scripts/analyze-page.js http://localhost:3000 --mode error --full
 *   node scripts/analyze-page.js http://localhost:3000 --no-analysis -o screenshot.png
 */

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const http = require('http');

// --- Parse arguments ---
const args = process.argv.slice(2);
const url = args.find(a => a.startsWith('http'));

if (!url) {
  console.error('Usage: node analyze-page.js <url> [options]');
  console.error('Example: node analyze-page.js http://localhost:3000/catalogos --mode error');
  process.exit(1);
}

function getArg(flags, defaultVal) {
  const flag = args.find(a => flags.some(f => a.startsWith(f + '=') || a === f));
  if (!flag) return defaultVal;
  if (flag.includes('=')) return flag.split('=')[1];
  const idx = args.indexOf(flag);
  return args[idx + 1] || defaultVal;
}

const hasFlag = (flags) => args.some(a => flags.includes(a));

const mode = getArg(['--mode', '-m'], 'ui');
const userModel = getArg(['--model', '-l'], null);
const output = getArg(['--output', '-o'], null);
const wait = parseInt(getArg(['--wait', '-w'], '2000'), 10);
const fullPage = hasFlag(['--full', '-f']);
const ollamaUrl = getArg(['--ollama', '-u'], 'http://127.0.0.1:11434');
const noAnalysis = hasFlag(['--no-analysis']);

// --- Model selection ---
// Default: moondream (fast, lightweight, works on any RAM)
// Use --model llava:7b only if you have >8GB free AND want slower but better analysis
const DEFAULT_MODEL = 'moondream:latest';

function selectModel(userModel) {
  if (userModel) {
    console.log(`🧠 Using user-specified model: ${userModel}`);
    return userModel;
  }
  console.log(`🧠 Using default model: ${DEFAULT_MODEL} (use --model to override)`);
  return DEFAULT_MODEL;
}

// --- Mode prompts (optimized for small vision models — short & direct) ---
const modePrompts = {
  ui: "Describe this webpage. List any visual problems you see.",
  error: "What error or problem do you see in this image?",
  design: "Describe the design. What looks good? What needs improvement?",
  accessibility: "Check this page for accessibility problems. Any contrast or size issues?",
  performance: "Any loading issues, broken images, or layout problems visible?"
};

// --- Capture page ---
async function capturePage() {
  console.log(`🌐 Launching browser...`);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    deviceScaleFactor: 1
  });
  const page = await context.newPage();

  try {
    console.log(`🔗 Navigating to ${url}`);
    await page.goto(url, { waitUntil: 'networkidle', timeout: 30000 });

    if (wait > 0) {
      console.log(`⏳ Waiting ${wait}ms for page to settle...`);
      await page.waitForTimeout(wait);
    }

    // Determine screenshot path
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    const screenshotPath = output || path.join(process.cwd(), `screenshot-${timestamp}.png`);

    console.log(`📸 Capturing ${fullPage ? 'full page' : 'viewport'}...`);
    await page.screenshot({
      path: screenshotPath,
      fullPage: fullPage
    });

    // Wait for file to be fully written
    await new Promise(r => setTimeout(r, 500));

    console.log(`✅ Screenshot saved: ${screenshotPath}`);
    return screenshotPath;

  } finally {
    await browser.close();
  }
}

// --- Analyze with Ollama ---
async function analyzeWithOllama(imagePath, model) {
  console.log(`🧠 Analyzing with ${model} (mode: ${mode})...`);

  const imageBytes = fs.readFileSync(imagePath);
  const imageBase64 = imageBytes.toString('base64');

  const prompt = modePrompts[mode] || modePrompts.ui;

  const body = JSON.stringify({
    model: model,
    messages: [{
      role: 'user',
      content: prompt,
      images: [imageBase64]
    }],
    stream: false
  });

  const startTime = Date.now();

  try {
    const result = await new Promise((resolve, reject) => {
      const req = http.request(`${ollamaUrl}/api/chat`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(body)
        },
        timeout: 300000 // 5 min timeout
      }, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          try {
            resolve(JSON.parse(data));
          } catch (e) {
            reject(new Error(`Invalid JSON response: ${e.message}`));
          }
        });
      });

      req.on('error', reject);
      req.on('timeout', () => {
        req.destroy();
        reject(new Error('Request timed out after 300s'));
      });

      req.write(body);
      req.end();
    });

    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);

    console.log('');
    console.log('═'.repeat(55));
    console.log(`  🔍 Vision Analysis (${mode}) — ${elapsed}s`);
    console.log('═'.repeat(55));
    console.log('');
    console.log(result.message.content);
    console.log('');
    console.log('═'.repeat(55));
    console.log(`  Model: ${model} | Image: ${path.basename(imagePath)}`);
    console.log('═'.repeat(55));

    // Return structured result
    return {
      success: true,
      mode,
      model,
      image: imagePath,
      elapsed_seconds: parseFloat(elapsed),
      analysis: result.message.content
    };

  } catch (err) {
    console.error(`❌ Ollama error: ${err.message}`);
    console.log('');
    console.log('💡 Make sure Ollama is running: ollama serve');
    console.log(`   And model is pulled: ollama pull ${model}`);

    return {
      success: false,
      error: err.message,
      image: imagePath
    };
  }
}

// --- Main ---
(async () => {
  try {
    // --- Resolve model ---
    const model = selectModel(userModel);

    // --- Capture ---
    const screenshotPath = await capturePage();

    if (noAnalysis) {
      console.log('Done. Skipping analysis (--no-analysis).');
      process.exit(0);
    }

    // --- Analyze ---
    const result = await analyzeWithOllama(screenshotPath, model);

    // Output JSON for programmatic use
    if (process.env.JSON_OUTPUT === '1') {
      console.log(JSON.stringify(result, null, 2));
    }

    process.exit(result.success ? 0 : 1);

  } catch (err) {
    console.error(`❌ Fatal error: ${err.message}`);
    process.exit(1);
  }
})();
