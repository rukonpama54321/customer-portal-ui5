const proxy = require('http-proxy-middleware');
const https = require('https');
const crypto = require('crypto');

const SAP_ODATA_TARGET = 'https://eccdev.nrl.com:8001';
const SAP_WD_TARGET = 'http://eccdev.nrl.com:8000';

// In-memory session store: token → { username, password, sapCookies }
// sapCookies holds the SAP session cookies captured server-side so that the
// CSRF token fetch and the subsequent $batch request land on the SAME SAP
// session — SAP validates CSRF tokens against the session that issued them,
// so without session stickiness every $batch returns 403.
const sessions = new Map();

function getPortalToken(req) {
    const cookies = req.headers.cookie || '';
    const match = cookies.match(/sap_session=([^;]+)/);
    return match ? match[1] : null;
}

function makeProxy(target) {
    return proxy.createProxyMiddleware({
        target,
        changeOrigin: true,
        secure: false,
        onProxyReq: (proxyReq, req) => {
            const portalToken = getPortalToken(req);
            const session = portalToken ? sessions.get(portalToken) : null;

            // Set Authorization from the portal session's stored credentials.
            if (session) {
                const dynAuth = Buffer.from(session.username + ':' + session.password).toString('base64');
                proxyReq.setHeader('Authorization', 'Basic ' + dynAuth);
            }
            proxyReq.setHeader('sap-client', '300');

            // DEBUG — remove once sy-uname issue is resolved
            const authHeader = proxyReq.getHeader('Authorization') || req.headers['authorization'] || '(none)';
            const authUser = authHeader !== '(none)'
                ? Buffer.from(authHeader.replace(/^Basic /, ''), 'base64').toString().split(':')[0]
                : '(none)';
            console.log(`[proxy] ${req.method} ${req.path} → auth user: ${authUser} | sap_session: ${portalToken ? 'present' : 'missing'} | sap_cookies: ${session && session.sapCookies ? 'present' : 'none'}`);

            // Forward the SAP session cookies that were captured server-side on
            // the previous response. This keeps the CSRF token and the $batch
            // request in the same SAP session so SAP accepts the token.
            // We never forward raw browser cookies to SAP to prevent stale
            // developer sessions (e.g. 100620) from interfering.
            if (session && session.sapCookies) {
                proxyReq.setHeader('Cookie', session.sapCookies);
            } else {
                proxyReq.removeHeader('Cookie');
            }
        },
        onProxyRes: (proxyRes, req) => {
            delete proxyRes.headers['www-authenticate'];

            // Capture SAP session cookies from the SAP response and store them
            // server-side, tied to the portal session. On the next request they
            // are forwarded to SAP (see onProxyReq above) so the same SAP
            // session is reused. The cookies are never forwarded to the browser.
            if (proxyRes.headers['set-cookie']) {
                const portalToken = getPortalToken(req);
                if (portalToken && sessions.has(portalToken)) {
                    const captured = proxyRes.headers['set-cookie']
                        .map(c => c.split(';')[0]) // keep name=value only
                        .join('; ');
                    sessions.get(portalToken).sapCookies = captured;
                }
                delete proxyRes.headers['set-cookie'];
            }
        }
    });
}

const odataProxy = makeProxy(SAP_ODATA_TARGET);
const wdProxy = makeProxy(SAP_WD_TARGET);

/**
 * Validate SAP credentials AND establish a real SAP session in one request.
 * Uses GET with X-CSRF-Token: Fetch so we capture:
 *   - proof that credentials are valid (non-401/403 response)
 *   - the SAP session cookies (sap-sessionid etc.) for session stickiness
 * Storing these cookies immediately means session.sapCookies is populated
 * before the browser's ODataModel ever makes a request, so the CSRF token
 * fetch and every subsequent $batch all land on the SAME SAP session.
 */
function validateSapCredentials(user, pass) {
    return new Promise(function (resolve, reject) {
        var testAuth = Buffer.from(user + ':' + pass).toString('base64');
        var options = {
            hostname: 'eccdev.nrl.com',
            port: 8001,
            path: '/sap/opu/odata/sap/ZSD_CUSTIND_WITHOUTVEHNEW_SRV/?sap-client=300',
            method: 'GET',
            headers: {
                'Authorization': 'Basic ' + testAuth,
                'sap-client': '300',
                'X-CSRF-Token': 'Fetch'
            },
            rejectUnauthorized: false
        };

        var req = https.request(options, function (res) {
            // Drain the response body so the socket is released promptly.
            res.resume();

            if (res.statusCode === 401 || res.statusCode === 403) {
                reject(new Error('Invalid username or password.'));
                return;
            }

            // Capture SAP session cookies so the proxy can forward them on
            // every subsequent request, keeping all requests in the same
            // SAP session and making CSRF token validation work correctly.
            var sapCookies = null;
            if (res.headers['set-cookie']) {
                sapCookies = res.headers['set-cookie']
                    .map(function (c) { return c.split(';')[0]; })
                    .join('; ');
            }

            resolve({ valid: true, sapCookies: sapCookies });
        });

        req.on('error', function () {
            reject(new Error('Cannot reach the backend. Please try again later.'));
        });

        req.end();
    });
}

module.exports = function ({ resources, options }) {
    return function customProxyMiddleware(req, res, next) {
        // ── Custom login endpoint ──────────────────────────────────────────────
        if (req.method === 'POST' && req.path === '/api/login') {
            var body = '';
            req.on('data', function (chunk) { body += chunk.toString(); });
            req.on('end', function () {
                var parsed;
                try {
                    parsed = JSON.parse(body);
                } catch (e) {
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
                    .then(function (result) {
                        var token = crypto.randomBytes(32).toString('hex');
                        // Store sapCookies captured during credential validation so
                        // the very first proxied OData request (CSRF token fetch)
                        // reuses the same SAP session — preventing CSRF 403 errors.
                        sessions.set(token, { username: user, password: pass, sapCookies: result.sapCookies || null });
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

        // ── Logout endpoint ───────────────────────────────────────────────────
        if (req.method === 'POST' && req.path === '/api/logout') {
            var cookies = req.headers.cookie || '';
            var match = cookies.match(/sap_session=([^;]+)/);
            if (match) { sessions.delete(match[1]); }
            res.writeHead(200, {
                'Content-Type': 'application/json',
                'Set-Cookie': 'sap_session=; HttpOnly; Path=/; Max-Age=0'
            });
            res.end(JSON.stringify({ success: true }));
            return;
        }

        // ── SAP proxy routes ───────────────────────────────────────────────────
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
