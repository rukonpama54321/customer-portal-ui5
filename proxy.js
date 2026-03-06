/**
 * ⚠️  LOCAL DEVELOPMENT PROXY ONLY  ⚠️
 *
 * This file is used exclusively when running "npm run start-local" on a developer's
 * machine. It is NOT included in the BSP/dist deployment package.
 *
 * DO NOT commit real credentials here. Use environment variables instead:
 *   USERNAME = process.env.SAP_USER
 *   PASSWORD = process.env.SAP_PASS
 *
 * When deployed to the SAP BSP (ZCUSTINDENT), the browser calls the SAP backend
 * directly via the same origin — no proxy is needed and no credentials are embedded.
 */
const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');

const BACKEND_URL = 'https://eccdev.nrl.com:8001';

// Use environment variables; fall back to placeholders that will fail loudly
const USERNAME = process.env.SAP_USER || 'REPLACE_WITH_ENV_VAR';
const PASSWORD = process.env.SAP_PASS || 'REPLACE_WITH_ENV_VAR';

if (USERNAME === 'REPLACE_WITH_ENV_VAR') {
    console.warn('⚠️  proxy.js: SAP_USER / SAP_PASS environment variables are not set. Set them before running locally.');
}

const auth = Buffer.from(`${USERNAME}:${PASSWORD}`).toString('base64');

module.exports = function(app) {
  app.use('/sap/opu/odata', createProxyMiddleware({
    target: BACKEND_URL,
    changeOrigin: true,
    secure: false,
    headers: {
      'Authorization': `Basic ${auth}`,
      'sap-client': '300'
    },
    onProxyReq: (proxyReq, req, res) => {
      proxyReq.setHeader('Authorization', `Basic ${auth}`);
      proxyReq.setHeader('sap-client', '300');
    }
  }));
};
