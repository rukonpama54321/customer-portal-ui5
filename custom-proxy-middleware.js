const proxy = require('http-proxy-middleware');

module.exports = function ({ resources, options }) {
    return function customProxyMiddleware(req, res, next) {
        const username = '100620';
        const password = 'Feb567#$';
        const auth = Buffer.from(`${username}:${password}`).toString('base64');

        if (req.path.startsWith('/sap/opu/odata')) {
            return proxy.createProxyMiddleware({
                target: 'https://eccdev.nrl.com:8001',
                changeOrigin: true,
                secure: false,
                onProxyReq: (proxyReq) => {
                    proxyReq.setHeader('Authorization', `Basic ${auth}`);
                    proxyReq.setHeader('sap-client', '300');
                },
                onProxyRes: (proxyRes) => {
                    // Remove WWW-Authenticate to prevent browser prompt
                    delete proxyRes.headers['www-authenticate'];
                }
            })(req, res, next);
        }
        next();
    };
};
