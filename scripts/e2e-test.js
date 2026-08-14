#!/usr/bin/env node
/**
 * e2e-test.js — Simple E2E testing with Playwright
 *
 * Usage:
 *   node e2e-test.js --url http://localhost:3000 --actions "click:#login,fill:#email=test.com"
 *   node e2e-test.js --url http://localhost:3000 --actions "click:#login" --analyze
 *   node e2e-test.js --url http://localhost:3000 --actions "click:#login" --screenshot after.png
 *   node e2e-test.js --url http://localhost:3000 --actions "click:#login" --headed
 *
 * Actions:
 *   click:#selector          — Click element
 *   fill:#selector=value     — Fill input field (use = as separator)
 *   type:#selector=value     — Type text (keyboard events)
 *   select:#selector=value   — Select dropdown option
 *   wait:#selector           — Wait for element to appear
 *   wait:1000                — Wait N milliseconds
 *   screenshot:name.png      — Take screenshot
 */

const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

// Parse arguments
function parseArgs() {
  const args = process.argv.slice(2);
  const config = {
    url: null,
    actions: '',
    analyze: false,
    model: 'moondream:latest',
    screenshot: null,
    timeout: 30000,
    headed: false
  };

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--url':
      case '-u':
        config.url = args[++i];
        break;
      case '--actions':
      case '-a':
        config.actions = args[++i];
        break;
      case '--analyze':
        config.analyze = true;
        break;
      case '--model':
      case '-m':
        config.model = args[++i];
        break;
      case '--screenshot':
      case '-s':
        config.screenshot = args[++i];
        break;
      case '--timeout':
      case '-t':
        config.timeout = parseInt(args[++i]);
        break;
      case '--headed':
        config.headed = true;
        break;
    }
  }

  return config;
}

// Parse actions string into array
// Format: click:#selector, fill:#selector=value, wait:#selector, screenshot:name.png
function parseActions(actionsStr) {
  if (!actionsStr) return [];

  return actionsStr.split(',').map(action => {
    const [type, ...rest] = action.split(':');
    const value = rest.join(':'); // Rejoin in case value has colons

    if (type === 'click' || type === 'wait') {
      return { type, selector: value };
    } else if (type === 'fill' || type === 'type' || type === 'select') {
      // Use = as separator: fill:#selector=value
      const eqIndex = value.indexOf('=');
      if (eqIndex === -1) {
        return { type, selector: value, value: '' };
      }
      const selector = value.substring(0, eqIndex);
      const fieldValue = value.substring(eqIndex + 1);
      return { type, selector, value: fieldValue };
    } else if (type === 'screenshot') {
      return { type, filename: value };
    }

    return { type, raw: value };
  });
}

// Execute single action
async function executeAction(page, action) {
  switch (action.type) {
    case 'click':
      await page.click(action.selector);
      console.log(`  ✓ Clicked: ${action.selector}`);
      break;

    case 'fill':
      await page.fill(action.selector, action.value);
      console.log(`  ✓ Filled: ${action.selector} = "${action.value}"`);
      break;

    case 'type':
      await page.type(action.selector, action.value);
      console.log(`  ✓ Typed: ${action.selector} = "${action.value}"`);
      break;

    case 'select':
      await page.selectOption(action.selector, action.value);
      console.log(`  ✓ Selected: ${action.selector} = "${action.value}"`);
      break;

    case 'wait':
      if (action.selector.startsWith('#') || action.selector.startsWith('.') || action.selector.startsWith('[')) {
        await page.waitForSelector(action.selector);
        console.log(`  ✓ Waited for: ${action.selector}`);
      } else {
        await page.waitForTimeout(parseInt(action.selector));
        console.log(`  ✓ Waited: ${action.selector}ms`);
      }
      break;

    case 'screenshot':
      await page.screenshot({ path: action.filename, fullPage: true });
      console.log(`  ✓ Screenshot: ${action.filename}`);
      break;

    default:
      console.log(`  ⚠ Unknown action: ${action.type}`);
  }
}

// Call Ollama for analysis
async function analyzeWithOllama(screenshotPath, model) {
  return new Promise((resolve, reject) => {
    const imageData = fs.readFileSync(screenshotPath);
    const base64Image = imageData.toString('base64');

    const prompt = 'Describe what you see';

    const data = JSON.stringify({
      model: model,
      prompt: prompt,
      images: [base64Image],
      stream: false
    });

    const options = {
      hostname: '127.0.0.1',
      port: 11434,
      path: '/api/generate',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(data)
      }
    };

    const req = http.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => body += chunk);
      res.on('end', () => {
        try {
          const result = JSON.parse(body);
          resolve(result.response);
        } catch (e) {
          reject(e);
        }
      });
    });

    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

// Main function
async function main() {
  const config = parseArgs();

  if (!config.url) {
    console.error('Error: --url is required');
    console.error('Usage: node e2e-test.js --url http://localhost:3000 --actions "click:#login"');
    process.exit(1);
  }

  const actions = parseActions(config.actions);

  console.log('=== E2E Test ===');
  console.log(`URL: ${config.url}`);
  console.log(`Actions: ${actions.length}`);
  console.log('');

  const browser = await chromium.launch({ headless: !config.headed });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    // Navigate to URL
    console.log(`Navigating to ${config.url}...`);
    await page.goto(config.url, { waitUntil: 'networkidle' });
    console.log('  ✓ Page loaded');

    // Take initial screenshot
    const initialScreenshot = 'e2e-initial.png';
    await page.screenshot({ path: initialScreenshot, fullPage: true });
    console.log(`  ✓ Initial screenshot: ${initialScreenshot}`);

    // Execute actions
    if (actions.length > 0) {
      console.log('\nExecuting actions...');
      for (const action of actions) {
        await executeAction(page, action);
      }
    }

    // Take final screenshot
    const finalScreenshot = config.screenshot || 'e2e-final.png';
    await page.screenshot({ path: finalScreenshot, fullPage: true });
    console.log(`\n  ✓ Final screenshot: ${finalScreenshot}`);

    // Get page title and URL
    const title = await page.title();
    const currentUrl = page.url();
    console.log(`\nPage title: ${title}`);
    console.log(`Current URL: ${currentUrl}`);

    // Analyze with Ollama if requested
    if (config.analyze) {
      console.log(`\nAnalyzing with ${config.model}...`);
      try {
        const analysis = await analyzeWithOllama(finalScreenshot, config.model);
        console.log('\n=== AI Analysis ===');
        console.log(analysis);
      } catch (e) {
        console.error(`Analysis failed: ${e.message}`);
      }
    }

    console.log('\n=== Test Complete ===');

  } catch (e) {
    console.error(`\nError: ${e.message}`);
    process.exit(1);
  } finally {
    await browser.close();
  }
}

main();
