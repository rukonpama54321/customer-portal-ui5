sap.ui.define([], function () {
    "use strict";
    return {
        formatDate: function (sValue) {
            if (!sValue) {
                return "";
            }
            if (typeof sValue === "string" && sValue.length === 8) {
                var year = sValue.substring(0, 4);
                var month = sValue.substring(4, 6);
                var day = sValue.substring(6, 8);
                return day + "." + month + "." + year;
            }
            return sValue;
        },
        formatYesNo: function (ynValue) {
            if (!ynValue) {
                return "";
            }
            if (ynValue === "Y") {
                return "Yes";
            } else if (ynValue === "N") {
                return "No";
            }
            return ynValue; // fallback, in case value is not Y/N
        },
        formatFlushKey: function (sValue) {
            if (!sValue) return "";
            if (sValue === "Y" || sValue.toUpperCase() === "YES") return "Y";
            if (sValue === "N" || sValue.toUpperCase() === "NO") return "N";
            return "";
        },
        onFlushingSelectChange: function (oEvent) {
            var sKey = oEvent.getSource().getSelectedKey();
            var oModel = this.getView().getModel("SelectedIndent");

            oModel.setProperty("/ATF_FLUSH", sKey);

            var oReasonInput = this.byId("changeFlushingReasonSelect");
            if (sKey === "Y") {
                oReasonInput.setEnabled(true);
            } else {
                oReasonInput.setEnabled(false);
                oReasonInput.setValue("");
                oModel.setProperty("/FLUSH_REASON", ""); // clear in model too
            }
        },
        accstmtformatdate: function(sFrom, sTo) {
            function formatDate(sValue) {
                if (!sValue) return "";
                if (typeof sValue === "string" && sValue.length === 8) {
                    var year = sValue.substring(0, 4);
                    var month = sValue.substring(4, 6);
                    var day = sValue.substring(6, 8);
                    return day + "." + month + "." + year;
                }
                return sValue;
            }

            return "Statement of Account for Period: " + formatDate(sFrom) + " - " + formatDate(sTo);
        },
        creditformatdate: function(sFrom) {
            function formatDate(sValue) {
                if (!sValue) return "";
                if (typeof sValue === "string" && sValue.length === 8) {
                    var year = sValue.substring(0, 4);
                    var month = sValue.substring(4, 6);
                    var day = sValue.substring(6, 8);
                    return day + "." + month + "." + year;
                }
                return sValue;
            }

            return "Credit Details as on Date: " + formatDate(sFrom);
        },
        dispdetformatdate: function(sFrom, sTo) {
            function formatDate(sValue) {
                if (!sValue) return "";
                if (typeof sValue === "string" && sValue.length === 8) {
                    var year = sValue.substring(0, 4);
                    var month = sValue.substring(4, 6);
                    var day = sValue.substring(6, 8);
                    return day + "." + month + "." + year;
                }
                return sValue;
            }

            return "Dispatch Details: " + formatDate(sFrom) + " - " + formatDate(sTo);
        },
        reconformatdate: function(sFrom, sTo) {
            function formatDate(sValue) {
                if (!sValue) return "";
                if (typeof sValue === "string" && sValue.length === 8) {
                    var year = sValue.substring(0, 4);
                    var month = sValue.substring(4, 6);
                    var day = sValue.substring(6, 8);
                    return day + "." + month + "." + year;
                }
                return sValue;
            }

            return "Reconciliation for the Period: " + formatDate(sFrom) + " - " + formatDate(sTo);
        },
        closformatdate: function(sFrom) {
            function formatDate(sValue) {
                if (!sValue) return "";
                if (typeof sValue === "string" && sValue.length === 8) {
                    var year = sValue.substring(0, 4);
                    var month = sValue.substring(4, 6);
                    var day = sValue.substring(6, 8);
                    return day + "." + month + "." + year;
                }
                return sValue;
            }

            return "Balance as on Date: " + formatDate(sFrom) ;
        },
        paydetformatdate: function(sFrom, sTo) {
            function formatDate(sValue) {
                if (!sValue) return "";
                if (typeof sValue === "string" && sValue.length === 8) {
                    var year = sValue.substring(0, 4);
                    var month = sValue.substring(4, 6);
                    var day = sValue.substring(6, 8);
                    return day + "." + month + "." + year;
                }
                return sValue;
            }

            return "Payment Details: " + formatDate(sFrom) + " - " + formatDate(sTo);
        },

        formatItemNumber: function(sValue) {
            if (!sValue) {
                return "";
            }
            // Convert to string and remove leading zeros
            var sStringValue = String(sValue);
            return sStringValue.replace(/^0+/, '') || '0'; // Keep at least one zero if all are zeros
        },

        formatQuantityPercentage: function(sQuantity) {
            if (!sQuantity) {
                return 0;
            }
            // Convert quantity to percentage for depletion bar
            // This is a placeholder calculation - user will explain significance later
            var quantity = parseFloat(sQuantity);
            if (quantity <= 0) return 0;
            if (quantity >= 100) return 100;
            
            // For now, use quantity as percentage (can be adjusted based on business logic)
            return Math.min(quantity, 100);
        },

        formatAllocationPercentage: function (sAgentQty, sTotalQty) {
            var agentQty = parseFloat(sAgentQty) || 0;
            var totalQty = parseFloat(sTotalQty) || 0;
            
            if (totalQty === 0) {
                return 0;
            }
            
            var percentage = (agentQty / totalQty) * 100;
            return Math.min(Math.max(percentage, 0), 100);
        },

        formatAllocationLabel: function (sAgentQty, sTotalQty, sUom) {
            var agentQty = parseFloat(sAgentQty) || 0;
            var totalQty = parseFloat(sTotalQty) || 0;
            var uom = sUom || "";
            
            return agentQty + " / " + totalQty + " " + uom + " allocated";
        }

    };
});