const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');

const BACKEND_URL = 'https://eccdev.nrl.com:8001';
const USERNAME = '100620';
const PASSWORD = 'Feb567#$';

// Create base64 encoded credentials
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
