/**
 * Test your connection to inference-hub.
 *
 * Usage:
 *   npm install openai
 *   npx tsx test_connection.ts
 *
 * Set these environment variables before running:
 *   export INFERENCE_HUB_URL="http://192.168.1.100:4200/v1"
 *   export INFERENCE_HUB_KEY="mind-team-your-key-here"
 */

import OpenAI from "openai";

const BASE_URL = process.env.INFERENCE_HUB_URL ?? "http://localhost:4200/v1";
const API_KEY = process.env.INFERENCE_HUB_KEY ?? "YOUR_KEY_HERE";
const MODEL = process.env.INFERENCE_HUB_MODEL ?? "small";

const client = new OpenAI({ baseURL: BASE_URL, apiKey: API_KEY });

console.log(`Connecting to ${BASE_URL}...`);

// 1. List available models
const models = await client.models.list();
console.log(`Available models: ${models.data.map((m) => m.id).join(", ")}`);

// 2. Send a test message
console.log(`\nSending test message to model '${MODEL}'...`);
const response = await client.chat.completions.create({
  model: MODEL,
  messages: [{ role: "user", content: "What is 2+2? Reply in one sentence." }],
  max_tokens: 50,
});

console.log(`Response: ${response.choices[0].message.content}`);
console.log(`\nTokens used: ${response.usage?.total_tokens}`);
console.log("Connection successful!");
