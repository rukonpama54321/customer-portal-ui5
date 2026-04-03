sap.ui.define([
    "sap/ui/core/mvc/Controller",
    "sap/m/MessageBox"
], function (Controller, MessageBox) {
    "use strict";

    return Controller.extend("customerindent.controller.Home", {

        onInit: function () {
            // Show logged-in username in the header
            var sUsername = sessionStorage.getItem("portal_username") || "";
            if (sUsername) {
                this.byId("loggedInUser").setText("Signed in as: " + sUsername);
            }
        },

        onSignOut: function () {
            MessageBox.confirm("Are you sure you want to sign out?", {
                title: "Sign Out",
                onClose: function (sAction) {
                    if (sAction === MessageBox.Action.OK) {
                        // Clear session state and OData auth header
                        sessionStorage.removeItem("portal_isLoggedIn");
                        sessionStorage.removeItem("portal_username");
                        sessionStorage.removeItem("portal_token");

                        var oModel = this.getOwnerComponent().getModel();
                        if (oModel) {
                            oModel.setHeaders({ "Authorization": undefined });
                        }

                        this.getOwnerComponent().getRouter().navTo("RouteLogin", {}, true);
                    }
                }.bind(this)
            });
        },

        onBulkIndentPress: function () {
            this.getOwnerComponent().getRouter().navTo("RouteCustomerIndent");
        },

        onDirectIndentPress: function () {
            window.open(
                "/sap/bc/webdynpro/sap/zsd_cust_indent_dir_inbapp?sap-client=800&sap-language=EN&sap-wd-run-sc=X",
                "_blank"
            );
        }

    });
});
