sap.ui.define([], function () {
    "use strict";
    return {
        getLoginInfo: function () {
            var sUserId = "", sEmail = "";

            if (sap.ushell && sap.ushell.Container && sap.ushell.Container.getUser) {
                sUserId = sap.ushell.Container.getUser().getId();
                sEmail = sap.ushell.Container.getUser().getEmail();
            }

            // Fallback for local testing
            //sUserId = "100238";
            // sUserId = "100007";
            // sEmail = "MRIGANKA.SARMA@NRL.CO.IN";
            // sUserId = "Z_DEEPJOYD";
            // sEmail  = "DEEPJOY@INDIGI.CO.IN";

            return { userId: sUserId, email: sEmail };
        },

    };
});