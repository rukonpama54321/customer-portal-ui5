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
            this.getRouter().initialize();
            this.getRouter().attachRouteMatched(this.onRouteMatched, this);
            this.setModel(models.createDeviceModel(), "device");

            var sToken = sessionStorage.getItem("portal_token");
            var sUsername = sessionStorage.getItem("portal_username");

            // Create the OData model only when credentials are available.
            // If created without credentials the framework immediately fetches
            // $metadata unauthenticated, gets 401, and marks the model as failed.
            if (sToken) {
                this._initODataModel(sToken, sUsername);
            }

            // Load CSS asynchronously
            this._loadStyleSheet();
        },

        /**
         * Creates and attaches the default OData model with the given credentials.
         * Called from init() (page reload with session) and from the Login controller
         * after a successful login.
         */
        initODataModel: function (sToken, sUsername) {
            this._initODataModel(sToken, sUsername);
        },

        _initODataModel: function (sToken, sUsername) {
            var oModel = new ODataModel("/sap/opu/odata/sap/ZSD_CUSTIND_WITHOUTVEHNEW_SRV/", {
                defaultBindingMode: "TwoWay",
                useBatch: true,
                refreshAfterChange: false,
                headers: {
                    "sap-client": "300",
                    "Authorization": "Basic " + sToken,
                    "X-Portal-User": sUsername || ""
                }
            });
            this.setModel(oModel);
            // Fetch a valid CSRF token now that credentials are set.
            oModel.refreshSecurityToken();
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

            // Session guard: redirect unauthenticated users to the login page
            if (sRouteName !== "RouteLogin" && sessionStorage.getItem("portal_isLoggedIn") !== "true") {
                this.getRouter().navTo("RouteLogin", {}, true);
                return;
            }

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
