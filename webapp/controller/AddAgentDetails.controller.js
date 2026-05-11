sap.ui.define([
    "sap/ui/core/mvc/Controller",
    "sap/ui/core/routing/History",
    "sap/ui/model/json/JSONModel",
    "sap/ui/model/Filter",
    "sap/ui/model/FilterOperator",
    "sap/m/MessageToast",
    "sap/m/MessageBox",
    "../util/formatter-dbg"
], function (Controller, History, JSONModel, Filter, FilterOperator, MessageToast, MessageBox, formatter) {
    "use strict";

    return Controller.extend("customerindent.controller.AddAgentDetails", {

        formatter: formatter,

        onInit: function () {
            var oViewModel = new JSONModel({
                busy: false,
                AGENT_ID: "",
                AGENT_NAME: "",
                AGENT_MAIL: "",
                AGENT_PH: "",
                AGENT_ADDR: "",
                agents: []
            });
            this.getView().setModel(oViewModel, "addAgentModel");

            var oRouter = this.getOwnerComponent().getRouter();
            oRouter.getRoute("AddAgentDetails").attachPatternMatched(this._onRouteMatched, this);
        },

        _onRouteMatched: function () {
            this._resetForm();
            this._loadAgents();
        },

        onAfterRendering: function () {
            this._adjustTableHeight();
        },

        onExit: function () {
            if (this._fnResizeHandler) {
                window.removeEventListener("resize", this._fnResizeHandler);
            }
        },

        _adjustTableHeight: function () {
            var oScrollContainer = this.byId("agentsScrollContainer");
            if (!oScrollContainer) { return; }
            var oDomRef = oScrollContainer.getDomRef();
            if (!oDomRef) { return; }

            var oCard = oDomRef.closest(".agent-table-card");
            var oCardHeader = oCard ? oCard.querySelector(".card-header") : null;
            var nCardHeight = oCard ? oCard.clientHeight : 0;
            var nHeaderHeight = oCardHeader ? oCardHeader.offsetHeight : 0;
            var nAvailableHeight = nCardHeight - nHeaderHeight - 2; // 2px buffer

            if (nAvailableHeight > 80) {
                oDomRef.style.height = nAvailableHeight + "px";
                var oInnerScroll = oDomRef.querySelector(".sapMScrollContScroll");
                if (oInnerScroll) {
                    oInnerScroll.style.height = nAvailableHeight + "px";
                    oInnerScroll.style.overflowY = "auto";
                }
            }

            // Re-register resize handler (idempotent)
            if (!this._fnResizeHandler) {
                this._fnResizeHandler = this._adjustTableHeight.bind(this);
                window.addEventListener("resize", this._fnResizeHandler);
            }
        },

        _loadAgents: function () {
            var oViewModel = this.getView().getModel("addAgentModel");
            var oODataModel = this.getView().getModel();

            oViewModel.setProperty("/busy", true);
            oODataModel.read("/AgentDetailsSet", {
                success: function (oData) {
                    var aAgents = oData.results || [];
                    oViewModel.setProperty("/agents", aAgents);
                    oViewModel.setProperty("/busy", false);
                    this._generateAgentId(aAgents);
                    // Re-adjust scroll height after new rows are rendered
                    setTimeout(this._adjustTableHeight.bind(this), 100);
                }.bind(this),
                error: function () {
                    oViewModel.setProperty("/agents", []);
                    oViewModel.setProperty("/busy", false);
                }.bind(this)
            });
        },

        _generateAgentId: function (aAgents) {
            var oViewModel = this.getView().getModel("addAgentModel");
            var nMax = 0;
            (aAgents || []).forEach(function (oAgent) {
                var nId = parseInt(oAgent.AGENT_ID, 10);
                if (!isNaN(nId) && nId > nMax) { nMax = nId; }
            });
            var sNextId = String(nMax + 1).padStart(10, "0");
            oViewModel.setProperty("/AGENT_ID", sNextId);
        },

        onAgentSearch: function (oEvent) {
            var sQuery = oEvent.getParameter("newValue") || "";
            var oTable = this.byId("agentsTable");
            var oBinding = oTable.getBinding("items");

            if (!oBinding) { return; }

            if (!sQuery) {
                oBinding.filter([]);
                return;
            }

            var aFilters = [
                new Filter("AGENT_ID",   FilterOperator.Contains, sQuery),
                new Filter("AGENT_NAME", FilterOperator.Contains, sQuery),
                new Filter("AGENT_MAIL", FilterOperator.Contains, sQuery),
                new Filter("AGENT_PH",   FilterOperator.Contains, sQuery)
            ];
            oBinding.filter(new Filter({ filters: aFilters, and: false }));
        },

        /**
         * Reset the form model to empty values when navigating to this view.
         */
        _resetForm: function () {
            var oViewModel = this.getView().getModel("addAgentModel");
            var aAgents = oViewModel.getProperty("/agents") || [];
            oViewModel.setData({
                busy: false,
                AGENT_ID: "",
                AGENT_NAME: "",
                AGENT_MAIL: "",
                AGENT_PH: "",
                AGENT_ADDR: "",
                agents: aAgents
            });

            // Clear any value state set during previous validation
            var aInputIds = ["agentIdInput", "agentNameInput", "agentMailInput", "agentPhInput", "agentAddrInput"];
            aInputIds.forEach(function (sId) {
                var oControl = this.byId(sId);
                if (oControl) {
                    oControl.setValueState("None");
                    oControl.setValueStateText("");
                }
            }.bind(this));
        },

        onNavBack: function () {
            this.getOwnerComponent().getRouter().navTo("RouteCustomerIndent", {}, true);
        },

        onSave: function () {
            if (!this._validateForm()) {
                return;
            }

            var oView = this.getView();
            var oViewModel = oView.getModel("addAgentModel");

            var sName = (oViewModel.getProperty("/AGENT_NAME") || "").trim();
            var sId   = (oViewModel.getProperty("/AGENT_ID")   || "").trim();

            MessageBox.confirm(
                "Save new agent \"" + sName + "\" (ID: " + sId + ")?\nThis will create the record in the system.",
                {
                    title: "Confirm Save",
                    actions: [MessageBox.Action.OK, MessageBox.Action.CANCEL],
                    emphasizedAction: MessageBox.Action.OK,
                    onClose: function (sAction) {
                        if (sAction === MessageBox.Action.OK) {
                            this._doSave();
                        }
                    }.bind(this)
                }
            );
        },

        _doSave: function () {
            var oView = this.getView();
            var oViewModel = oView.getModel("addAgentModel");
            var oODataModel = oView.getModel();

            var oPayload = {
                AGENT_ID:   oViewModel.getProperty("/AGENT_ID").trim(),
                AGENT_NAME: oViewModel.getProperty("/AGENT_NAME").trim(),
                AGENT_MAIL: oViewModel.getProperty("/AGENT_MAIL").trim(),
                AGENT_PH:   oViewModel.getProperty("/AGENT_PH").trim(),
                AGENT_ADDR: oViewModel.getProperty("/AGENT_ADDR").trim()
            };

            oViewModel.setProperty("/busy", true);

            oODataModel.create("/AgentDetailsSet", oPayload, {
                success: function () {
                    oViewModel.setProperty("/busy", false);
                    MessageToast.show(this._getText("addAgent.saveSuccess"));
                    this._resetForm();
                    this._loadAgents();
                }.bind(this),
                error: function (oError) {
                    oViewModel.setProperty("/busy", false);
                    var sMessage = this._getText("addAgent.saveError");
                    try {
                        var oResponse = JSON.parse(oError.responseText);
                        if (oResponse && oResponse.error && oResponse.error.message && oResponse.error.message.value) {
                            sMessage = oResponse.error.message.value;
                        }
                    } catch (e) {
                        // use default message
                    }
                    MessageBox.error(sMessage);
                }.bind(this)
            });
        },

        /**
         * Validate required fields.
         * @returns {boolean} true if all required fields are filled correctly
         */
        _validateForm: function () {
            var oViewModel = this.getView().getModel("addAgentModel");
            var bValid = true;

            var aRequiredFields = [
                { id: "agentNameInput", field: "/AGENT_NAME", labelKey: "addAgent.agentName" },
                { id: "agentMailInput", field: "/AGENT_MAIL", labelKey: "addAgent.agentMail" },
                { id: "agentPhInput",   field: "/AGENT_PH",   labelKey: "addAgent.agentPh" },
                { id: "agentAddrInput", field: "/AGENT_ADDR", labelKey: "addAgent.agentAddr" }
            ];

            aRequiredFields.forEach(function (oEntry) {
                var sValue = (oViewModel.getProperty(oEntry.field) || "").trim();
                var oControl = this.byId(oEntry.id);
                if (!sValue) {
                    oControl.setValueState("Error");
                    oControl.setValueStateText(this._getText("addAgent.fieldRequired", [this._getText(oEntry.labelKey)]));
                    bValid = false;
                } else {
                    oControl.setValueState("None");
                    oControl.setValueStateText("");
                }
            }.bind(this));

            return bValid;
        },

        /**
         * Helper to retrieve i18n text.
         */
        _getText: function (sKey, aArgs) {
            return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(sKey, aArgs);
        },

        onDeleteAgent: function (oEvent) {
            var oItem = oEvent.getSource().getParent(); // Button → ColumnListItem
            var oCtx  = oItem.getBindingContext("addAgentModel");
            var sId   = oCtx.getProperty("AGENT_ID");
            var sName = oCtx.getProperty("AGENT_NAME");

            MessageBox.confirm(
                "Delete agent \"" + sName + "\" (ID: " + sId + ")?\nThis cannot be undone.",
                {
                    title: "Confirm Delete",
                    actions: [MessageBox.Action.OK, MessageBox.Action.CANCEL],
                    emphasizedAction: MessageBox.Action.CANCEL,
                    onClose: function (sAction) {
                        if (sAction !== MessageBox.Action.OK) { return; }
                        var oODataModel = this.getView().getModel();
                        var oViewModel  = this.getView().getModel("addAgentModel");
                        oViewModel.setProperty("/busy", true);
                        oODataModel.remove("/AgentDetailsSet('" + sId + "')", {
                            success: function () {
                                oViewModel.setProperty("/busy", false);
                                MessageToast.show("Agent " + sId + " deleted.");
                                this._loadAgents();
                            }.bind(this),
                            error: function (oError) {
                                oViewModel.setProperty("/busy", false);
                                var sMsg = "Failed to delete agent.";
                                try {
                                    var oResp = JSON.parse(oError.responseText);
                                    if (oResp.error && oResp.error.message && oResp.error.message.value) {
                                        sMsg = oResp.error.message.value;
                                    }
                                } catch (e) { /* use default */ }
                                MessageBox.error(sMsg);
                            }.bind(this)
                        });
                    }.bind(this)
                }
            );
        }

    });
});
