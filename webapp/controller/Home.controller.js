sap.ui.define([
    "sap/ui/core/mvc/Controller"
], function (Controller) {
    "use strict";

    return Controller.extend("customerindent.controller.Home", {

        onInit: function () {
            // Home screen initialisation
        },

        onBulkIndentPress: function () {
            this.getOwnerComponent().getRouter().navTo("RouteCustomerIndent");
        },

        onDirectIndentPress: function () {
            window.open(
                "/sap/bc/webdynpro/sap/zsd_cust_indent_dir_inbapp?sap-client=800&sap-language=EN",
                "_blank"
            );
        }

    });
});
