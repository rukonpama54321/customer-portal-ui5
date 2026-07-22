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

            var sUser = sessionStorage.getItem("portal_username") || "";
            // Prefer a previously resolved SAP display name for this session so the
            // header doesn't flash the raw username before start_up responds.
            var sCachedName = sessionStorage.getItem("portal_userfullname") || "";
            var sInitialName = sCachedName || (sUser ? sUser.toUpperCase() : "User");

            var oViewModel = new JSONModel({
                busy: false,
                fromDate: this._formatDateToValue(oFromDate),
                toDate: this._formatDateToValue(oToday),
                headers: [],
                allHeaders: null,
                showEmptyMessage: false,
                filterAssignmentStatus: "",
                filterShippingCondition: "",
                filterMaterial: "",
                filterQuantity: "",
                uomHint: "",
                materialOptions: [{ MATNR: "", text: "All Products" }],
                createdOrders: [],
                selectedOrdersSubTab: "allOrders",
                currentUser: sInitialName,
                currentUserInitials: this._getInitials(sCachedName || sUser)
            });

            this.getView().setModel(oViewModel, "viewModel");

            // Resolve the real SAP user (sy-uname + full name) from the standard
            // start_up service and update the header when it responds.
            this._loadSapUser();

            // Preload the product catalog so the customer can pick a product as part
            // of the search criteria (before any date-range search has been run).
            this._loadMaterialCatalog();

            // Attach route matched handler to check for refresh flag
            var oRouter = this.getOwnerComponent().getRouter();
            if (oRouter) {
                oRouter.getRoute("RouteCustomerIndent").attachPatternMatched(this._onRouteMatched, this);
            }
        },

        /**
         * Derives up to two initials from a username for the header avatar.
         * Splits on common separators (space, dot, underscore, hyphen); if the
         * name is a single token, uses its first two characters.
         */
        _getInitials: function (sUser) {
            if (!sUser) { return "U"; }
            var aParts = sUser.trim().split(/[\s._-]+/).filter(Boolean);
            if (aParts.length >= 2) {
                return (aParts[0].charAt(0) + aParts[1].charAt(0)).toUpperCase();
            }
            return sUser.trim().substring(0, 2).toUpperCase();
        },

        /**
         * Fetches the authoritative logged-in SAP user from the standard
         * /sap/bc/ui2/start_up service and updates the header.
         *
         * Auth: on production (BSP) the session cookie identifies the user, so
         * credentials:"include" is enough. On localhost the dev proxy does not
         * inject the OData model's Basic-Auth header into arbitrary fetches, so
         * we attach it here from the token stored at login.
         *
         * Falls back silently to the typed username already in the model if the
         * service is unavailable (e.g. the ICF node is inactive).
         */
        _loadSapUser: function () {
            var bIsLocal = window.location.hostname === "localhost" ||
                           window.location.hostname === "127.0.0.1";
            var mHeaders = { "Accept": "application/json" };
            if (bIsLocal) {
                var sToken = sessionStorage.getItem("portal_token");
                if (sToken) {
                    mHeaders["Authorization"] = "Basic " + sToken;
                }
                mHeaders["sap-client"] = "300";
            }

            fetch("/sap/bc/ui2/start_up", {
                method: "GET",
                credentials: "include",
                headers: mHeaders
            })
            .then(function (oResponse) {
                if (!oResponse.ok) {
                    throw new Error("start_up returned " + oResponse.status);
                }
                return oResponse.json();
            })
            .then(function (oData) {
                if (!oData) { return; }
                var sFullName = oData.fullName ||
                    ((oData.firstName || "") + " " + (oData.lastName || "")).trim() ||
                    oData.id || "";
                if (!sFullName) { return; }

                var oViewModel = this.getView().getModel("viewModel");
                if (!oViewModel) { return; }
                oViewModel.setProperty("/currentUser", sFullName);
                oViewModel.setProperty("/currentUserInitials", this._getInitials(sFullName));
                sessionStorage.setItem("portal_userfullname", sFullName);
            }.bind(this))
            .catch(function () {
                // Keep the typed-username fallback already in the model.
            });
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

            // Re-run the search to get fresh SALESORDERHeaderSet data (updated KWMENG)
            // and fresh CustomerOrderSet flags whenever the user returns to this view.
            var oViewModel = this.getView().getModel("viewModel");
            var aAllHeaders = oViewModel.getProperty("/allHeaders");
            if (aAllHeaders && aAllHeaders.length > 0) {
                this.onSearch();
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
                    
                    // Record whether all items already have KWMENG = 0. This alone does NOT
                    // mean "fully assigned" – a sales doc can arrive from SAP with 0 open qty
                    // and no bulk indents at all. The __isAssigned / __isNoOpenQty distinction
                    // is finalized after the CustomerOrderSet fetch (needs bHasOrders).
                    var aWithFlags = aResults.map(function (oHeader) {
                        var bAllZeroQty = false;

                        if (oHeader.ToItem && oHeader.ToItem.results && oHeader.ToItem.results.length > 0) {
                            bAllZeroQty = oHeader.ToItem.results.every(function(oItem) {
                                var qty = parseFloat(oItem.KWMENG || "0");
                                return qty === 0;
                            });
                        }

                        return Object.assign({}, oHeader, {
                            __expanded: false,
                            __allZeroQty: bAllZeroQty,
                            __isAssigned: false,           // set after CustomerOrderSet fetch
                            __isPartiallyAssigned: false,  // set after CustomerOrderSet fetch
                            __isNoOpenQty: false           // set after CustomerOrderSet fetch
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

                            // Normalize a sales doc number to plain integer string for comparison
                            // (SAP returns "0000224200" from SALESORDERHeaderSet but "224200" from CustomerOrderSet)
                            var fnNorm = function (s) { return s ? String(parseInt(s, 10)) : ""; };

                            // Build a Set of normalized SALESORDER values that have at least one customer order
                            var oSalesOrdersWithOrders = {};
                            // Track sales orders where bulk indent was created with NO/N/A third party agent
                            var oSalesOrdersNoThirdParty = {};
                            // Track the raw THIRDPARTY value from the latest customer order per SALESORDER
                            var oSalesOrderThirdPartyRaw = {};
                            // Build a lookup: normSALESORDER → { MATNR: original KWMENG }
                            var oOrigQtyLookup = {};
                            aCustOrders.forEach(function (oCust) {
                                if (oCust.SALESORDER) {
                                    var sKey = fnNorm(oCust.SALESORDER);
                                    var sThirdParty = oCust.THIRDPARTY || "";
                                    var bIsNoOrNA = (sThirdParty === "0" || sThirdParty === "N" || sThirdParty === "NO" ||
                                                     sThirdParty === "3" || sThirdParty === "N/A");
                                    oSalesOrdersWithOrders[sKey] = true;
                                    if (bIsNoOrNA) {
                                        oSalesOrdersNoThirdParty[sKey] = true;
                                    }
                                    if (!oSalesOrderThirdPartyRaw[sKey] && sThirdParty) {
                                        oSalesOrderThirdPartyRaw[sKey] = sThirdParty;
                                    }
                                    var aItems = (oCust.CustOrderHeadertoItem && oCust.CustOrderHeadertoItem.results) || [];
                                    if (!oOrigQtyLookup[sKey]) {
                                        oOrigQtyLookup[sKey] = {};
                                    }
                                    aItems.forEach(function (oItem) {
                                        var sMATNR = oItem.MATNR || "";
                                        if (sMATNR && !oOrigQtyLookup[sKey][sMATNR]) {
                                            oOrigQtyLookup[sKey][sMATNR] = oItem.KWMENG || "";
                                        }
                                    });
                                }
                            });

                            // Mark __isAssigned / __isPartiallyAssigned / __isNoOpenQty:
                            // - Fully assigned requires at least one bulk indent (bHasOrders):
                            //     * DL orders / NO-N/A third-party orders: as soon as a bulk indent exists
                            //     * Other orders: when all SAP item quantities have reached 0
                            // - All-zero qty with NO bulk indent = "No Open Qty" (arrived empty from SAP),
                            //   NOT fully assigned.
                            var aFinal = aWithFlags.map(function (oHeader) {
                                var sKey = fnNorm(oHeader.VBELN);
                                var bHasOrders = !!oSalesOrdersWithOrders[sKey];
                                var bIsNoThirdParty = !!oSalesOrdersNoThirdParty[sKey];
                                var oQtyMap = oOrigQtyLookup[sKey] || {};
                                var sThirdPartyRaw = oSalesOrderThirdPartyRaw[sKey] || "";

                                var bIsDL = oHeader.VSBED === "DL";
                                var bAllZeroQty = !!oHeader.__allZeroQty;
                                var bIsFullyAssigned = bHasOrders && (bAllZeroQty || bIsDL || bIsNoThirdParty);
                                var bIsNoOpenQty = bAllZeroQty && !bHasOrders;
                                var bShowZeroQty = bHasOrders && (bIsDL || bIsNoThirdParty);

                                var oFinalHeader = Object.assign({}, oHeader, {
                                    __isAssigned: bIsFullyAssigned,
                                    __isPartiallyAssigned: bHasOrders && !bIsFullyAssigned,
                                    __isNoOpenQty: bIsNoOpenQty,
                                    __thirdPartyRaw: sThirdPartyRaw
                                });
                                if (oFinalHeader.ToItem && oFinalHeader.ToItem.results) {
                                    oFinalHeader.ToItem = {
                                        results: oFinalHeader.ToItem.results.map(function (oItem) {
                                            var sOrig = (bHasOrders && oQtyMap[oItem.MATNR]) ? oQtyMap[oItem.MATNR] : oItem.KWMENG;
                                            return Object.assign({}, oItem, {
                                                __origKWMENG: sOrig,
                                                __showZeroQty: bShowZeroQty
                                            });
                                        })
                                    };
                                }
                                return oFinalHeader;
                            });

                            oViewModel.setProperty("/allHeaders", aFinal);
                            this._buildMaterialOptions();
                            this._applyFilters();
                            oViewModel.setProperty("/busy", false);
                        }.bind(this),
                        error: function () {
                            // Fallback: proceed without partial assignment info
                            oViewModel.setProperty("/allHeaders", aWithFlags);
                            this._buildMaterialOptions();
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

        onAssignmentStatusFilter: function(oEvent) {
            this._applyFilters();
        },

        onShippingConditionFilter: function(oEvent) {
            var oViewModel = this.getView().getModel("viewModel");
            this._applyFilters();
        },

        _applyFilters: function() {
            var oViewModel = this.getView().getModel("viewModel");
            var aAllHeaders = oViewModel.getProperty("/allHeaders") || [];
            var sAssignmentStatus = oViewModel.getProperty("/filterAssignmentStatus") || "";
            var sShippingCondition = oViewModel.getProperty("/filterShippingCondition");
            var sSelectedSubTab = oViewModel.getProperty("/selectedOrdersSubTab") || "allOrders";
            var sFilterMaterial = oViewModel.getProperty("/filterMaterial") || "";
            var sFilterQuantity = oViewModel.getProperty("/filterQuantity");
            
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
                if (sSelectedSubTab === "allOrders" && sAssignmentStatus) {
                    if (sAssignmentStatus === "assigned" && !oHeader.__isAssigned) {
                        return false;
                    }
                    if (sAssignmentStatus === "partial" && !oHeader.__isPartiallyAssigned) {
                        return false;
                    }
                    if (sAssignmentStatus === "noOpenQty" && !oHeader.__isNoOpenQty) {
                        return false;
                    }
                    if (sAssignmentStatus === "unassigned" &&
                        (oHeader.__isAssigned || oHeader.__isPartiallyAssigned || oHeader.__isNoOpenQty)) {
                        return false;
                    }
                }
                
                // Filter by shipping condition
                if (sShippingCondition && oHeader.VSBED !== sShippingCondition) {
                    return false;
                }

                // Filter by product + available quantity (part of the search criteria).
                // A document qualifies when it has at least one item of the selected
                // product whose still-available quantity (KWMENG, treated as 0 once the
                // order is fully assigned) meets the requested minimum. With no quantity
                // entered, any document that still has that product available qualifies.
                if (sFilterMaterial) {
                    var fReqQty = parseFloat(sFilterQuantity);
                    var bHasReqQty = !isNaN(fReqQty) && fReqQty > 0;
                    var aItems = (oHeader.ToItem && oHeader.ToItem.results) || [];
                    var bMatch = aItems.some(function (oItem) {
                        if (oItem.MATNR !== sFilterMaterial) {
                            return false;
                        }
                        var fAvail = oItem.__showZeroQty ? 0 : parseFloat(oItem.KWMENG || "0");
                        // The user enters Min. Quantity in MT, but sales-document
                        // quantities (KWMENG) are stored in the document UOM — KG for
                        // these products. Convert the entered MT figure into the item's
                        // unit before comparing: 1 MT = 1000 KG. A non-KG item is assumed
                        // to already be in MT and is compared directly.
                        var sUom = (oItem.VRKME || "").trim().toUpperCase();
                        var fReqInItemUom = (sUom === "KG") ? (fReqQty * 1000) : fReqQty;
                        return bHasReqQty ? (fAvail >= fReqInItemUom) : (fAvail > 0);
                    });
                    if (!bMatch) {
                        return false;
                    }
                }

                return true;
            });
            
            oViewModel.setProperty("/headers", aFiltered);
            oViewModel.setProperty("/showEmptyMessage", aFiltered.length === 0);
        },

        /**
         * Loads the distinct product catalog (MATNR + description) from
         * SALESORDERItemSet so the Product search dropdown is populated up front,
         * before any date-range search has been run. Falls back silently — if this
         * fails, the dropdown still fills in from each search's results.
         */
        _loadMaterialCatalog: function() {
            var oModel = this.getView().getModel();
            if (!oModel) {
                return;
            }

            oModel.read("/SALESORDERItemSet", {
                urlParameters: {
                    "$select": "MATNR,ARKTX",
                    "$top": "5000"
                },
                success: function(oData) {
                    var aResults = (oData && oData.results) ? oData.results : [];
                    this._mergeMaterialOptions(aResults);
                }.bind(this),
                error: function() {
                    // Silent: search results will still populate the dropdown.
                }
            });
        },

        /**
         * Merges the given item-like objects (each with MATNR/ARKTX) into the
         * Product dropdown options, de-duplicated by material and sorted, keeping
         * the leading "All Products" entry (empty key) first.
         */
        _mergeMaterialOptions: function(aItems) {
            var oViewModel = this.getView().getModel("viewModel");
            var aOptions = (oViewModel.getProperty("/materialOptions") || []).slice();
            var oSeen = {};
            aOptions.forEach(function(o) {
                if (o.MATNR) {
                    oSeen[o.MATNR] = true;
                }
            });

            (aItems || []).forEach(function(oItem) {
                var sMATNR = oItem.MATNR || "";
                if (sMATNR && !oSeen[sMATNR]) {
                    oSeen[sMATNR] = true;
                    var sDesc = oItem.ARKTX || "";
                    aOptions.push({
                        MATNR: sMATNR,
                        text: sDesc ? (sMATNR + " - " + sDesc) : sMATNR
                    });
                }
            });

            aOptions.sort(function(a, b) {
                if (a.MATNR === "") { return -1; }
                if (b.MATNR === "") { return 1; }
                return a.MATNR < b.MATNR ? -1 : (a.MATNR > b.MATNR ? 1 : 0);
            });

            oViewModel.setProperty("/materialOptions", aOptions);
        },

        /**
         * Adds any products found in the currently loaded sales documents to the
         * Product dropdown (union with the preloaded catalog).
         */
        _buildMaterialOptions: function() {
            var oViewModel = this.getView().getModel("viewModel");
            var aAllHeaders = oViewModel.getProperty("/allHeaders") || [];
            var aItems = [];
            var oUomSeen = {};
            var aUoms = [];
            aAllHeaders.forEach(function(oHeader) {
                var aHeaderItems = (oHeader.ToItem && oHeader.ToItem.results) || [];
                aHeaderItems.forEach(function(oItem) {
                    aItems.push(oItem);
                    var sUom = (oItem.VRKME || "").trim();
                    if (sUom && !oUomSeen[sUom]) {
                        oUomSeen[sUom] = true;
                        aUoms.push(sUom);
                    }
                });
            });
            aUoms.sort();
            oViewModel.setProperty("/uomHint", aUoms.length ? ("Quantities in " + aUoms.join(", ")) : "");
            this._mergeMaterialOptions(aItems);
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
                    // Re-run search to get fresh KWMENG + assignment flags from backend
                    this.onSearch();
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

                    var fnNorm = function (s) { return s ? String(parseInt(s, 10)) : ""; };
                    var oSalesOrdersWithOrders = {};
                    var oSalesOrdersNoThirdParty = {};
                    var oSalesOrderThirdPartyRaw = {};

                    aCustOrders.forEach(function (oCust) {
                        if (oCust.SALESORDER) {
                            var sKey = fnNorm(oCust.SALESORDER);
                            var sThirdParty = oCust.THIRDPARTY || "";
                            var bIsNoOrNA = (sThirdParty === "0" || sThirdParty === "N" || sThirdParty === "NO" ||
                                             sThirdParty === "3" || sThirdParty === "N/A");
                            oSalesOrdersWithOrders[sKey] = true;
                            if (bIsNoOrNA) {
                                oSalesOrdersNoThirdParty[sKey] = true;
                            }
                            if (!oSalesOrderThirdPartyRaw[sKey] && sThirdParty) {
                                oSalesOrderThirdPartyRaw[sKey] = sThirdParty;
                            }
                        }
                    });

                    var aUpdated = aAllHeaders.map(function (oHeader) {
                        var sKey = fnNorm(oHeader.VBELN);
                        var bHasOrders    = !!oSalesOrdersWithOrders[sKey];
                        var bIsNoThirdParty = !!oSalesOrdersNoThirdParty[sKey];
                        var sThirdPartyRaw  = oSalesOrderThirdPartyRaw[sKey] || oHeader.__thirdPartyRaw || "";

                        // Re-check whether all item quantities are zero (fully consumed)
                        var bAllZero = false;
                        if (oHeader.ToItem && oHeader.ToItem.results && oHeader.ToItem.results.length > 0) {
                            bAllZero = oHeader.ToItem.results.every(function (oItem) {
                                return parseFloat(oItem.KWMENG || "0") === 0;
                            });
                        }

                        // Fully assigned requires at least one bulk indent (bHasOrders).
                        // All-zero qty with no bulk indent = "No Open Qty", not fully assigned.
                        var bIsDL = oHeader.VSBED === "DL";
                        var bIsAssigned = bHasOrders && (bAllZero || bIsDL || bIsNoThirdParty);
                        var bIsNoOpenQty = bAllZero && !bHasOrders;
                        var bShowZeroQty = bHasOrders && (bIsDL || bIsNoThirdParty);

                        var oUpdatedHeader = Object.assign({}, oHeader, {
                            __allZeroQty: bAllZero,
                            __isAssigned: bIsAssigned,
                            __isPartiallyAssigned: bHasOrders && !bIsAssigned,
                            __isNoOpenQty: bIsNoOpenQty,
                            __thirdPartyRaw: sThirdPartyRaw
                        });
                        if (oUpdatedHeader.ToItem && oUpdatedHeader.ToItem.results) {
                            oUpdatedHeader.ToItem = {
                                results: oUpdatedHeader.ToItem.results.map(function (oItem) {
                                    return Object.assign({}, oItem, { __showZeroQty: bShowZeroQty });
                                })
                            };
                        }
                        return oUpdatedHeader;
                    });

                    oViewModel.setProperty("/allHeaders", aUpdated);
                    this._buildMaterialOptions();
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
                        // Pre-format DelDate (Edm.DateTime arrives as JS Date) for display
                        var oDelDate = oOrder.DelDate;
                        if (oDelDate instanceof Date && !isNaN(oDelDate.getTime()) && oDelDate.getTime() !== 0) {
                            var iY = oDelDate.getFullYear();
                            var iM = oDelDate.getMonth() + 1;
                            var iD = oDelDate.getDate();
                            oOrder.DelDateDisplay = (iD < 10 ? "0" + iD : iD) + "." +
                                                    (iM < 10 ? "0" + iM : iM) + "." + iY;
                        } else {
                            oOrder.DelDateDisplay = "";
                        }

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
                            sessionStorage.removeItem("portal_isLoggedIn");
                            sessionStorage.removeItem("portal_username");
                            sessionStorage.removeItem("portal_token");
                            sessionStorage.removeItem("portal_userfullname");
                            // Full reload clears SAPUI5 model state (CSRF token, auth headers).
                            // Component.js will find no portal_isLoggedIn and route guard
                            // will redirect the user to the login screen.
                            window.location.href = window.location.origin + window.location.pathname;
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
        },

        onAddAgent: function () {
            this.getOwnerComponent().getRouter().navTo("AddAgentDetails");
        }
    });
});
