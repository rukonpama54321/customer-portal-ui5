sap.ui.define([
    "sap/ui/core/UIComponent",
    "sap/ui/Device",
    "customerindent/model/models"
], function (UIComponent, Device, models) {
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

            // Load CSS asynchronously
            this._loadStyleSheet();
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
                case "ManageOrder":
                    sTitle = "Manage Bulk Order";
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
