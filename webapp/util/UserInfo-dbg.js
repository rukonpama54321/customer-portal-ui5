sap.ui.define([], function () {
    "use strict";

    // Cache resolved user info so the backend is only called once per session
    var _oUserInfoCache = null;

    return {
        /**
         * Synchronous fallback — works only in FLP (sap.ushell available).
         * Prefer getLoginInfoAsync() in all new code.
         */
        getLoginInfo: function () {
            if (sap.ushell && sap.ushell.Container && sap.ushell.Container.getUser) {
                return {
                    userId: sap.ushell.Container.getUser().getId(),
                    email:  sap.ushell.Container.getUser().getEmail()
                };
            }
            // Return cache if already resolved (e.g. async call ran first)
            if (_oUserInfoCache) {
                return _oUserInfoCache;
            }
            // Standalone BSP: user ID not yet known synchronously
            return { userId: "", email: "" };
        },

        /**
         * Async version — works in both FLP and standalone BSP mode.
         * Resolves with { userId, email }.
         *
         * Usage:
         *   UserInfo.getLoginInfoAsync().then(function(oInfo) {
         *       console.log(oInfo.userId);
         *   });
         */
        getLoginInfoAsync: function () {
            // 1. FLP mode
            if (sap.ushell && sap.ushell.Container && sap.ushell.Container.getUser) {
                var oUser = sap.ushell.Container.getUser();
                _oUserInfoCache = { userId: oUser.getId(), email: oUser.getEmail() };
                return Promise.resolve(_oUserInfoCache);
            }

            // 2. Return cached result if already fetched
            if (_oUserInfoCache) {
                return Promise.resolve(_oUserInfoCache);
            }

            // 3. Standalone BSP mode — call SAP's start_up service which returns
            //    the session user without requiring sap.ushell
            return fetch("/sap/bc/ui2/start_up", {
                credentials: "include",
                headers: { "Accept": "application/json" }
            })
            .then(function (oResponse) {
                if (!oResponse.ok) {
                    throw new Error("start_up returned HTTP " + oResponse.status);
                }
                return oResponse.json();
            })
            .then(function (oData) {
                // The service returns { id: "USERID", email: "..." }
                _oUserInfoCache = {
                    userId: oData.id   || "",
                    email:  oData.email || ""
                };
                return _oUserInfoCache;
            })
            .catch(function (oErr) {
                console.warn("UserInfo: could not determine logged-in user.", oErr);
                _oUserInfoCache = { userId: "", email: "" };
                return _oUserInfoCache;
            });
        }
    };
});