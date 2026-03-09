const proxy = require('http-proxy-middleware');

const SAP_ODATA_TARGET = 'https://eccdev.nrl.com:8001';
const SAP_WD_TARGET = 'http://eccdev.nrl.com:8000';
const username = '100620';
const password = 'Mar567#$';
const auth = Buffer.from(`${username}:${password}`).toString('base64');

function makeProxy(target) {
    return proxy.createProxyMiddleware({
        target,
        changeOrigin: true,
        secure: false,
        onProxyReq: (proxyReq) => {
            proxyReq.setHeader('Authorization', `Basic ${auth}`);
            proxyReq.setHeader('sap-client', '300');
        },
        onProxyRes: (proxyRes) => {
            delete proxyRes.headers['www-authenticate'];
        }
    });
}

const odataProxy = makeProxy(SAP_ODATA_TARGET);
const wdProxy = makeProxy(SAP_WD_TARGET);

module.exports = function ({ resources, options }) {
    return function customProxyMiddleware(req, res, next) {
        if (req.path.startsWith('/sap/bc/webdynpro') ||
            req.path.startsWith('/sap/public') ||
            req.path.startsWith('/sap/bc/bsp')) {
            return wdProxy(req, res, next);
        }
        if (req.path.startsWith('/sap/')) {
            return odataProxy(req, res, next);
        }
        next();
    };
};
