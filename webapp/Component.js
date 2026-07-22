sap.ui.define([
    "sap/ui/core/UIComponent",
    "sap/ui/Device",
    "sap/ui/model/odata/v2/ODataModel",
    "customerindent/model/models"
], function (UIComponent, Device, ODataModel, models) {
    "use strict";

    return UIComponent.extend("customerindent.Component", {
        metadata: {
            manifest: "json"
        },

        init: function () {
            UIComponent.prototype.init.apply(this, arguments);
            this.setModel(models.createDeviceModel(), "device");

            // Initialise the OData model before the router fires any routes,
            // so that every controller's onInit / onRouteMatched already has a
            // model available via this.getOwnerComponent().getModel().
            this._initODataModel();

            // Load CSS asynchronously
            this._loadStyleSheet();

            // Router is initialised last — standard SAP Fiori pattern — so that
            // all models are ready before the first route match fires.
            this.getRouter().attachRouteMatched(this.onRouteMatched, this);
            this.getRouter().initialize();
        },

        /**
         * Creates and attaches the default OData model.
         * On BSP: session cookie provides auth — no headers needed.
         * On localhost: fiori-tools-proxy is not credential-aware by default,
         * so the Login screen collects credentials and passes them here as
         * a Basic Auth token to inject into OData requests.
         */
        initODataModel: function (sToken, sUsername) {
            this._initODataModel(sToken, sUsername);
        },

        _initODataModel: function (sToken, sUsername) {
            var oConfig = {
                defaultBindingMode: "TwoWay",
                useBatch: true,
                refreshAfterChange: false
            };
            var bIsLocal = window.location.hostname === "localhost" ||
                           window.location.hostname === "127.0.0.1";
            if (bIsLocal && sToken) {
                oConfig.headers = {
                    "sap-client": "300",
                    "Authorization": "Basic " + sToken,
                    "X-Portal-User": sUsername || ""
                };
            }
            var oModel = new ODataModel("/sap/opu/odata/sap/ZSD_CUST_BULK_INDENT_SRV/", oConfig);
            this.setModel(oModel);
            oModel.refreshSecurityToken();
            this._startSessionKeepAlive();
        },

        /**
         * Periodically refreshes the CSRF token to keep the SAP session alive.
         * Fires a HEAD request to the OData service root every 10 minutes.
         * Clears any previous interval so calling this after re-login is safe.
         */
        _startSessionKeepAlive: function () {
            var INTERVAL_MS = 10 * 60 * 1000; // 10 minutes

            if (this._keepAliveTimer) {
                clearInterval(this._keepAliveTimer);
            }

            this._keepAliveTimer = setInterval(function () {
                var oModel = this.getModel();
                if (oModel && typeof oModel.refreshSecurityToken === "function") {
                    oModel.refreshSecurityToken(
                        null,   // success — silent
                        null,   // error — silent; next real request will show the session-expired dialog
                        true    // force refresh
                    );
                }
            }.bind(this), INTERVAL_MS);
        },

        _loadStyleSheet: function() {
            var sPath = sap.ui.require.toUrl("customerindent/css/style.css");
            var link = document.createElement("link");
            link.rel = "stylesheet";
            link.href = sPath;
            document.head.appendChild(link);
        },

        onRouteMatched: function (oEvent) {
            var sRouteName = oEvent.getParameter("name");



            var sTitle = "Customer Indent App";

            switch (sRouteName) {
                case "ReptCustAccStmt":
                    sTitle = "Customer Account Statement";
                    break;
                case "ReportPage":
                    sTitle = "Customer Reports";
                    break;
                case "ReptCustomerIndent":
                    sTitle = "Customer Indent Report";
                    break;
                case "RouteCustomerIndent":
                    sTitle = "Customer Indent";
                    break;
                case "ManageBulkIndent":
                    sTitle = "Manage Bulk Indent";
                    break;
                case "ChangeIndentWithVehicleTab":
                    sTitle = "Change Indent with Vehicle";
                    break;
                case "ReptCustCredit":
                    sTitle = "Customer Credit";
                    break;
                case "ReptCustDispDet":
                    sTitle = "Customer Despatch Details";
                    break;
                case "ReptCustRecon":
                    sTitle = "Customer Reconciliation Account";
                    break;
                case "ReptCustValCon":
                    sTitle = "Valid Contract/Delivery Details";
                    break;
                case "ReptCustClosBal":
                    sTitle = "Customer Closing Balance";
                    break;
                case "ReptCustPayDet":
                    sTitle = "Customer Payment Details";
                    break;
                default:
                    sTitle = "Customer Indent App";
            }

            setTimeout(function () {
                document.title = sTitle;
            }, 0);
        }
    });
});
