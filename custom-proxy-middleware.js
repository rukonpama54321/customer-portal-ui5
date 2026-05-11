const proxy = require('http-proxy-middleware');
const https = require('https');
const crypto = require('crypto');

const SAP_ODATA_TARGET = 'https://eccdev.nrl.com:8001';
const SAP_WD_TARGET = 'http://eccdev.nrl.com:8000';

const sessions = new Map();

function getPortalToken(req) {
    const match = (req.headers.cookie || '').match(/sap_session=([^;]+)/);
    return match ? match[1] : null;
}

function makeProxy(target) {
    return proxy.createProxyMiddleware({
        target,
        changeOrigin: true,
        secure: false,
        onProxyReq: (proxyReq, req) => {
            const session = sessions.get(getPortalToken(req));
            if (session) {
                proxyReq.setHeader('Authorization', 'Basic ' + Buffer.from(session.username + ':' + session.password).toString('base64'));
            }
            proxyReq.setHeader('sap-client', '300');
        },
        onProxyRes: (proxyRes) => {
            delete proxyRes.headers['www-authenticate'];
        }
    });
}

const odataProxy = makeProxy(SAP_ODATA_TARGET);
const wdProxy = makeProxy(SAP_WD_TARGET);

function validateSapCredentials(user, pass) {
    return new Promise(function (resolve, reject) {
        var req = https.request({
            hostname: 'eccdev.nrl.com',
            port: 8001,
            path: '/sap/opu/odata/sap/ZSD_CUSTIND_WITHOUTVEHNEW_SRV/?sap-client=300',
            method: 'GET',
            headers: {
                'Authorization': 'Basic ' + Buffer.from(user + ':' + pass).toString('base64'),
                'sap-client': '300'
            },
            rejectUnauthorized: false
        }, function (res) {
            res.resume();
            if (res.statusCode === 401 || res.statusCode === 403) {
                reject(new Error('Invalid username or password.'));
            } else {
                resolve();
            }
        });
        req.on('error', function () { reject(new Error('Cannot reach the backend. Please try again later.')); });
        req.end();
    });
}

module.exports = function ({ resources, options }) {
    return function customProxyMiddleware(req, res, next) {

        if (req.method === 'POST' && req.path === '/api/login') {
            var body = '';
            req.on('data', function (chunk) { body += chunk.toString(); });
            req.on('end', function () {
                var parsed;
                try { parsed = JSON.parse(body); } catch (e) {
                    res.writeHead(400, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ message: 'Invalid request body.' }));
                    return;
                }
                var user = (parsed.username || '').trim();
                var pass = parsed.password || '';
                if (!user || !pass) {
                    res.writeHead(400, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ message: 'Username and password are required.' }));
                    return;
                }
                validateSapCredentials(user, pass)
                    .then(function () {
                        var token = crypto.randomBytes(32).toString('hex');
                        sessions.set(token, { username: user, password: pass });
                        res.writeHead(200, {
                            'Content-Type': 'application/json',
                            'Set-Cookie': 'sap_session=' + token + '; HttpOnly; Path=/; SameSite=Strict'
                        });
                        res.end(JSON.stringify({ success: true, username: user }));
                    })
                    .catch(function (err) {
                        var statusCode = err.message === 'Invalid username or password.' ? 401 : 503;
                        res.writeHead(statusCode, { 'Content-Type': 'application/json' });
                        res.end(JSON.stringify({ message: err.message }));
                    });
            });
            return;
        }

        if (req.method === 'POST' && req.path === '/api/logout') {
            var match = (req.headers.cookie || '').match(/sap_session=([^;]+)/);
            if (match) sessions.delete(match[1]);
            res.writeHead(200, {
                'Content-Type': 'application/json',
                'Set-Cookie': 'sap_session=; HttpOnly; Path=/; Max-Age=0'
            });
            res.end(JSON.stringify({ success: true }));
            return;
        }

        if (req.path.startsWith('/sap/bc/') || req.path.startsWith('/sap/public/')) {
            return wdProxy(req, res, next);
        }
        if (req.path.startsWith('/sap/')) {
            return odataProxy(req, res, next);
        }
        next();
    };
};
