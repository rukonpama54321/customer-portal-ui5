sap.ui.define([
    "sap/ui/core/mvc/Controller",
    "sap/ui/model/json/JSONModel",
    "sap/ui/model/Filter",
    "sap/ui/model/FilterOperator",
    "sap/m/MessageToast",
    "sap/m/MessageBox"
], function (Controller, JSONModel, Filter, FilterOperator, MessageToast, MessageBox) {
    "use strict";

    return Controller.extend("customerindent.controller.CustomerOrder", {
        onInit: function () {
            var oToday = new Date();
            var oFromDate = new Date();
            oFromDate.setDate(oToday.getDate() - 2);

            var oViewModel = new JSONModel({
                busy: false,
                fromDate: this._formatDateToValue(oFromDate),
                toDate: this._formatDateToValue(oToday),
                headers: [],
                allHeaders: null,
                showEmptyMessage: false,
                showAssignedOrders: true,
                filterShippingCondition: "",
                createdOrders: [],
                selectedOrdersSubTab: "allOrders"
            });

            this.getView().setModel(oViewModel, "viewModel");
            
            // Attach route matched handler to check for refresh flag
            var oRouter = this.getOwnerComponent().getRouter();
            if (oRouter) {
                oRouter.getRoute("RouteCustomerIndent").attachPatternMatched(this._onRouteMatched, this);
            }
        },

        _onRouteMatched: function () {
            // Check if created orders need to be refreshed (e.g., after deletion)
            var oComponent = this.getOwnerComponent();
            var oComponentModel = oComponent.getModel("componentData");
            
            if (oComponentModel && oComponentModel.getProperty("/refreshCreatedOrders")) {
                // Clear the flag
                oComponentModel.setProperty("/refreshCreatedOrders", false);
                
                // Refresh created orders list
                this._loadCreatedOrders();
                
                // Switch to created orders tab to show the updated list
                var oTabBar = this.byId("orderTabBar");
                if (oTabBar) {
                    oTabBar.setSelectedKey("createdOrders");
                }
            }
        },

        onSearch: function () {
            var oView = this.getView();
            var oViewModel = oView.getModel("viewModel");
            var sFromDate = oViewModel.getProperty("/fromDate");
            var sToDate = oViewModel.getProperty("/toDate");

            if (!sFromDate || !sToDate) {
                MessageToast.show("Select a valid date range.");
                return;
            }

            if (sFromDate > sToDate) {
                var sSwap = sFromDate;
                sFromDate = sToDate;
                sToDate = sSwap;
                oViewModel.setProperty("/fromDate", sFromDate);
                oViewModel.setProperty("/toDate", sToDate);
            }

            oViewModel.setProperty("/busy", true);
            oViewModel.setProperty("/showEmptyMessage", false);

            var oModel = oView.getModel();
            var aFilters = [new Filter("BSTDK", FilterOperator.BT, sFromDate, sToDate)];

            oModel.read("/SALESORDERHeaderSet", {
                filters: aFilters,
                urlParameters: {
                    "$expand": "ToItem"
                },
                success: function (oData) {
                    var aResults = (oData && oData.results) ? oData.results : [];
                    
                    console.log("=== Sales Order Data Loaded ===");
                    console.log("Number of orders:", aResults.length);
                    
                    // Mark orders as assigned if all items have KWMENG = 0
                    var aWithFlags = aResults.map(function (oHeader) {
                        var isAssigned = false;
                        
                        if (oHeader.ToItem && oHeader.ToItem.results && oHeader.ToItem.results.length > 0) {
                            // Check if all items have quantity = 0 (fully assigned)
                            isAssigned = oHeader.ToItem.results.every(function(oItem) {
                                var qty = parseFloat(oItem.KWMENG || "0");
                                return qty === 0;
                            });
                        }
                        
                        return Object.assign({}, oHeader, {
                            __expanded: false,
                            __isAssigned: isAssigned
                        });
                    });
                    
                    console.log("Orders with assignment status:", aWithFlags.map(function(o) {
                        return { VBELN: o.VBELN, assigned: o.__isAssigned };
                    }));
                    
                    // Reset filters on new search
                    oViewModel.setProperty("/showAssignedOrders", true);
                    oViewModel.setProperty("/filterShippingCondition", "");
                    
                    // Store all data and apply filters
                    oViewModel.setProperty("/allHeaders", aWithFlags);
                    this._applyFilters();
                    
                    oViewModel.setProperty("/busy", false);
                }.bind(this),
                error: function () {
                    oViewModel.setProperty("/busy", false);
                    MessageToast.show("Unable to load sales orders. Try again.");
                }.bind(this)
            });
        },



        onHeaderToggle: function (oEvent) {
            var oContext = oEvent.getSource().getBindingContext("viewModel");
            if (!oContext) {
                return;
            }

            var sVbeln = oContext.getProperty("VBELN");
            var oViewModel = this.getView().getModel("viewModel");
            var aHeaders = oViewModel.getProperty("/headers") || [];
            var bExpanded = false;

            var aUpdated = aHeaders.map(function (oHeader) {
                if (oHeader.VBELN === sVbeln) {
                    bExpanded = !oHeader.__expanded;
                    return Object.assign({}, oHeader, {
                        __expanded: bExpanded
                    });
                }

                return Object.assign({}, oHeader, {
                    __expanded: false
                });
            });

            oViewModel.setProperty("/headers", aUpdated);
        },

        onToggleAssignedFilter: function(oEvent) {
            var bSelected = oEvent.getParameter("selected");
            var oViewModel = this.getView().getModel("viewModel");
            
            oViewModel.setProperty("/showAssignedOrders", bSelected);
            this._applyFilters();
        },

        onShippingConditionFilter: function(oEvent) {
            var oViewModel = this.getView().getModel("viewModel");
            this._applyFilters();
        },

        _applyFilters: function() {
            var oViewModel = this.getView().getModel("viewModel");
            var aAllHeaders = oViewModel.getProperty("/allHeaders") || [];
            var bShowAssigned = oViewModel.getProperty("/showAssignedOrders");
            var sShippingCondition = oViewModel.getProperty("/filterShippingCondition");
            var sSelectedSubTab = oViewModel.getProperty("/selectedOrdersSubTab") || "allOrders";
            
            // Apply filters
            var aFiltered = aAllHeaders.filter(function(oHeader) {
                // Filter by subtab selection
                if (sSelectedSubTab === "fullyAssigned" && !oHeader.__isAssigned) {
                    return false;
                }
                
                // Filter by assignment status (only for "All Orders" subtab)
                if (sSelectedSubTab === "allOrders" && !bShowAssigned && oHeader.__isAssigned) {
                    return false;
                }
                
                // Filter by shipping condition
                if (sShippingCondition && oHeader.VSBED !== sShippingCondition) {
                    return false;
                }
                
                return true;
            });
            
            oViewModel.setProperty("/headers", aFiltered);
            oViewModel.setProperty("/showEmptyMessage", aFiltered.length === 0);
        },

        onOrderSelection: function (oEvent) {
            var oListItem = oEvent.getParameter("listItem");
            var oContext = oListItem ? oListItem.getBindingContext("viewModel") : null;
            var oViewModel = this.getView().getModel("viewModel");

            if (oContext) {
                var oSelectedOrder = oContext.getObject();
                oViewModel.setProperty("/selectedOrder", oSelectedOrder);
            } else {
                oViewModel.setProperty("/selectedOrder", null);
            }
        },

        onManagePress: function (oEvent) {
            var oSource = oEvent.getSource();
            var oContext = oSource.getBindingContext("viewModel");
            
            // If no binding context on button, try parent elements
            if (!oContext) {
                var oParent = oSource.getParent();
                while (oParent && !oContext) {
                    oContext = oParent.getBindingContext("viewModel");
                    oParent = oParent.getParent();
                }
            }
            
            if (!oContext) {
                MessageToast.show("Error: No binding context found");
                console.error("onManagePress - No binding context found");
                return;
            }

            var oOrderData = oContext.getObject();
            if (!oOrderData || !oOrderData.VBELN) {
                MessageToast.show("Error: No order data found");
                console.error("onManagePress - No order data or VBELN", oOrderData);
                return;
            }

            // Store the complete order data in the component model for transfer
            var oComponent = this.getOwnerComponent();
            var oComponentModel = oComponent.getModel("componentData");
            
            if (!oComponentModel) {
                oComponentModel = new JSONModel({});
                oComponent.setModel(oComponentModel, "componentData");
            }
            
            oComponentModel.setProperty("/selectedOrder", oOrderData);
            
            // Set viewMode based on assignment status
            // If fully assigned, open in view mode (read-only); otherwise editable
            var bIsViewMode = !!oOrderData.__isAssigned;
            oComponentModel.setProperty("/viewMode", bIsViewMode);

            try {
                var oRouter = oComponent.getRouter();
                if (!oRouter) {
                    MessageToast.show("Error: Router not available");
                    console.error("onManagePress - Router not available");
                    return;
                }
                
                console.log("onManagePress - Navigating to ManageOrder with vbeln:", oOrderData.VBELN, "viewMode:", bIsViewMode);
                oRouter.navTo("ManageOrder", {
                    vbeln: oOrderData.VBELN
                }, false);
            } catch (error) {
                MessageToast.show("Navigation error: " + error.message);
                console.error("onManagePress - Navigation error:", error);
            }
        },

        _formatDateToValue: function (oDate) {
            var iYear = oDate.getFullYear();
            var iMonth = oDate.getMonth() + 1;
            var iDay = oDate.getDate();

            var sMonth = iMonth < 10 ? "0" + iMonth : String(iMonth);
            var sDay = iDay < 10 ? "0" + iDay : String(iDay);

            return iYear + "-" + sMonth + "-" + sDay;
        },

        formatShipping: function (sValue) {
            if (!sValue) {
                return "Shipping: -";
            }

            if (sValue === "CL") {
                return "Shipping: Collected";
            }

            if (sValue === "DL") {
                return "Shipping: Delivered";
            }

            return "Shipping: " + sValue;
        },

        onTabSelect: function (oEvent) {
            var sKey = oEvent.getParameter("key");
            var oViewModel = this.getView().getModel("viewModel");
            
            // Handle main tab selection
            if (sKey === "createdOrders") {
                this._loadCreatedOrders();
            } 
            // Handle subtab selection (allOrders or fullyAssigned)
            else if (sKey === "allOrders" || sKey === "fullyAssigned") {
                oViewModel.setProperty("/selectedOrdersSubTab", sKey);
                this._applyFilters();
            }
        },

        _loadCreatedOrders: function () {
            var oView = this.getView();
            var oModel = oView.getModel();
            var oViewModel = oView.getModel("viewModel");

            oViewModel.setProperty("/busy", true);

            oModel.read("/CustomerOrderSet", {
                success: function (oData) {
                    var aResults = (oData && oData.results) ? oData.results : [];
                    oViewModel.setProperty("/createdOrders", aResults);
                    oViewModel.setProperty("/busy", false);
                }.bind(this),
                error: function (oError) {
                    oViewModel.setProperty("/busy", false);
                    MessageToast.show("Failed to load created orders: " + (oError.message || "Unknown error"));
                }.bind(this)
            });
        },

        onRefreshCreatedOrders: function () {
            this._loadCreatedOrders();
        },

        onViewCreatedOrder: function (oEvent) {
            var oSource = oEvent.getSource();
            var oContext = oSource.getBindingContext("viewModel");
            
            if (!oContext) {
                MessageToast.show("Error: No binding context found");
                return;
            }

            var oOrderData = oContext.getObject();
            if (!oOrderData || !oOrderData.ORDER_NO) {
                MessageToast.show("Error: Order data not found");
                return;
            }

            var oView = this.getView();
            var oModel = oView.getModel();
            var oViewModel = oView.getModel("viewModel");
            
            oViewModel.setProperty("/busy", true);

            // Fetch full order details with items
            oModel.read("/CustomerOrderSet('" + oOrderData.ORDER_NO + "')", {
                urlParameters: {
                    "$expand": "CustOrderHeadertoItem"
                },
                success: function (oFullOrderData) {
                    oViewModel.setProperty("/busy", false);
                    
                    // Store the full order data in the component model
                    var oComponent = this.getOwnerComponent();
                    var oComponentModel = oComponent.getModel("componentData");
                    
                    if (!oComponentModel) {
                        oComponentModel = new JSONModel({});
                        oComponent.setModel(oComponentModel, "componentData");
                    }
                    
                    oComponentModel.setProperty("/selectedOrder", oFullOrderData);
                    oComponentModel.setProperty("/viewMode", true);  // View mode - readonly

                    // Navigate to ManageOrder route with ORDER_NO
                    try {
                        var oRouter = oComponent.getRouter();
                        oRouter.navTo("ManageOrder", {
                            vbeln: oFullOrderData.ORDER_NO
                        }, false);
                    } catch (error) {
                        MessageToast.show("Navigation error: " + error.message);
                    }
                }.bind(this),
                error: function (oError) {
                    oViewModel.setProperty("/busy", false);
                    
                    // Check if error is 404 (order not found/deleted)
                    var bOrderNotFound = oError.statusCode === "404" || oError.statusCode === 404;
                    
                    if (bOrderNotFound) {
                        // Silently refresh the created orders list to remove the deleted order
                        this._loadCreatedOrders();
                    } else {
                        MessageToast.show("Failed to load order details: " + (oError.message || "Unknown error"));
                    }
                }.bind(this)
            });
        }
    });
});
