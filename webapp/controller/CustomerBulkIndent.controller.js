sap.ui.define([
    "sap/ui/core/mvc/Controller",
    "sap/ui/model/json/JSONModel",
    "sap/ui/model/Filter",
    "sap/ui/model/FilterOperator",
    "sap/m/MessageToast",
    "sap/m/MessageBox"
], function (Controller, JSONModel, Filter, FilterOperator, MessageToast, MessageBox) {
    "use strict";

    return Controller.extend("customerindent.controller.CustomerBulkIndent", {
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

            // Always refresh assignment flags on return so partial/fully assigned
            // lists reflect any orders created or updated since the last search.
            this._refreshSalesOrderFlags();
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
                            __isAssigned: isAssigned,
                            __isPartiallyAssigned: false  // will be set after CustomerOrderSet fetch
                        });
                    });

                    // Reset filters on new search
                    oViewModel.setProperty("/showAssignedOrders", true);
                    oViewModel.setProperty("/filterShippingCondition", "");

                    // Fetch CustomerOrderSet (SALESORDER is non-filterable, so fetch all and match client-side)
                    // to determine which sales orders have customer orders created (partially assigned)
                    oModel.read("/CustomerOrderSet", {
                        urlParameters: { "$top": "9999", "$expand": "CustOrderHeadertoItem" },
                        success: function (oCustData) {
                            var aCustOrders = (oCustData && oCustData.results) ? oCustData.results : [];

                            // Build a Set of SALESORDER values that have at least one customer order
                            // where 3rd Party Agent is YES — exclude NO and N/A orders from Partially Assigned
                            var oSalesOrdersWithOrders = {};
                            // Also track sales orders with NO/N/A customer orders — treat as fully assigned
                            var oSalesOrdersNoThirdParty = {};
                            // Track the raw THIRDPARTY value from the latest customer order per SALESORDER
                            var oSalesOrderThirdPartyRaw = {};
                            // Build a lookup: SALESORDER → { MATNR: original KWMENG }
                            // CustomerOrderItem.KWMENG holds the original ordered qty
                            var oOrigQtyLookup = {};
                            aCustOrders.forEach(function (oCust) {
                                if (oCust.SALESORDER) {
                                    var sThirdParty = oCust.THIRDPARTY || "";
                                    var bIsYes = (sThirdParty === "1" || sThirdParty === "Y" || sThirdParty === "YES");
                                    var bIsNoOrNA = (sThirdParty === "0" || sThirdParty === "N" || sThirdParty === "NO" ||
                                                     sThirdParty === "3" || sThirdParty === "N/A");
                                    if (bIsYes) {
                                        oSalesOrdersWithOrders[oCust.SALESORDER] = true;
                                    }
                                    if (bIsNoOrNA) {
                                        oSalesOrdersNoThirdParty[oCust.SALESORDER] = true;
                                    }
                                    // Store raw value (first one found; all orders for a SALESORDER share same value)
                                    if (!oSalesOrderThirdPartyRaw[oCust.SALESORDER] && sThirdParty) {
                                        oSalesOrderThirdPartyRaw[oCust.SALESORDER] = sThirdParty;
                                    }
                                    // Build original qty lookup from CustomerOrderItem
                                    var aItems = (oCust.CustOrderHeadertoItem && oCust.CustOrderHeadertoItem.results) || [];
                                    if (!oOrigQtyLookup[oCust.SALESORDER]) {
                                        oOrigQtyLookup[oCust.SALESORDER] = {};
                                    }
                                    aItems.forEach(function (oItem) {
                                        var sMATNR = oItem.MATNR || "";
                                        if (sMATNR && !oOrigQtyLookup[oCust.SALESORDER][sMATNR]) {
                                            oOrigQtyLookup[oCust.SALESORDER][sMATNR] = oItem.KWMENG || "";
                                        }
                                    });
                                }
                            });

                            // Mark __isPartiallyAssigned: has a customer order (YES agent) AND not fully assigned
                            // For NO/N/A orders: zero out all item quantities and mark as fully assigned
                            var aFinal = aWithFlags.map(function (oHeader) {
                                var bHasOrders = !!oSalesOrdersWithOrders[oHeader.VBELN];
                                var bIsNoThirdParty = !!oSalesOrdersNoThirdParty[oHeader.VBELN];
                                var oQtyMap = oOrigQtyLookup[oHeader.VBELN] || {};

                                var sThirdPartyRaw = oSalesOrderThirdPartyRaw[oHeader.VBELN] || "";

                                if (bIsNoThirdParty) {
                                    // Zero out remaining quantities for all items, but preserve the original for display
                                    var oUpdatedHeader = Object.assign({}, oHeader);
                                    if (oUpdatedHeader.ToItem && oUpdatedHeader.ToItem.results) {
                                        oUpdatedHeader.ToItem = {
                                            results: oUpdatedHeader.ToItem.results.map(function (oItem) {
                                                var sOrig = oQtyMap[oItem.MATNR] || oItem.KWMENG;
                                                return Object.assign({}, oItem, { __origKWMENG: sOrig, KWMENG: "0" });
                                            })
                                        };
                                    }
                                    oUpdatedHeader.__isAssigned = true;
                                    oUpdatedHeader.__isPartiallyAssigned = false;
                                    oUpdatedHeader.__thirdPartyRaw = sThirdPartyRaw;
                                    return oUpdatedHeader;
                                }

                                // For agent-fully-assigned orders, stamp __origKWMENG from CustomerOrderItem
                                var oFinalHeader = Object.assign({}, oHeader, {
                                    __isPartiallyAssigned: bHasOrders && !oHeader.__isAssigned,
                                    __thirdPartyRaw: sThirdPartyRaw
                                });
                                if (oFinalHeader.__isAssigned && Object.keys(oQtyMap).length > 0 &&
                                    oFinalHeader.ToItem && oFinalHeader.ToItem.results) {
                                    oFinalHeader.ToItem = {
                                        results: oFinalHeader.ToItem.results.map(function (oItem) {
                                            var sOrig = oQtyMap[oItem.MATNR] || oItem.KWMENG;
                                            return Object.assign({}, oItem, { __origKWMENG: sOrig });
                                        })
                                    };
                                }
                                return oFinalHeader;
                            });

                            oViewModel.setProperty("/allHeaders", aFinal);
                            this._applyFilters();
                            oViewModel.setProperty("/busy", false);
                        }.bind(this),
                        error: function () {
                            // Fallback: proceed without partial assignment info
                            oViewModel.setProperty("/allHeaders", aWithFlags);
                            this._applyFilters();
                            oViewModel.setProperty("/busy", false);
                        }.bind(this)
                    });
                }.bind(this),
                error: function (oError) {
                    oViewModel.setProperty("/busy", false);
                    this._handleODataError(
                        oError,
                        "Your orders could not be loaded. Please check your connection and try again."
                    );
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

                if (sSelectedSubTab === "partiallyAssigned" && !oHeader.__isPartiallyAssigned) {
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
                oRouter.navTo("ManageBulkIndent", {
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
            // Handle subtab selection
            else if (sKey === "allOrders" || sKey === "fullyAssigned" || sKey === "partiallyAssigned") {
                oViewModel.setProperty("/selectedOrdersSubTab", sKey);
                
                // Check if we have data from a search
                var aAllHeaders = oViewModel.getProperty("/allHeaders");
                
                if (!aAllHeaders || aAllHeaders.length === 0) {
                    // No search performed yet
                    oViewModel.setProperty("/headers", []);
                    oViewModel.setProperty("/showEmptyMessage", true);
                } else if (sKey === "partiallyAssigned" || sKey === "fullyAssigned") {
                    // Refresh flags from backend so the list reflects latest order state
                    this._refreshSalesOrderFlags();
                } else {
                    // Apply filters to existing data
                    this._applyFilters();
                }
            }
        },

        /**
         * Re-fetches CustomerOrderSet and recomputes __isAssigned / __isPartiallyAssigned
         * on all entries already in /allHeaders, then re-applies the current filters.
         * Called on every route-match and when switching to partial/fully-assigned subtabs.
         */
        _refreshSalesOrderFlags: function () {
            var oView = this.getView();
            var oModel = oView.getModel();
            var oViewModel = oView.getModel("viewModel");
            var aAllHeaders = oViewModel.getProperty("/allHeaders");

            if (!aAllHeaders || aAllHeaders.length === 0) {
                return;  // Nothing loaded yet – nothing to refresh
            }

            oViewModel.setProperty("/busy", true);

            oModel.read("/CustomerOrderSet", {
                urlParameters: { "$top": "9999", "$expand": "CustOrderHeadertoItem" },
                success: function (oCustData) {
                    var aCustOrders = (oCustData && oCustData.results) ? oCustData.results : [];

                    var oSalesOrdersWithOrders = {};
                    var oSalesOrdersNoThirdParty = {};
                    var oSalesOrderThirdPartyRaw = {};

                    aCustOrders.forEach(function (oCust) {
                        if (oCust.SALESORDER) {
                            var sThirdParty = oCust.THIRDPARTY || "";
                            var bIsYes = (sThirdParty === "1" || sThirdParty === "Y" || sThirdParty === "YES");
                            var bIsNoOrNA = (sThirdParty === "0" || sThirdParty === "N" || sThirdParty === "NO" ||
                                             sThirdParty === "3" || sThirdParty === "N/A");
                            if (bIsYes) {
                                oSalesOrdersWithOrders[oCust.SALESORDER] = true;
                            }
                            if (bIsNoOrNA) {
                                oSalesOrdersNoThirdParty[oCust.SALESORDER] = true;
                            }
                            if (!oSalesOrderThirdPartyRaw[oCust.SALESORDER] && sThirdParty) {
                                oSalesOrderThirdPartyRaw[oCust.SALESORDER] = sThirdParty;
                            }
                        }
                    });

                    var aUpdated = aAllHeaders.map(function (oHeader) {
                        var bHasOrders    = !!oSalesOrdersWithOrders[oHeader.VBELN];
                        var bIsNoThirdParty = !!oSalesOrdersNoThirdParty[oHeader.VBELN];
                        var sThirdPartyRaw  = oSalesOrderThirdPartyRaw[oHeader.VBELN] || oHeader.__thirdPartyRaw || "";

                        // Re-check whether all item quantities are zero (fully consumed)
                        var bAllZero = false;
                        if (oHeader.ToItem && oHeader.ToItem.results && oHeader.ToItem.results.length > 0) {
                            bAllZero = oHeader.ToItem.results.every(function (oItem) {
                                return parseFloat(oItem.KWMENG || "0") === 0;
                            });
                        }

                        var bIsAssigned = bAllZero || bIsNoThirdParty;

                        return Object.assign({}, oHeader, {
                            __isAssigned: bIsAssigned,
                            __isPartiallyAssigned: bHasOrders && !bIsAssigned,
                            __thirdPartyRaw: sThirdPartyRaw
                        });
                    });

                    oViewModel.setProperty("/allHeaders", aUpdated);
                    this._applyFilters();
                    oViewModel.setProperty("/busy", false);
                }.bind(this),
                error: function () {
                    // Silently fall back – just re-apply existing filters without flag changes
                    this._applyFilters();
                    oViewModel.setProperty("/busy", false);
                }.bind(this)
            });
        },

        _loadCreatedOrders: function () {
            var oView = this.getView();
            var oModel = oView.getModel();
            var oViewModel = oView.getModel("viewModel");

            oViewModel.setProperty("/busy", true);

            oModel.read("/CustomerOrderSet", {
                success: function (oData) {
                    var aResults = (oData && oData.results) ? oData.results : [];
                    
                    // For each order, check if it has agent allocations
                    var iChecksPending = aResults.length;
                    
                    if (iChecksPending === 0) {
                        oViewModel.setProperty("/createdOrders", aResults);
                        oViewModel.setProperty("/busy", false);
                        return;
                    }
                    
                    aResults.forEach(function(oOrder) {
                        // Check if agent allocations exist for this order
                        oModel.read("/AgentOrderAllocationSet", {
                            filters: [new sap.ui.model.Filter("ORDER_NO", sap.ui.model.FilterOperator.EQ, oOrder.ORDER_NO)],
                            success: function(oAllocData) {
                                oOrder.hasAllocations = (oAllocData.results && oAllocData.results.length > 0);
                                iChecksPending--;
                                
                                if (iChecksPending === 0) {
                                    oViewModel.setProperty("/createdOrders", aResults);
                                    oViewModel.setProperty("/busy", false);
                                }
                            },
                            error: function() {
                                oOrder.hasAllocations = false;
                                iChecksPending--;
                                
                                if (iChecksPending === 0) {
                                    oViewModel.setProperty("/createdOrders", aResults);
                                    oViewModel.setProperty("/busy", false);
                                }
                            }
                        });
                    });
                }.bind(this),
                error: function (oError) {
                    oViewModel.setProperty("/busy", false);
                    this._handleODataError(
                        oError,
                        "Your orders could not be loaded. Please try again or contact support."
                    );
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
                    oComponentModel.setProperty("/viewMode", false);  // ManageOrder will lock if not the latest order

                    // Navigate to ManageOrder route with ORDER_NO
                    try {
                        var oRouter = oComponent.getRouter();
                        oRouter.navTo("ManageBulkIndent", {
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
                        this._handleODataError(
                            oError,
                            "The order details could not be loaded. Please try again."
                        );
                    }
                }.bind(this)
            });
        },

        /**
         * Centralised OData error handler.
         * Detects session expiry (HTTP 401 / 403) and prompts the customer to log in again.
         * Falls back to a plain customer-friendly message for all other failures.
         * @param {object} oError  - The OData error object received in an error callback
         * @param {string} [sMsg]  - Optional context-specific fallback message
         */
        _handleODataError: function (oError, sMsg) {
            var iStatus = parseInt(oError && oError.statusCode, 10);

            if (iStatus === 401 || iStatus === 403) {
                MessageBox.error(
                    "Your session has expired. Please log in again to continue.",
                    {
                        title: "Session Expired",
                        actions: [MessageBox.Action.OK],
                        onClose: function () {
                            // Reloading causes SAP BSP to redirect to the login screen
                            window.location.reload();
                        }
                    }
                );
                return;
            }

            MessageBox.error(
                sMsg || "Something went wrong. Please try again, or contact support if the problem persists."
            );
        },

        /**
         * Creates a custom group header for created orders showing Sales Order with Net Value
         * @param {object} oGroup - The group information
         * @returns {sap.m.GroupHeaderListItem} The group header item
         */
        createGroupHeader: function (oGroup) {
            var sap = window.sap;
            var GroupHeaderListItem = sap.m.GroupHeaderListItem;

            // Get the sales order number from group key
            var sSalesOrder = oGroup.key;
            
            // Get data from viewModel since oGroup doesn't provide context
            var oViewModel = this.getView().getModel("viewModel");
            var aCreatedOrders = oViewModel.getProperty("/createdOrders") || [];
            
            // Find the first order with this sales order number to get NETWR, WAERK, and SHIP_COND
            var oFirstOrderInGroup = aCreatedOrders.find(function(oOrder) {
                return oOrder.SALESORDER === sSalesOrder;
            });
            
            var sNetValue = "";
            var sCurrency = "";
            var sShipping = "";
            
            if (oFirstOrderInGroup) {
                sNetValue = oFirstOrderInGroup.NETWR || "0";
                sCurrency = oFirstOrderInGroup.WAERK || "";
                
                // Format shipping condition
                var sShipCond = oFirstOrderInGroup.SHIP_COND || "";
                if (sShipCond === "CL") {
                    sShipping = "Collected";
                } else if (sShipCond === "DL") {
                    sShipping = "Delivered";
                } else {
                    sShipping = sShipCond;
                }
                
                // Format the net value with thousand separators
                if (sNetValue) {
                    var fValue = parseFloat(sNetValue);
                    if (!isNaN(fValue)) {
                        sNetValue = fValue.toLocaleString('en-IN', { 
                            minimumFractionDigits: 1, 
                            maximumFractionDigits: 1 
                        });
                    }
                }
            }

            // Format the title - Sales Order, Shipping, then net value
            var sTitle = "Sales Document: " + sSalesOrder + "     •     " + sShipping + "     •     Net Value: " + sNetValue + " " + sCurrency;

            // Create and return the GroupHeaderListItem
            var oGroupHeader = new GroupHeaderListItem({
                title: sTitle,
                upperCase: false
            });
            
            // Add custom style class for styling
            oGroupHeader.addStyleClass("sales-order-group-header-item");

            return oGroupHeader;
        }
    });
});
