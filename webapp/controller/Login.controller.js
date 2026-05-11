sap.ui.define([
    "sap/ui/core/mvc/Controller"
], function (Controller) {
    "use strict";

    // OData service used as a credential-validation ping in production
    var SAP_PING_URL = "/sap/opu/odata/sap/ZSD_CUSTIND_WITHOUTVEHNEW_SRV/?sap-client=300";

    return Controller.extend("customerindent.controller.Login", {

        onInit: function () {
            // If already logged in, skip the login page
            if (sessionStorage.getItem("portal_isLoggedIn") === "true") {
                this.getOwnerComponent().getRouter().navTo("RouteCustomerIndent", {}, true);
            }

            // Reset form state every time the login page is navigated to,
            // because SAPUI5 reuses the controller instance (onInit runs only once)
            this.getOwnerComponent().getRouter()
                .getRoute("RouteLogin")
                .attachPatternMatched(this._onRouteMatched, this);
        },

        _onRouteMatched: function () {
            var oButton = this.byId("loginButton");
            oButton.setEnabled(true);
            oButton.setText("Sign In");
            this.byId("usernameInput").setValue("");
            this.byId("passwordInput").setValue("");
            this._hideError();
        },

        onLoginPress: function () {
            var sUsername = this.byId("usernameInput").getValue().trim();
            var sPassword = this.byId("passwordInput").getValue();

            if (!sUsername || !sPassword) {
                this._showError("Please enter both username and password.");
                return;
            }

            this._hideError();
            var oButton = this.byId("loginButton");
            oButton.setEnabled(false);
            oButton.setText("Signing in\u2026");

            var bIsLocal = window.location.hostname === "localhost" ||
                           window.location.hostname === "127.0.0.1";

            var pLogin = bIsLocal
                ? this._loginViaProxy(sUsername, sPassword)
                : this._loginViaSAP(sUsername, sPassword);

            pLogin
                .then(function () {
                    this._onLoginSuccess(sUsername, sPassword);
                }.bind(this))
                .catch(function (oErr) {
                    this._showError(oErr.message || "Login failed. Please check your credentials and try again.");
                    oButton.setEnabled(true);
                    oButton.setText("Sign In");
                }.bind(this));
        },

        /**
         * Dev-only: POST to Node.js proxy which validates against SAP via a HEAD request.
         */
        _loginViaProxy: function (sUsername, sPassword) {
            return fetch("/api/login", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ username: sUsername, password: sPassword })
            }).then(function (oResponse) {
                if (oResponse.ok) { return; }
                return oResponse.json().then(function (oData) {
                    throw new Error(oData.message || "Invalid username or password.");
                });
            });
        },

        /**
         * Production: HEAD request directly to SAP OData with Basic Auth.
         * No new ABAP code required — uses the existing service as a credential ping.
         * The BSP app's ICF node must allow anonymous access for this page to load first
         * (see SAP Basis steps below).
         *
         * We first call the SAP logoff endpoint to invalidate any existing browser
         * session (e.g. a developer/admin user already logged in as 100620).
         * Without this, SAP honours the existing session cookie and sy-uname stays as
         * the old user even though Basic-Auth credentials for the portal user are
         * supplied on the OData model.
         */
        _loginViaSAP: function (sUsername, sPassword) {
            var sToken = btoa(unescape(encodeURIComponent(sUsername + ":" + sPassword)));

            // Step 1: Invalidate any existing SAP session so a fresh one is
            // created for the portal user in step 2.
            return fetch("/sap/public/bc/icf/logoff", {
                method: "GET",
                credentials: "include"
            })
            .catch(function () { /* logoff may 404 on some systems – safe to ignore */ })
            .then(function () {
                // Step 2: Authenticate as the portal user. SAP creates a new
                // session cookie for this user; all subsequent same-origin OData
                // requests (incl. XMLHttpRequest from the OData model) will carry
                // it, so sy-uname will resolve to sUsername.
                return fetch(SAP_PING_URL, {
                    method: "HEAD",
                    credentials: "include",
                    headers: {
                        "Authorization": "Basic " + sToken,
                        "sap-client": "300"
                    }
                });
            })
            .then(function (oResponse) {
                if (oResponse.status === 401 || oResponse.status === 403) {
                    throw new Error("Invalid username or password.");
                }
                if (!oResponse.ok) {
                    throw new Error("Cannot reach the SAP system. Please try again later.");
                }
            });
        },

        _onLoginSuccess: function (sUsername, sPassword) {
            // Persist login state for this browser session
            sessionStorage.setItem("portal_isLoggedIn", "true");
            sessionStorage.setItem("portal_username", sUsername);

            // Persist encoded credentials so Component.js can restore
            // the OData model after a page refresh.
            var sToken = btoa(unescape(encodeURIComponent(sUsername + ":" + sPassword)));
            sessionStorage.setItem("portal_token", sToken);

            // Create (or recreate) the OData model now that credentials are
            // available. This prevents the unauthenticated $metadata 401 that
            // occurs when the model is created before login.
            this.getOwnerComponent().initODataModel(sToken, sUsername);

            this.getOwnerComponent().getRouter().navTo("RouteCustomerIndent", {}, true);
        },

        _showError: function (sMessage) {
            var oStrip = this.byId("loginError");
            oStrip.setText(sMessage);
            oStrip.setVisible(true);
        },

        _hideError: function () {
            this.byId("loginError").setVisible(false);
        }

    });
});
