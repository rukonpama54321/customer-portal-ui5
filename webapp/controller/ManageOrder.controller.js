sap.ui.define([
    "sap/ui/core/mvc/Controller",
    "sap/ui/core/routing/History",
    "sap/ui/model/json/JSONModel",
    "sap/ui/model/Filter",
    "sap/ui/model/FilterOperator",
    "sap/m/MessageToast",
    "sap/m/MessageBox",
    "sap/m/VBox",
    "sap/m/Text",
    "../util/formatter-dbg"
], function (Controller, History, JSONModel, Filter, FilterOperator, MessageToast, MessageBox, VBox, Text, formatter) {
    "use strict";

    return Controller.extend("customerindent.controller.ManageOrder", {
        formatter: formatter,
        
        onInit: function () {
            var oViewModel = new JSONModel({
                busy: false,
                orderCreated: false,
                viewMode: false,  // false = Manage mode, true = View mode
                header: {},
                items: [],
                orderNo: "",
                thirdPartyAgent: "",
                agents: [],
                transporters: [],
                agentAllocations: []
            });

            this.getView().setModel(oViewModel, "manageModel");

            var oRouter = this.getOwnerComponent().getRouter();
            oRouter.getRoute("ManageOrder").attachPatternMatched(this._onRouteMatched, this);
        },

        _loadAgents: function () {
            var oView = this.getView();
            var oModel = oView.getModel();
            var oViewModel = oView.getModel("manageModel");
            
            // Only load agents if backend is available
            oModel.read("/AgentDetailsSet", {
                success: function (oData) {
                    var aAgents = oData.results || [];
                    oViewModel.setProperty("/agents", aAgents);
                }.bind(this),
                error: function (oError) {
                    // Set empty array as fallback
                    oViewModel.setProperty("/agents", []);
                    console.warn("Agents service unavailable - using fallback", oError);
                }.bind(this)
            });
        },

        _loadTransporters: function () {
            var oView = this.getView();
            var oModel = oView.getModel();
            var oViewModel = oView.getModel("manageModel");
            
            // Only load transporters if backend is available  
            oModel.read("/TransporterDetailsSet", {
                success: function (oData) {
                    var aTransporters = oData.results || [];
                    console.log("Loaded transporters from backend:", aTransporters);
                    if (aTransporters.length > 0) {
                        console.log("First transporter sample:", aTransporters[0]);
                        console.log("Transporter fields:", Object.keys(aTransporters[0]));
                        console.log("Sample values - CARRIER:", aTransporters[0].CARRIER, "NAME:", aTransporters[0].NAME, "GSTN:", aTransporters[0].GSTN);
                    }
                    oViewModel.setProperty("/transporters", aTransporters);
                }.bind(this),
                error: function (oError) {
                    // Set empty array as fallback
                    oViewModel.setProperty("/transporters", []);
                    console.warn("Transporters service unavailable - using fallback", oError);
                }.bind(this)
            });
        },

        _initializeOrderItems: function (aItems) {
            // Initialize items with all required properties
            return aItems.map(function(oItem) {
                // Use actualAllocatedQty (calculated from agent allocations) if available, otherwise fall back to USEDQTY
                var fUsedQty = parseFloat(oItem.actualAllocatedQty || oItem.USEDQTY) || 0;
                return Object.assign({}, oItem, {
                    QUANTITY: "",
                    DELIVERY_LOC: "",
                    totalAllocatedQty: 0,  // Current order's agent allocations
                    previouslyUsedQty: fUsedQty  // Already used in other orders
                });
            });
        },

        _recalculateAllocatedQuantities: function () {
            var oView = this.getView();
            var oViewModel = oView.getModel("manageModel");
            
            var aItems = oViewModel.getProperty("/items") || [];
            var aAllocations = oViewModel.getProperty("/agentAllocations") || [];
            
            console.log("_recalculateAllocatedQuantities - Items count:", aItems.length, "Allocations count:", aAllocations.length);
            
            // Reset current order's allocated quantities to 0 (keep previouslyUsedQty intact)
            aItems.forEach(function(oItem) {
                oItem.totalAllocatedQty = 0;
                // Preserve previouslyUsedQty from other orders
                if (oItem.previouslyUsedQty === undefined) {
                    oItem.previouslyUsedQty = parseFloat(oItem.USEDQTY) || 0;
                }
            });
            
            // Recalculate based on current allocations
            aAllocations.forEach(function(oAllocation, iAllocIdx) {
                console.log("Processing allocation " + iAllocIdx + " with items:", oAllocation.items ? oAllocation.items.length : 0);
                
                if (oAllocation.items && oAllocation.items.length > 0) {
                    oAllocation.items.forEach(function(oAllocItem) {
                        // Find matching item in the main items array by POSNR AND MATNR (both must match)
                        var oMatchingItem = aItems.find(function(oItem) {
                            var bPosnrMatch = oItem.POSNR && oAllocItem.POSNR && oItem.POSNR === oAllocItem.POSNR;
                            var bMatnrMatch = (oItem.MATNR === oAllocItem.MATNR || 
                                              oItem.MATNR === oAllocItem.MATERIAL ||
                                              oItem.MATERIAL === oAllocItem.MATNR ||
                                              oItem.MATERIAL === oAllocItem.MATERIAL);
                            
                            // Match if both POSNR and MATNR are the same
                            return bPosnrMatch && bMatnrMatch;
                        });
                        
                        var fAllocQty = parseFloat(oAllocItem.agentQuantity) || 0;
                        console.log("Alloc item - POSNR:", oAllocItem.POSNR, "MATNR:", oAllocItem.MATNR, 
                                    "Qty:", fAllocQty, "Match found:", !!oMatchingItem);
                        
                        if (oMatchingItem) {
                            oMatchingItem.totalAllocatedQty += fAllocQty;
                            console.log("Updated item POSNR " + oMatchingItem.POSNR + 
                                      " (MATNR: " + oMatchingItem.MATNR + ") to totalAllocatedQty: " + oMatchingItem.totalAllocatedQty);
                        }
                    });
                }
            });
            
            // Update the model to trigger UI binding updates
            oViewModel.setProperty("/items", aItems);
            console.log("Final recalculated allocated quantities:", aItems);
            
            // Final debug after recalculation
            console.log("🎭 Post-recalculation debug:");
            console.log("  - Items updated in model");
            console.log("  - Allocations still in model:", (oViewModel.getProperty("/agentAllocations") || []).length);
            var aAllocationsCheck = oViewModel.getProperty("/agentAllocations") || [];
            if (aAllocationsCheck.length > 0) {
                console.log("  - First allocation check:", {
                    AGENT_NAME: aAllocationsCheck[0].AGENT_NAME,
                    TRANS_NAME: aAllocationsCheck[0].TRANS_NAME,
                    items_count: (aAllocationsCheck[0].items || []).length
                });
            }
            
            // Update allocation display for progress bars
            this._updateAllocationDisplayForAllItems();
        },

        _loadAgentAllocations: function (sOrderNo) {
            var oView = this.getView();
            var oModel = oView.getModel();
            var oViewModel = oView.getModel("manageModel");
            
            console.log("🔍 _loadAgentAllocations called for ORDER_NO:", sOrderNo);
            
            if (!sOrderNo) {
                oViewModel.setProperty("/agentAllocations", []);
                return;
            }
            
            // Debug current model state
            console.log("📊 Current model state before loading allocations:");
            console.log("  - agents count:", (oViewModel.getProperty("/agents") || []).length);
            console.log("  - transporters count:", (oViewModel.getProperty("/transporters") || []).length);
            console.log("  - agentAllocations count:", (oViewModel.getProperty("/agentAllocations") || []).length);
            
            // Get the current order items for merging full details
            var aOrderItems = oViewModel.getProperty("/items") || [];
            console.log("  - order items count:", aOrderItems.length);
            
            // Fetch agent allocations for this order from the database
            var aFilters = [new Filter("ORDER_NO", FilterOperator.EQ, sOrderNo)];
            
            console.log("🚀 Starting OData call to fetch agent allocations...");
            oModel.read("/AgentOrderAllocationSet", {
                filters: aFilters,
                urlParameters: {
                    "$expand": "AgentOrderHeadertoItem"
                },
                success: function (oData) {
                    console.log("✅ Agent allocations OData response received:", oData);
                    var aAllocations = oData.results || [];
                    console.log("📦 Number of allocations found:", aAllocations.length);
                    
                    if (aAllocations.length === 0) {
                        console.log("⚠️ No allocations found for ORDER_NO:", sOrderNo);
                        oViewModel.setProperty("/agentAllocations", []);
                        return;
                    }
                    
                    // Debug each allocation
                    aAllocations.forEach(function(oAlloc, index) {
                        console.log("🏷️ Allocation " + (index + 1) + ":");
                        console.log("  - ALLOCATION_ID:", oAlloc.ALLOCATION_ID);
                        console.log("  - AGENT_ID:", oAlloc.AGENT_ID);
                        console.log("  - AGENT_NAME:", oAlloc.AGENT_NAME);
                        console.log("  - TRANSPORTER:", oAlloc.TRANSPORTER);
                        console.log("  - TRANS_NAME:", oAlloc.TRANS_NAME);
                        console.log("  - LOADING_DATE:", oAlloc.LOADING_DATE);
                        console.log("  - Items count:", oAlloc.AgentOrderHeadertoItem ? oAlloc.AgentOrderHeadertoItem.results.length : 0);
                    });
                    
                    // Map backend allocations to the UI structure
                    var aMappedAllocations = aAllocations.map(function (oAllocation) {
                        console.log("🔄 Mapping allocation:", oAllocation.ALLOCATION_ID, "with items:", oAllocation.AgentOrderHeadertoItem);
                        
                        // Get agents and transporters lists for enriching data
                        var aAgents = oViewModel.getProperty("/agents") || [];
                        var aTransporters = oViewModel.getProperty("/transporters") || [];
                        
                        console.log("📋 Available for lookup - Agents:", aAgents.length, "Transporters:", aTransporters.length);
                        
                        // Look up agent details if not in the allocation data
                        var oAgentDetails = {};
                        if (oAllocation.AGENT_ID) {
                            var oFoundAgent = aAgents.find(function(oAgent) {
                                return oAgent.AGENT_ID === oAllocation.AGENT_ID;
                            });
                            if (oFoundAgent) {
                                oAgentDetails = {
                                    AGENT_NAME: oFoundAgent.AGENT_NAME || oAllocation.AGENT_NAME,
                                    AGENT_MAIL: oFoundAgent.AGENT_MAIL || oAllocation.AGENT_MAIL,
                                    AGENT_PH: oFoundAgent.AGENT_PH || oAllocation.AGENT_PH,
                                    AGENT_ADDR: oFoundAgent.AGENT_ADDR || oAllocation.AGENT_ADDR
                                };
                                console.log("👤 Found agent details:", oAgentDetails);
                            } else {
                                console.log("❌ Agent not found in lookup for ID:", oAllocation.AGENT_ID);
                                // Use data from allocation even if not in lookup
                                oAgentDetails = {
                                    AGENT_NAME: oAllocation.AGENT_NAME,
                                    AGENT_MAIL: oAllocation.AGENT_MAIL,
                                    AGENT_PH: oAllocation.AGENT_PH,
                                    AGENT_ADDR: oAllocation.AGENT_ADDR
                                };
                            }
                        }
                        
                        // Look up transporter details if not in the allocation data
                        var oTransporterDetails = {};
                        if (oAllocation.TRANSPORTER) {
                            console.log("🚛 Looking for transporter with CARRIER:", oAllocation.TRANSPORTER);
                            
                            // Backend strips leading zeros from CARRIER - normalize for comparison
                            var sNormalizedCarrier = oAllocation.TRANSPORTER.padStart(10, '0');
                            
                            var oFoundTransporter = aTransporters.find(function(oTransporter) {
                                var sTransporterCarrier = (oTransporter.CARRIER || "").padStart(10, '0');
                                return sTransporterCarrier === sNormalizedCarrier;
                            });
                            
                            if (oFoundTransporter) {
                                oTransporterDetails = {
                                    TRANS_NAME: oFoundTransporter.NAME || oAllocation.TRANS_NAME,
                                    TRANSPORTGSTN: oFoundTransporter.GSTN || oAllocation.TRANSPORTGSTN
                                };
                                console.log("🚛 Found transporter (normalized match):", oFoundTransporter.CARRIER, "→", oTransporterDetails);
                            } else {
                                console.log("❌ Transporter not found in lookup for CARRIER:", oAllocation.TRANSPORTER, 
                                           "(tried with padding:", sNormalizedCarrier + ")");
                                // Use data from allocation even if not in lookup
                                oTransporterDetails = {
                                    TRANS_NAME: oAllocation.TRANS_NAME,
                                    TRANSPORTGSTN: oAllocation.TRANSPORTGSTN
                                };
                            }
                        }
                        
                        // Map allocation items and merge with full order item details
                        // Show ALL order items, with allocation data merged for items that were allocated
                        var bIsReadonly = !!oAllocation.ALLOCATION_ID;  // Determine if allocation is from backend
                        
                        // WORKAROUND: Backend duplicates items - deduplicate by MATERIAL
                        // Keep LAST occurrence and validate quantity consistency
                        var mDeduplicatedItems = {};
                        var mDuplicateQuantities = {}; // Track all quantities for each material
                        
                        if (oAllocation.AgentOrderHeadertoItem && oAllocation.AgentOrderHeadertoItem.results) {
                            oAllocation.AgentOrderHeadertoItem.results.forEach(function(oAllocItem) {
                                var sMaterial = oAllocItem.MATERIAL;
                                
                                // Track all quantities for this material
                                if (!mDuplicateQuantities[sMaterial]) {
                                    mDuplicateQuantities[sMaterial] = [];
                                }
                                mDuplicateQuantities[sMaterial].push(oAllocItem.QUANTITY);
                                
                                if (!mDeduplicatedItems[sMaterial]) {
                                    // First occurrence - keep it for now
                                    mDeduplicatedItems[sMaterial] = Object.assign({}, oAllocItem);
                                } else {
                                    // Duplicate found - REPLACE with latest (keep LAST occurrence)
                                    var sOldQty = mDeduplicatedItems[sMaterial].QUANTITY;
                                    var sNewQty = oAllocItem.QUANTITY;
                                    
                                    // Check if quantities differ (backend data corruption)
                                    if (sOldQty !== sNewQty) {
                                        console.error("⚠️ CRITICAL BACKEND BUG: Material", sMaterial, 
                                                     "has duplicates with DIFFERENT quantities! Previous:", sOldQty, 
                                                     "Current:", sNewQty, "- Keeping LAST occurrence:", sNewQty);
                                    } else {
                                        console.warn("BACKEND BUG: Duplicate item detected for MATERIAL:", sMaterial, 
                                                    "QUANTITY:", sNewQty, "- Keeping LAST occurrence");
                                    }
                                    
                                    // Replace with latest occurrence
                                    mDeduplicatedItems[sMaterial] = Object.assign({}, oAllocItem);
                                }
                            });
                            
                            // Final validation: Log summary of quantity inconsistencies
                            Object.keys(mDuplicateQuantities).forEach(function(sMaterial) {
                                var aQuantities = mDuplicateQuantities[sMaterial];
                                if (aQuantities.length > 1) {
                                    var bAllSame = aQuantities.every(function(q) { return q === aQuantities[0]; });
                                    if (!bAllSame) {
                                        console.error("❌ DATA CORRUPTION for", sMaterial + ":", 
                                                     "Backend returned", aQuantities.length, "duplicates with quantities:", 
                                                     aQuantities.join(", "), "- Using LAST:", aQuantities[aQuantities.length - 1]);
                                    }
                                }
                            });
                        }
                        
                        var aItems = aOrderItems.map(function(oOrderItem) {
                            // Find if this order item has allocation data (using deduplicated map)
                            var sMaterial = oOrderItem.MATNR || oOrderItem.MATERIAL;
                            var oAllocItem = mDeduplicatedItems[sMaterial];
                            
                            // Return order item with allocation data if exists
                            return Object.assign({}, oOrderItem, {
                                agentQuantity: oAllocItem ? oAllocItem.QUANTITY : "",
                                DELIVERY_LOC: oAllocItem ? oAllocItem.DELIVERY_LOC : "",
                                _readonly: bIsReadonly
                            });
                        });
                        
                        if (oAllocation.AgentOrderHeadertoItem && oAllocation.AgentOrderHeadertoItem.results) {
                            var iOriginalCount = oAllocation.AgentOrderHeadertoItem.results.length;
                            var iDeduplicatedCount = Object.keys(mDeduplicatedItems).length;
                            console.log("📊 Found", iOriginalCount, "items for allocation:", oAllocation.ALLOCATION_ID,
                                       "(Deduplicated to", iDeduplicatedCount, "unique items)");
                        } else {
                            console.log("⚠️ No items found in AgentOrderHeadertoItem for allocation:", oAllocation.ALLOCATION_ID);
                        }
                        
                        var oMappedAllocation = {
                            __expanded: false,  // Initially collapsed
                            _readonly: !!oAllocation.ALLOCATION_ID,  // Mark as readonly if from backend
                            ORDER_NO: oAllocation.ORDER_NO,
                            ALLOCATION_ID: oAllocation.ALLOCATION_ID,
                            AGENT_ID: oAllocation.AGENT_ID,
                            AGENT_NAME: oAgentDetails.AGENT_NAME || oAllocation.AGENT_NAME || "",
                            AGENT_MAIL: oAgentDetails.AGENT_MAIL || oAllocation.AGENT_MAIL || "",
                            AGENT_PH: oAgentDetails.AGENT_PH || oAllocation.AGENT_PH || "",
                            AGENT_ADDR: oAgentDetails.AGENT_ADDR || oAllocation.AGENT_ADDR || "",
                            LOADING_DATE: oAllocation.LOADING_DATE,
                            TRANSPORTER: oAllocation.TRANSPORTER,
                            TRANS_NAME: oTransporterDetails.TRANS_NAME || oAllocation.TRANS_NAME || "",
                            TRANSPORTGSTN: oTransporterDetails.TRANSPORTGSTN || oAllocation.TRANSPORTGSTN || "",
                            items: aItems
                        };
                        console.log("✨ Final mapped allocation:", {
                            ALLOCATION_ID: oMappedAllocation.ALLOCATION_ID,
                            AGENT_NAME: oMappedAllocation.AGENT_NAME,
                            TRANS_NAME: oMappedAllocation.TRANS_NAME,
                            items_count: oMappedAllocation.items.length
                        });
                        return oMappedAllocation;
                    });
                    
                    console.log("🎯 Setting /agentAllocations to:", aMappedAllocations.length, "allocations");
                    oViewModel.setProperty("/agentAllocations", aMappedAllocations);
                    console.log("✅ Successfully loaded and mapped agent allocations");
                    
                    // Debug UI binding state
                    console.log("🎪 UI Debug - After setting allocations:");
                    console.log("  - Model path /agentAllocations:", oViewModel.getProperty("/agentAllocations"));
                    console.log("  - Allocations length:", (oViewModel.getProperty("/agentAllocations") || []).length);
                    console.log("  - thirdPartyAgent:", oViewModel.getProperty("/thirdPartyAgent"));
                    console.log("  - orderCreated:", oViewModel.getProperty("/orderCreated"));
                    
                    // Check visibility condition
                    var bSectionVisible = oViewModel.getProperty("/orderCreated") && 
                                         (oViewModel.getProperty("/thirdPartyAgent") === 'YES' || 
                                          (oViewModel.getProperty("/agentAllocations") || []).length > 0);
                    console.log("  - Agent section should be visible:", bSectionVisible);
                    
                    // Force UI update
                    oViewModel.updateBindings(true);
                    
                    // Recalculate allocated quantities to update the items array and quantity bars
                    this._recalculateAllocatedQuantities();
                }.bind(this),
                error: function (oError) {
                    // No allocations found or error - set empty array
                    console.error("💥 Error loading agent allocations:", oError);
                    oViewModel.setProperty("/agentAllocations", []);
                    console.warn("Failed to load agent allocations:", oError);
                }.bind(this)
            });
        },

        _onRouteMatched: function (oEvent) {
            var sVbeln = oEvent.getParameter("arguments").vbeln;
            if (!sVbeln) {
                return;
            }

            var oView = this.getView();
            var oViewModel = oView.getModel("manageModel");
            var oComponent = this.getOwnerComponent();
            
            // Get data from component model (passed from CustomerOrder)
            var oComponentModel = oComponent.getModel("componentData");
            var oSelectedOrder = oComponentModel ? oComponentModel.getProperty("/selectedOrder") : null;
            var bViewMode = oComponentModel ? oComponentModel.getProperty("/viewMode") : false;
            
            console.log("_onRouteMatched - viewMode from componentData:", bViewMode);
            
            // Set view mode in the manage model
            oViewModel.setProperty("/viewMode", bViewMode);
            console.log("Set viewMode in manageModel to:", bViewMode);
            
            // Handle both sales orders (VBELN) and created orders (ORDER_NO)
            var bIsSalesOrder = oSelectedOrder && oSelectedOrder.VBELN === sVbeln;
            var bIsCreatedOrder = oSelectedOrder && oSelectedOrder.ORDER_NO === sVbeln;
            
            if (bIsSalesOrder) {
                // Sales Order: Use the passed data directly - reset order state
                console.log("Processing Sales Order - viewMode should be editable (false)");
                oViewModel.setProperty("/viewMode", false);  // Explicitly ensure editable for sales orders
                oViewModel.setProperty("/orderNo", "");
                oViewModel.setProperty("/orderCreated", false);
                oViewModel.setProperty("/thirdPartyAgent", "");
                oViewModel.setProperty("/header", oSelectedOrder);
                var aItems = (oSelectedOrder.ToItem && oSelectedOrder.ToItem.results) ? oSelectedOrder.ToItem.results : [];
                
                console.log("ManageOrder - Sales Order items:", aItems);
                
                // Add allocation properties to each item
                var aItemsWithAllocation = this._initializeOrderItems(aItems);
                
                oViewModel.setProperty("/items", aItemsWithAllocation);
                oViewModel.setProperty("/agentAllocations", []);
                
                // Initialize progress bar display values
                this._updateAllocationDisplayForAllItems();
            } else if (bIsCreatedOrder) {
                // Created Order: Fetch from backend to verify it still exists
                var oModel = oView.getModel();
                oViewModel.setProperty("/busy", true);
                
                oModel.read("/CustomerOrderSet('" + oSelectedOrder.ORDER_NO + "')", {
                    urlParameters: {
                        "$expand": "CustOrderHeadertoItem"
                    },
                    success: function (oFullOrderData) {
                        oViewModel.setProperty("/busy", false);
                        oViewModel.setProperty("/orderNo", oFullOrderData.ORDER_NO);
                        oViewModel.setProperty("/orderCreated", true);
                        
                        // Map created order fields to header structure
                        var oHeader = {
                            VBELN: oFullOrderData.SALESORDER,
                            KUNNR: oFullOrderData.KUNNR,
                            BSTNK: oFullOrderData.BSTNK,
                            BSTDK: oFullOrderData.BSTDK,
                            VSBED: oFullOrderData.SHIP_COND,
                            NETWR: oFullOrderData.NETWR,
                            WAERK: oFullOrderData.WAERK,
                            ORDER_NO: oFullOrderData.ORDER_NO,
                            SALESORDER: oFullOrderData.SALESORDER,
                            SHIP_COND: oFullOrderData.SHIP_COND,
                            THIRDPARTY: oFullOrderData.THIRDPARTY
                        };
                        oViewModel.setProperty("/header", oHeader);
                        
                        // Map created order items
                        var aCreatedItems = (oFullOrderData.CustOrderHeadertoItem && oFullOrderData.CustOrderHeadertoItem.results) 
                            ? oFullOrderData.CustOrderHeadertoItem.results : [];
                        
                        var aItemsWithAllocation = this._initializeOrderItems(aCreatedItems);
                        
                        oViewModel.setProperty("/items", aItemsWithAllocation);
                        
                        // Convert THIRDPARTY from backend format to UI format (YES/NO)
                        var sThirdParty = "";
                        
                        console.log("Raw THIRDPARTY value:", oFullOrderData.THIRDPARTY, "Type:", typeof oFullOrderData.THIRDPARTY);
                        console.log("SHIP_COND (VSBED):", oFullOrderData.SHIP_COND);
                        
                        // Handle various formats: "1"/"0", "Y"/"N", "YES"/"NO"
                        if (oFullOrderData.THIRDPARTY === "1" || oFullOrderData.THIRDPARTY === "Y" || oFullOrderData.THIRDPARTY === "YES") {
                            sThirdParty = "YES";
                        } else if (oFullOrderData.THIRDPARTY === "0" || oFullOrderData.THIRDPARTY === "N" || oFullOrderData.THIRDPARTY === "NO") {
                            sThirdParty = "NO";
                        } else {
                            sThirdParty = oFullOrderData.THIRDPARTY || "";
                        }
                        
                        console.log("Converted thirdPartyAgent:", sThirdParty);
                        oViewModel.setProperty("/thirdPartyAgent", sThirdParty);
                        
                        // Always load agents and transporters for viewing created orders
                        // (needed for allocation lookups even if thirdPartyAgent is NO)
                        this._loadAgents();
                        this._loadTransporters();
                        
                        // Force update all bindings on the model to propagate changes immediately
                        oViewModel.updateBindings(false);
                        
                        // Set ComboBox value only if shipping condition is 'CL'
                        if (oFullOrderData.SHIP_COND === "CL") {
                            var oController = this;
                            var iRetries = 0;
                            var fnSetComboBoxValue = function() {
                                var oComboBox = oController.byId("thirdPartyAgentComboBox");
                                if (oComboBox) {
                                    console.log("Setting ComboBox selectedKey to:", sThirdParty);
                                    oComboBox.setSelectedKey(sThirdParty);
                                } else if (iRetries < 5) {
                                    iRetries++;
                                    setTimeout(fnSetComboBoxValue, 100);
                                }
                            };
                            setTimeout(fnSetComboBoxValue, 100);
                        }
                        
                        // Wait for agents/transporters to load before fetching allocations
                        // (allocations need agent/transporter data for lookups)
                        setTimeout(function() {
                            this._loadAgentAllocations(oFullOrderData.ORDER_NO);
                        }.bind(this), 500);
                    }.bind(this),
                    error: function (oError) {
                        oViewModel.setProperty("/busy", false);
                        
                        // Order was deleted - reset to initial state with empty order number
                        var bOrderNotFound = oError.statusCode === "404" || oError.statusCode === 404;
                        
                        if (bOrderNotFound && oSelectedOrder.SALESORDER) {
                            // Fetch the sales order to allow creating a new customer order
                            this._loadSalesOrderForNewOrder(oSelectedOrder.SALESORDER);
                        } else {
                            MessageToast.show("Failed to load order. Please select an order from the list.");
                            this.onNavBack();
                        }
                    }.bind(this)
                });
            } else {
                MessageToast.show("Order data not found. Please select an order from the list.");
                this.onNavBack();
            }
        },

        _loadSalesOrderForNewOrder: function (sSalesOrder) {
            var oView = this.getView();
            var oModel = oView.getModel();
            var oViewModel = oView.getModel("manageModel");
            
            oViewModel.setProperty("/busy", true);
            
            // Fetch the sales order from backend
            oModel.read("/SALESORDERHeaderSet('" + sSalesOrder + "')", {
                urlParameters: {
                    "$expand": "ToItem"
                },
                success: function (oSalesOrderData) {
                    oViewModel.setProperty("/busy", false);
                    
                    // Reset to new order state
                    oViewModel.setProperty("/orderNo", "");
                    oViewModel.setProperty("/orderCreated", false);
                    oViewModel.setProperty("/thirdPartyAgent", "");
                    
                    // Set header data from sales order
                    oViewModel.setProperty("/header", oSalesOrderData);
                    
                    // Set items from sales order
                    var aItems = (oSalesOrderData.ToItem && oSalesOrderData.ToItem.results) ? oSalesOrderData.ToItem.results : [];
                    var aItemsWithAllocation = this._initializeOrderItems(aItems);
                    
                    oViewModel.setProperty("/items", aItemsWithAllocation);
                    oViewModel.setProperty("/agentAllocations", []);
                    
                    // Initialize progress bar display values
                    this._updateAllocationDisplayForAllItems();
                }.bind(this),
                error: function (oError) {
                    oViewModel.setProperty("/busy", false);
                    MessageToast.show("Failed to load sales order. Please try again.");
                    this.onNavBack();
                }.bind(this)
            });
        },

        onThirdPartyAgentChange: function (oEvent) {
            var oSource = oEvent.getSource();
            var sSelectedValue = oEvent.getParameter("selectedItem").getKey();
            
            // Clear validation error state when a valid selection is made
            if (oSource && sSelectedValue) {
                oSource.setValueState("None");
                oSource.setValueStateText("");
            }
            
            // Load agents and transporters only if 3rd party agent is selected as YES
            if (sSelectedValue === "YES") {
                this._loadAgents();
                this._loadTransporters();
            }
        },

        onAgentChange: function (oEvent) {
            var oComboBox = oEvent.getSource();
            var oBindingContext = oComboBox.getBindingContext("manageModel");
            if (!oBindingContext) {
                return;
            }

            var oSelectedItem = oEvent.getParameter("selectedItem");
            if (!oSelectedItem) {
                return;
            }

            var sSelectedKey = oSelectedItem.getKey();
            var oViewModel = this.getView().getModel("manageModel");
            var aAgents = oViewModel.getProperty("/agents") || [];

            var oSelectedAgent = aAgents.find(function (agent) {
                return agent.AGENT_ID === sSelectedKey;
            });

            if (oSelectedAgent) {
                var sPath = oBindingContext.getPath();
                oViewModel.setProperty(sPath + "/AGENT_NAME", oSelectedAgent.AGENT_NAME);
                oViewModel.setProperty(sPath + "/AGENT_ID", oSelectedAgent.AGENT_ID);
                oViewModel.setProperty(sPath + "/AGENT_MAIL", oSelectedAgent.AGENT_MAIL || "");
                oViewModel.setProperty(sPath + "/AGENT_PH", oSelectedAgent.AGENT_PH || "");
                oViewModel.setProperty(sPath + "/AGENT_ADDR", oSelectedAgent.AGENT_ADDR || "");
            }
        },

        onTransporterChange: function (oEvent) {
            var oComboBox = oEvent.getSource();
            var oBindingContext = oComboBox.getBindingContext("manageModel");
            if (!oBindingContext) {
                return;
            }

            var oSelectedItem = oEvent.getParameter("selectedItem");
            var sSelectedKey = oSelectedItem ? oSelectedItem.getKey() : oComboBox.getSelectedKey();
            var oViewModel = this.getView().getModel("manageModel");
            var aTransporters = oViewModel.getProperty("/transporters") || [];

            if (!sSelectedKey) {
                return;
            }

            var oSelectedTransporter = aTransporters.find(function (transporter) {
                return transporter.CARRIER === sSelectedKey;
            });

            if (!oSelectedTransporter && oSelectedItem) {
                var oCtx = oSelectedItem.getBindingContext("manageModel");
                oSelectedTransporter = oCtx ? oCtx.getObject() : null;
            }

            if (oSelectedTransporter) {
                console.log("Selected transporter object:", oSelectedTransporter);
                console.log("Transporter fields:", Object.keys(oSelectedTransporter));
                console.log("Field values - CARRIER:", oSelectedTransporter.CARRIER, "NAME:", oSelectedTransporter.NAME, "GSTN:", oSelectedTransporter.GSTN);
                var sPath = oBindingContext.getPath();
                oViewModel.setProperty(sPath + "/TRANSPORTER", oSelectedTransporter.CARRIER);
                oViewModel.setProperty(sPath + "/TRANS_NAME", oSelectedTransporter.NAME || "");
                oViewModel.setProperty(sPath + "/TRANSPORTGSTN", oSelectedTransporter.GSTN || "");
                console.log("Set TRANSPORTGSTN to:", oSelectedTransporter.GSTN);
            }
        },

        _validateAgentItemQty: function (iEnteredQty, iOrderQty, iTotalAllocatedQty) {
            var iAvailableQty = (iOrderQty || 0) - (iTotalAllocatedQty || 0);
            return {
                isValid: iEnteredQty <= iAvailableQty,
                availableQty: iAvailableQty,
                errorMessage: "Quantity (" + iEnteredQty + ") exceeds available limit (" + iAvailableQty + ")"
            };
        },

        onAgentItemQtyChange: function (oEvent) {
            var oInput = oEvent.getSource();
            var oBindingContext = oInput.getBindingContext("manageModel");
            
            console.log("=== onAgentItemQtyChange FIRED ===");
            console.log("Input value from event:", oInput.getValue());
            console.log("Binding context path:", oBindingContext ? oBindingContext.getPath() : "NO CONTEXT");
            
            if (!oBindingContext) {
                return;
            }

            // Get the item and agent allocation context
            var oViewModel = this.getView().getModel("manageModel");
            var oAgentAllocationContext = oInput.getBindingContext("manageModel");
            var sPath = oAgentAllocationContext.getPath();
            var aParts = sPath.split("/");
            
            console.log("Full path:", sPath);
            console.log("Path parts:", aParts);
            
            // Determine which agent allocation and item we're in
            // Path should be like: /agentAllocations/0/items/1
            if (aParts.length < 4) {
                console.warn("Path too short, expected /agentAllocations/X/items/Y, got:", sPath);
                return;
            }

            var iAgentIndex = parseInt(aParts[2]);
            var iItemIndex = parseInt(aParts[4]);
            
            console.log("Agent index:", iAgentIndex, "Item index:", iItemIndex);
            
            var aAgentAllocations = oViewModel.getProperty("/agentAllocations") || [];
            var aMainItems = oViewModel.getProperty("/items") || [];
            
            if (iAgentIndex < 0 || iAgentIndex >= aAgentAllocations.length) {
                return;
            }

            var oAgent = aAgentAllocations[iAgentIndex];
            if (!oAgent || !oAgent.items || iItemIndex < 0 || iItemIndex >= oAgent.items.length) {
                return;
            }

            var oAgentItem = oAgent.items[iItemIndex];
            var sMaterial = oAgentItem.MATNR;
            var iEnteredQty = parseFloat(oAgentItem.agentQuantity) || 0;
            
            console.log("Agent item data:", {
                POSNR: oAgentItem.POSNR,
                MATNR: oAgentItem.MATNR,
                agentQuantity: oAgentItem.agentQuantity,
                parsedQty: iEnteredQty
            });

            // Find the corresponding main item
            var oMainItem = aMainItems.find(function (item) {
                return item.MATNR === sMaterial;
            });

            if (!oMainItem) {
                return;
            }

            // Calculate total allocated quantity across all agents for this material
            // Excluding the current agent's quantity to get the actual other allocations
            var iTotalAllocatedByOthers = 0;
            aAgentAllocations.forEach(function (agent, agentIdx) {
                if (agent.items) {
                    agent.items.forEach(function (item) {
                        if (item.MATNR === sMaterial) {
                            // Don't count the current agent's current input
                            if (agentIdx !== iAgentIndex) {
                                iTotalAllocatedByOthers += parseFloat(item.agentQuantity) || 0;
                            }
                        }
                    });
                }
            });

            // Validate the entered quantity
            var oValidation = this._validateAgentItemQty(iEnteredQty, oMainItem.KWMENG, iTotalAllocatedByOthers);
            
            if (!oValidation.isValid && iEnteredQty > 0) {
                oInput.setValueState("Error");
                oInput.setValueStateText(oValidation.errorMessage);
                MessageToast.show(oValidation.errorMessage);
                console.warn("Quantity validation failed for Material:", sMaterial, oValidation.errorMessage);
            } else {
                oInput.setValueState("None");
                oInput.setValueStateText("");
            }

            // Calculate total allocated quantity across all agents for this material (including current)
            var iTotalAllocated = iTotalAllocatedByOthers + iEnteredQty;

            // Update the main item with total allocated quantity
            var iMainItemIndex = aMainItems.indexOf(oMainItem);
            if (iMainItemIndex >= 0) {
                oViewModel.setProperty("/items/" + iMainItemIndex + "/totalAllocatedQty", iTotalAllocated);
            }

            // Recalculate allocation display for all items
            this._updateAllocationDisplayForAllItems();

            console.log("Agent item qty changed - Material:", sMaterial, "Total allocated:", iTotalAllocated, "Available:", oValidation.availableQty);
            console.log("=== onAgentItemQtyChange END ===");
        },

        _updateAllocationDisplayForAllItems: function () {
            var oViewModel = this.getView().getModel("manageModel");
            var aItems = oViewModel.getProperty("/items") || [];
            var aAgentAllocations = oViewModel.getProperty("/agentAllocations") || [];

            aItems.forEach(function (oItem, iIndex) {
                var sPOSNR = oItem.POSNR;
                var fTotalAllocated = 0;

                // Sum up all agent quantities for this item
                aAgentAllocations.forEach(function (oAgent) {
                    if (oAgent.items && Array.isArray(oAgent.items)) {
                        oAgent.items.forEach(function (oAgentItem) {
                            if (oAgentItem.POSNR === sPOSNR && oAgentItem.agentQuantity) {
                                fTotalAllocated += parseFloat(oAgentItem.agentQuantity) || 0;
                            }
                        });
                    }
                });

                // Calculate values for progress bar
                var fKWMENG = parseFloat(oItem.KWMENG) || 0;
                var fPercent = fKWMENG > 0 ? (fTotalAllocated / fKWMENG) * 100 : 0;
                var sDisplay = fTotalAllocated + " / " + fKWMENG + " " + (oItem.VRKME || "") + " allocated";
                var sState = fTotalAllocated > 0 ? "Success" : "None";

                // Update the item with calculated values
                oViewModel.setProperty("/items/" + iIndex + "/allocationPercent", fPercent);
                oViewModel.setProperty("/items/" + iIndex + "/allocationDisplay", sDisplay);
                oViewModel.setProperty("/items/" + iIndex + "/allocationState", sState);
            });
        },

        onAddAgentAllocation: function () {
            var oViewModel = this.getView().getModel("manageModel");
            var aAllocations = oViewModel.getProperty("/agentAllocations") || [];
            var aItems = oViewModel.getProperty("/items") || [];

            // Create a new agent allocation with blank item quantities
            var oNewAllocation = {
                __expanded: true,
                _readonly: false,  // New allocations are editable
                AGENT_ID: "",
                AGENT_NAME: "",
                LOADING_DATE: new Date().toISOString().split("T")[0],
                TRANSPORTER: "",
                TRANS_NAME: "",
                TRANSPORTGSTN: "",
                items: aItems.map(function (oItem) {
                    return Object.assign({}, oItem, {
                        agentQuantity: "",
                        DELIVERY_LOC: "",
                        _readonly: false  // New allocation items are editable
                    });
                })
            };

            aAllocations.push(oNewAllocation);
            oViewModel.setProperty("/agentAllocations", aAllocations);

            // Update allocation display for progress bars
            this._updateAllocationDisplayForAllItems();

            MessageToast.show("New agent allocation added");
        },

        onDeleteAgentAllocation: function (oEvent) {
            var oButton = oEvent.getSource();
            var oBindingContext = oButton.getBindingContext("manageModel");
            if (!oBindingContext) return;
            
            var oView = this.getView();
            var oViewModel = oView.getModel("manageModel");
            var sPath = oBindingContext.getPath();
            var iIndex = parseInt(sPath.split("/").pop());
            var aAllocations = oViewModel.getProperty("/agentAllocations") || [];
            var oAllocation = aAllocations[iIndex];
            
            MessageBox.confirm("Are you sure you want to delete this agent allocation?", {
                title: "Confirm Deletion",
                onClose: function (sAction) {
                    if (sAction !== MessageBox.Action.OK) {
                        return;
                    }

                    if (!oAllocation) {
                        return;
                    }

                    var sOrderNo = oAllocation.ORDER_NO || oViewModel.getProperty("/orderNo");
                    var sAllocationId = oAllocation.ALLOCATION_ID;
                    var sAgentId = oAllocation.AGENT_ID;

                    if (sOrderNo && sAllocationId && sAgentId) {
                        var oModel = oView.getModel();
                        
                        // Delete the allocation header (backend should cascade delete items)
                        var fnDeleteAllocationHeader = function() {
                            var sHeaderKeyPath = oModel.createKey("AgentOrderAllocationSet", {
                                ORDER_NO: sOrderNo,
                                ALLOCATION_ID: sAllocationId,
                                AGENT_ID: sAgentId
                            });

                            console.log("Deleting allocation header:", sHeaderKeyPath);

                            oModel.remove("/" + sHeaderKeyPath, {
                                success: function () {
                                    aAllocations.splice(iIndex, 1);
                                    oViewModel.setProperty("/agentAllocations", aAllocations);
                                    
                                    // Recalculate allocated quantities for all items after deletion
                                    this._recalculateAllocatedQuantities();
                                    
                                    // Update USEDQTY in backend after deletion
                                    var aItems = oViewModel.getProperty("/items") || [];
                                    this._updateUsedQtyForItems(sOrderNo, aItems, function (oResult) {
                                        oViewModel.setProperty("/busy", false);
                                        
                                        if (oResult && oResult.hadError) {
                                            MessageBox.warning("Agent allocation deleted, but updating used quantities failed: " + oResult.error, {
                                                title: "Partial Success"
                                            });
                                        } else {
                                            MessageToast.show("Agent allocation deleted and quantities updated successfully");
                                        }
                                    }.bind(this));
                                }.bind(this),
                                error: function (oError) {
                                    oViewModel.setProperty("/busy", false);
                                    var sErrorMessage = "Failed to delete agent allocation";
                                    try {
                                        var oErrorResponse = JSON.parse(oError.responseText);
                                        sErrorMessage = oErrorResponse.error.message.value || sErrorMessage;
                                    } catch (e) {
                                        sErrorMessage = oError.message || sErrorMessage;
                                    }
                                    MessageBox.error("Delete failed: " + sErrorMessage);
                                }.bind(this)
                            });
                        }.bind(this);

                        oViewModel.setProperty("/busy", true);
                        fnDeleteAllocationHeader();  // Delete the allocation header
                    } else {
                        aAllocations.splice(iIndex, 1);
                        oViewModel.setProperty("/agentAllocations", aAllocations);
                        
                        // Recalculate allocated quantities for all items after deletion
                        this._recalculateAllocatedQuantities();
                        
                        MessageToast.show("Agent allocation deleted");
                    }
                }.bind(this)
            });
        },

        onSave: function () {
            MessageToast.show("Save will be wired after the remaining details are confirmed.");
        },

        onSaveAgentAllocations: function () {
            var oView = this.getView();
            var oViewModel = oView.getModel("manageModel");
            var oModel = oView.getModel();
            var sOrderNo = oViewModel.getProperty("/orderNo");

            if (!sOrderNo) {
                MessageToast.show("Order number not found. Cannot save agent allocations.");
                return;
            }

            var aAgentAllocations = oViewModel.getProperty("/agentAllocations") || [];
            
            if (aAgentAllocations.length === 0) {
                MessageToast.show("No agent allocations to save.");
                return;
            }

            // Validate agent allocations before saving
            var oAllocValidation = this._validateAgentAllocations();
            if (!oAllocValidation.isValid) {
                MessageBox.error("Agent Allocation Validation Error: " + oAllocValidation.error, {
                    title: "Validation Failed"
                });
                return;
            }

            oViewModel.setProperty("/busy", true);

            var oHeader = oViewModel.getProperty("/header") || {};
            
            // Build payloads with validation and enrichment
            var aPayloads = [];
            try {
                aPayloads = aAgentAllocations.map(function (oAllocation, iIndex) {
                    console.log("📦 Building payload for allocation " + (iIndex + 1) + ":", {
                        AGENT_ID: oAllocation.AGENT_ID,
                        AGENT_NAME: oAllocation.AGENT_NAME,
                        TRANSPORTER: oAllocation.TRANSPORTER
                    });
                    return this._buildAgentAllocationDeepEntity(oHeader, sOrderNo, oAllocation);
                }.bind(this));
                console.log("✅ All payloads built successfully:", aPayloads.length, "allocations");
            } catch (oError) {
                oViewModel.setProperty("/busy", false);
                MessageBox.error("Validation failed: " + oError.message, {
                    title: "Save Failed"
                });
                return;
            }

            var bHadError = false;
            var sLastError = "";
            var iCurrentIndex = 0;

            // Send allocations sequentially to avoid batch/changeset issues
            var fnSaveNextAllocation = function () {
                if (iCurrentIndex >= aPayloads.length) {
                    // All allocations saved, now update used quantities
                    var aItems = oViewModel.getProperty("/items") || [];
                    this._updateUsedQtyForItems(sOrderNo, aItems, function (oResult) {
                        oViewModel.setProperty("/busy", false);

                        if (bHadError) {
                            MessageBox.error(sLastError || "Some agent allocations failed to save.", {
                                title: "Save Failed"
                            });
                            return;
                        }

                        if (oResult && oResult.hadError) {
                            MessageBox.warning("Agent allocations saved, but updating used quantities failed: " + oResult.error, {
                                title: "Partial Save"
                            });
                            return;
                        }

                        MessageBox.success("Agent allocations saved successfully.", {
                            title: "Save Successful",
                            onClose: function () {
                                this._loadAgentAllocations(sOrderNo);
                            }.bind(this)
                        });
                    }.bind(this));
                    return;
                }

                var oPayload = aPayloads[iCurrentIndex];
                iCurrentIndex += 1;

                console.log("=== SAVING ALLOCATION " + iCurrentIndex + " of " + aPayloads.length + " ===");
                console.log("Full payload being sent to backend:");
                console.log(JSON.stringify(oPayload, null, 2));
                console.log("Number of items in payload:", oPayload.AgentOrderHeadertoItem.results.length);
                console.log("Item details:");
                oPayload.AgentOrderHeadertoItem.results.forEach(function(item, idx) {
                    console.log("  Item " + idx + ": MATERIAL=" + item.MATERIAL + " QUANTITY=" + item.QUANTITY + " UOM=" + item.UOM);
                });

                oModel.create("/AgentOrderAllocationSet", oPayload, {
                    success: function (oData) {
                        console.log("=== ALLOCATION " + (iCurrentIndex - 1) + " SAVED SUCCESSFULLY ===");
                        console.log("Backend response:");
                        console.log(JSON.stringify(oData, null, 2));
                        if (oData.AgentOrderHeadertoItem && oData.AgentOrderHeadertoItem.results) {
                            console.log("Backend returned " + oData.AgentOrderHeadertoItem.results.length + " items");
                            oData.AgentOrderHeadertoItem.results.forEach(function(item, idx) {
                                console.log("  Response Item " + idx + ": MATERIAL=" + item.MATERIAL + " QUANTITY=" + item.QUANTITY);
                            });
                        }
                        fnSaveNextAllocation();
                    }.bind(this),
                    error: function (oError) {
                        bHadError = true;
                        try {
                            var oErrorResponse = JSON.parse(oError.responseText);
                            sLastError = oErrorResponse.error.message.value || sLastError;
                        } catch (e) {
                            sLastError = oError.message || sLastError;
                        }
                        console.error("Failed to save allocation " + (iCurrentIndex - 1) + ":", sLastError);
                        fnSaveNextAllocation();
                    }.bind(this)
                });
            }.bind(this);

            fnSaveNextAllocation();
        },

        _updateUsedQtyForItems: function (sOrderNo, aItems, fnDone) {
            var oView = this.getView();
            var oModel = oView.getModel();

            if (!sOrderNo || !aItems || aItems.length === 0) {
                if (fnDone) {
                    fnDone({ hadError: false });
                }
                return;
            }

            console.log("Updating USEDQTY for order:", sOrderNo, "Items:", aItems);

            var iCurrentIndex = 0;
            var bHadError = false;
            var sLastError = "";

            // Try updating items directly via CustomerOrderItemSet
            var fnUpdateNextItem = function () {
                if (iCurrentIndex >= aItems.length) {
                    if (fnDone) {
                        fnDone({ hadError: bHadError, error: sLastError });
                    }
                    return;
                }

                var oItem = aItems[iCurrentIndex];
                iCurrentIndex += 1;

                if (!oItem.POSNR) {
                    fnUpdateNextItem();
                    return;
                }

                // Skip items with zero allocated quantity (not allocated, may not exist in backend)
                var fAllocatedQty = parseFloat(oItem.totalAllocatedQty) || 0;
                if (fAllocatedQty === 0) {
                    console.log("Skipping USEDQTY update for POSNR:", oItem.POSNR, "(not allocated, qty=0)");
                    fnUpdateNextItem();
                    return;
                }

                // Try direct entity set path
                var sItemKey = oModel.createKey("CustomerOrderItemSet", {
                    ORDER_NO: sOrderNo,
                    POSNR: oItem.POSNR
                });

                var sUsedQty = String(fAllocatedQty);
                var oPayload = {
                    USEDQTY: sUsedQty
                };

                console.log("Attempting direct update:", sItemKey, "USEDQTY:", sUsedQty);

                oModel.update("/" + sItemKey, oPayload, {
                    merge: true,
                    success: function () {
                        console.log("USEDQTY updated successfully for POSNR:", oItem.POSNR);
                        fnUpdateNextItem();
                    }.bind(this),
                    error: function (oError) {
                        bHadError = true;
                        try {
                            var oErrorResponse = JSON.parse(oError.responseText);
                            sLastError = oErrorResponse.error.message.value || oError.message;
                        } catch (e) {
                            sLastError = oError.message;
                        }
                        console.error("Error updating USEDQTY for POSNR:", oItem.POSNR, sLastError);
                        fnUpdateNextItem();
                    }.bind(this)
                });
            }.bind(this);

            fnUpdateNextItem();
        },

        _buildAgentAllocationDeepEntity: function (oHeader, sOrderNo, oAllocation) {
            var oViewModel = this.getView().getModel("manageModel");
            var aAgents = oViewModel.getProperty("/agents") || [];
            var aTransporters = oViewModel.getProperty("/transporters") || [];
            
            var fnVal = function (v, fallback) {
                return v === undefined || v === null || v === "" ? fallback : v;
            };

            // Enrich agent data from agents list
            var oAgentData = {
                AGENT_ID: fnVal(oAllocation.AGENT_ID, ""),
                AGENT_NAME: fnVal(oAllocation.AGENT_NAME, ""),
                AGENT_MAIL: fnVal(oAllocation.AGENT_MAIL, ""),
                AGENT_PH: fnVal(oAllocation.AGENT_PH, ""),
                AGENT_ADDR: fnVal(oAllocation.AGENT_ADDR, "")
            };

            // If AGENT_ID exists, lookup agent details to ensure all fields are populated
            if (oAgentData.AGENT_ID) {
                var oFoundAgent = aAgents.find(function(agent) {
                    return agent.AGENT_ID === oAgentData.AGENT_ID;
                });
                
                if (oFoundAgent) {
                    console.log("💪 Enriching agent data for AGENT_ID:", oAgentData.AGENT_ID, "with:", oFoundAgent);
                    oAgentData.AGENT_NAME = fnVal(oFoundAgent.AGENT_NAME, oAgentData.AGENT_NAME);
                    oAgentData.AGENT_MAIL = fnVal(oFoundAgent.AGENT_MAIL, oAgentData.AGENT_MAIL);
                    oAgentData.AGENT_PH = fnVal(oFoundAgent.AGENT_PH, oAgentData.AGENT_PH);
                    oAgentData.AGENT_ADDR = fnVal(oFoundAgent.AGENT_ADDR, oAgentData.AGENT_ADDR);
                } else {
                    console.warn("⚠️ Agent not found in list for AGENT_ID:", oAgentData.AGENT_ID);
                }
            }

            // Enrich transporter data from transporters list
            var oTransporterData = {
                TRANSPORTER: fnVal(oAllocation.TRANSPORTER, ""),
                TRANS_NAME: fnVal(oAllocation.TRANS_NAME, ""),
                TRANSPORTGSTN: fnVal(oAllocation.TRANSPORTGSTN, "")
            };

            // If TRANSPORTER exists, lookup transporter details to ensure all fields are populated
            if (oTransporterData.TRANSPORTER) {
                // Normalize CARRIER for lookup (backend strips leading zeros)
                var sNormalizedCarrier = oTransporterData.TRANSPORTER.padStart(10, '0');
                
                var oFoundTransporter = aTransporters.find(function(transporter) {
                    var sTransporterCarrier = (transporter.CARRIER || "").padStart(10, '0');
                    return sTransporterCarrier === sNormalizedCarrier;
                });
                
                if (oFoundTransporter) {
                    console.log("🚛 Enriching transporter data for CARRIER:", oTransporterData.TRANSPORTER, "with:", oFoundTransporter);
                    oTransporterData.TRANS_NAME = fnVal(oFoundTransporter.NAME, oTransporterData.TRANS_NAME);
                    oTransporterData.TRANSPORTGSTN = fnVal(oFoundTransporter.GSTN, oTransporterData.TRANSPORTGSTN);
                } else {
                    console.warn("⚠️ Transporter not found in list for CARRIER:", oTransporterData.TRANSPORTER);
                }
            }

            // Validation: Ensure critical fields are not blank
            var aValidationErrors = [];
            if (!oAgentData.AGENT_ID) {
                aValidationErrors.push("Agent ID is required");
            }
            if (!oAgentData.AGENT_NAME) {
                aValidationErrors.push("Agent Name is required");
            }
            if (!fnVal(oAllocation.LOADING_DATE, "")) {
                aValidationErrors.push("Loading Date is required");
            }
            if (!oTransporterData.TRANSPORTER) {
                aValidationErrors.push("Transporter is required");
            }
            if (!oTransporterData.TRANS_NAME) {
                aValidationErrors.push("Transporter Name is required");
            }

            if (aValidationErrors.length > 0) {
                console.error("🚫 Allocation validation failed:", aValidationErrors.join(", "));
                throw new Error("Invalid allocation data: " + aValidationErrors.join(", "));
            }

            console.log("✅ Building enriched allocation payload:", {
                AGENT_ID: oAgentData.AGENT_ID,
                AGENT_NAME: oAgentData.AGENT_NAME,
                TRANSPORTER: oTransporterData.TRANSPORTER,
                TRANS_NAME: oTransporterData.TRANS_NAME,
                items: (oAllocation.items || []).filter(function (oItem) {
                    var fQty = parseFloat(oItem.agentQuantity);
                    return !isNaN(fQty) && fQty > 0;
                }).length
            });

            // Only return fields that are accepted by the backend AgentOrderAllocationSet entity
            // Remove display-only fields (AGENT_NAME, AGENT_MAIL, AGENT_PH, AGENT_ADDR, TRANS_NAME)
            // These are kept in the UI model for display but not sent to backend
            return {
                ORDER_NO: sOrderNo,
                AGENT_ID: oAgentData.AGENT_ID,
                KUNNR: fnVal(oHeader.KUNNR, ""),
                KUNNR_DESC: fnVal(oHeader.BSTNK, ""),
                LOADING_DATE: fnVal(oAllocation.LOADING_DATE, new Date().toISOString().split("T")[0]),
                TRANSPORTER: oTransporterData.TRANSPORTER,
                TRANSPORTGSTN: oTransporterData.TRANSPORTGSTN,
                AgentOrderHeadertoItem: {
                    results: (oAllocation.items || [])
                        .filter(function (oItem) {
                            var fQty = parseFloat(oItem.agentQuantity);
                            return !isNaN(fQty) && fQty > 0;
                        })
                        .map(function (oItem) {
                            var fQty = parseFloat(oItem.agentQuantity);
                            return {
                                ORDER_NO: sOrderNo,
                                AGENT_ID: oAgentData.AGENT_ID,
                                POSNR: fnVal(oItem.POSNR, ""),
                                MATERIAL: fnVal(oItem.MATNR, ""),
                                QUANTITY: isNaN(fQty) ? "0" : String(fQty),
                                UOM: fnVal(oItem.VRKME, ""),
                                DELIVERY_LOC: fnVal(oItem.DELIVERY_LOC, "")
                            };
                        })
                }
            };
        },

        onDeleteOrder: function () {
            var oView = this.getView();
            var oViewModel = oView.getModel("manageModel");
            var sOrderNo = oViewModel.getProperty("/orderNo");
            var sSalesOrder = oViewModel.getProperty("/header/VBELN");

            if (!sOrderNo) {
                MessageToast.show("Order number not found. Cannot delete.");
                return;
            }

            // Check if there are any agent allocations
            var aAgentAllocations = oViewModel.getProperty("/agentAllocations") || [];
            if (aAgentAllocations.length > 0) {
                MessageBox.error(
                    "Cannot delete order with existing agent allocations.\n\nPlease delete all agent allocations first before deleting the order.",
                    {
                        title: "Delete Not Allowed"
                    }
                );
                return;
            }

            // Check if this is the latest order for the sales order
            this._checkIfLatestOrder(sOrderNo, sSalesOrder);
        },

        _checkIfLatestOrder: function (sOrderNo, sSalesOrder) {
            var oView = this.getView();
            var oModel = oView.getModel();
            var oViewModel = oView.getModel("manageModel");

            if (!sSalesOrder) {
                MessageToast.show("Sales order not found. Cannot validate deletion.");
                return;
            }

            oViewModel.setProperty("/busy", true);

            // Read all orders to find if this is the latest for the sales order
            oModel.read("/CustomerOrderSet", {
                filters: [new Filter("SALESORDER", FilterOperator.EQ, sSalesOrder)],
                success: function (oData) {
                    oViewModel.setProperty("/busy", false);
                    
                    var aOrders = oData.results || [];
                    if (aOrders.length === 0) {
                        MessageToast.show("No orders found for this sales order.");
                        return;
                    }

                    // Sort orders by ORDER_NO descending to find the latest
                    aOrders.sort(function (a, b) {
                        return b.ORDER_NO.localeCompare(a.ORDER_NO);
                    });

                    var sLatestOrderNo = aOrders[0].ORDER_NO;

                    console.log("Checking deletion eligibility:");
                    console.log("  Current Order:", sOrderNo);
                    console.log("  Latest Order for Sales Order " + sSalesOrder + ":", sLatestOrderNo);
                    console.log("  All Orders for this Sales Order:", aOrders.map(function (o) { return o.ORDER_NO; }).join(", "));

                    if (sOrderNo !== sLatestOrderNo) {
                        MessageBox.error(
                            "Only the latest order can be deleted.\n\n" +
                            "Sales Order: " + sSalesOrder + "\n" +
                            "Latest Order: " + sLatestOrderNo + "\n" +
                            "Current Order: " + sOrderNo + "\n\n" +
                            "Please delete order " + sLatestOrderNo + " first before deleting this order.",
                            {
                                title: "Delete Not Allowed",
                                details: "Order Sequence: " + aOrders.map(function (o) { return o.ORDER_NO; }).join(" → ")
                            }
                        );
                        return;
                    }

                    // This is the latest order, show confirmation dialog
                    MessageBox.confirm(
                        "Are you sure you want to delete order " + sOrderNo + "? This will delete the order header and all associated items.\n\n" +
                        "This is the latest order for Sales Order " + sSalesOrder + ".",
                        {
                            title: "Delete Order",
                            icon: MessageBox.Icon.WARNING,
                            actions: [MessageBox.Action.DELETE, MessageBox.Action.CANCEL],
                            emphasizedAction: MessageBox.Action.CANCEL,
                            onClose: function (sAction) {
                                if (sAction === MessageBox.Action.DELETE) {
                                    this._performDelete(sOrderNo);
                                }
                            }.bind(this)
                        }
                    );
                }.bind(this),
                error: function (oError) {
                    oViewModel.setProperty("/busy", false);
                    MessageToast.show("Failed to validate deletion: " + (oError.message || "Unknown error"));
                }.bind(this)
            });
        },

        _performDelete: function (sOrderNo) {
            var oView = this.getView();
            var oViewModel = oView.getModel("manageModel");
            var oModel = oView.getModel();

            oViewModel.setProperty("/busy", true);

            oModel.remove("/CustomerOrderSet('" + sOrderNo + "')", {
                success: function () {
                    oViewModel.setProperty("/busy", false);
                    
                    // Set flag to trigger refresh of created orders on CustomerOrder
                    var oComponent = this.getOwnerComponent();
                    var oComponentModel = oComponent.getModel("componentData");
                    if (!oComponentModel) {
                        oComponentModel = new JSONModel({});
                        oComponent.setModel(oComponentModel, "componentData");
                    }
                    oComponentModel.setProperty("/refreshCreatedOrders", true);
                    
                    MessageBox.success("Order " + sOrderNo + " and its items have been deleted successfully.", {
                        onClose: function () {
                            this.onNavBack();
                        }.bind(this)
                    });
                }.bind(this),
                error: function (oError) {
                    oViewModel.setProperty("/busy", false);
                    var sErrorMessage = "Failed to delete order";
                    try {
                        var oErrorResponse = JSON.parse(oError.responseText);
                        sErrorMessage = oErrorResponse.error.message.value || sErrorMessage;
                    } catch (e) {
                        sErrorMessage = oError.message || sErrorMessage;
                    }
                    MessageBox.error("Delete failed: " + sErrorMessage);
                }.bind(this)
            });
        },

        _validateAgentAllocations: function () {
            var oViewModel = this.getView().getModel("manageModel");
            var aItems = oViewModel.getProperty("/items") || [];
            var aAgentAllocations = oViewModel.getProperty("/agentAllocations") || [];

            console.log("Validating agent allocations:", aAgentAllocations);

            // If no agent allocations, validation passes
            if (aAgentAllocations.length === 0) {
                return {
                    isValid: true,
                    error: null
                };
            }

            // Validate each allocation
            for (var i = 0; i < aAgentAllocations.length; i++) {
                var oAllocation = aAgentAllocations[i];
                console.log("Validating allocation " + (i + 1) + ":", oAllocation);
                
                // Check if AGENT_ID is filled and valid
                var sAgentId = String(oAllocation.AGENT_ID).trim();
                if (!sAgentId || sAgentId === "") {
                    return {
                        isValid: false,
                        error: "Allocation " + (i + 1) + ": Agent is required"
                    };
                }

                // Check if AGENT_NAME is populated (should be set when agent is selected)
                var sAgentName = String(oAllocation.AGENT_NAME || "").trim();
                if (!sAgentName || sAgentName === "") {
                    return {
                        isValid: false,
                        error: "Allocation " + (i + 1) + ": Agent Name is missing. Please reselect the agent."
                    };
                }

                // Check if Loading Date is filled
                if (!oAllocation.LOADING_DATE || String(oAllocation.LOADING_DATE).trim() === "") {
                    return {
                        isValid: false,
                        error: "Allocation " + (i + 1) + ": Loading Date is required"
                    };
                }

                // Validate Loading Date format (should be YYYY-MM-DD)
                var oLoadingDate = new Date(oAllocation.LOADING_DATE);
                if (isNaN(oLoadingDate.getTime())) {
                    return {
                        isValid: false,
                        error: "Allocation " + (i + 1) + ": Loading Date is invalid"
                    };
                }

                // Check if Loading Date is not in the past
                var oToday = new Date();
                oToday.setHours(0, 0, 0, 0);  // Set to midnight for fair comparison
                
                if (oLoadingDate < oToday) {
                    return {
                        isValid: false,
                        error: "Allocation " + (i + 1) + ": Loading Date cannot be a past date"
                    };
                }

                // Check if Transporter/Carrier is selected
                var sTransporter = String(oAllocation.TRANSPORTER || "").trim();
                if (!sTransporter || sTransporter === "") {
                    return {
                        isValid: false,
                        error: "Allocation " + (i + 1) + ": Carrier is required"
                    };
                }

                // Check if TRANS_NAME is populated (should be set when transporter is selected)
                var sTransName = String(oAllocation.TRANS_NAME || "").trim();
                if (!sTransName || sTransName === "") {
                    return {
                        isValid: false,
                        error: "Allocation " + (i + 1) + ": Carrier Name is missing. Please reselect the carrier."
                    };
                }

                // Check if at least one item has quantity allocated
                var bHasAllocatedQty = false;
                var iTotalAllocatedInAlloc = 0;

                console.log("Checking items for allocation " + (i + 1) + ". Items count:", oAllocation.items ? oAllocation.items.length : 0);

                if (oAllocation.items && oAllocation.items.length > 0) {
                    for (var j = 0; j < oAllocation.items.length; j++) {
                        var oAllocItem = oAllocation.items[j];
                        var fQty = parseFloat(oAllocItem.agentQuantity) || 0;
                        console.log("Item " + j + " (POSNR: " + oAllocItem.POSNR + "): agentQuantity = " + oAllocItem.agentQuantity + ", parsed = " + fQty);
                        
                        if (fQty > 0) {
                            bHasAllocatedQty = true;
                            iTotalAllocatedInAlloc += fQty;
                        }

                        // Check if quantity is valid (positive number)
                        if (oAllocItem.agentQuantity && isNaN(fQty)) {
                            return {
                                isValid: false,
                                error: "Allocation " + (i + 1) + ", Item " + oAllocItem.POSNR + ": Allocation quantity must be a valid number"
                            };
                        }

                        // Check if quantity is negative
                        if (fQty < 0) {
                            return {
                                isValid: false,
                                error: "Allocation " + (i + 1) + ", Item " + oAllocItem.POSNR + ": Allocation quantity cannot be negative"
                            };
                        }
                    }
                }

                console.log("Allocation " + (i + 1) + " has allocated quantities:", bHasAllocatedQty);

                // Check if at least one item has quantity for this allocation
                if (!bHasAllocatedQty) {
                    return {
                        isValid: false,
                        error: "Allocation " + (i + 1) + ": At least one item must have an allocation quantity"
                    };
                }
            }

            // Check each item to ensure allocated quantity doesn't exceed order quantity
            for (var i = 0; i < aItems.length; i++) {
                var oItem = aItems[i];
                var iOrderQty = parseFloat(oItem.KWMENG) || 0;
                var iTotalAllocated = parseFloat(oItem.totalAllocatedQty) || 0;

                if (iTotalAllocated > iOrderQty) {
                    return {
                        isValid: false,
                        error: "Material " + oItem.MATNR + ": Total allocated quantity (" + iTotalAllocated + 
                               ") exceeds order quantity (" + iOrderQty + ")"
                    };
                }
            }

            return {
                isValid: true,
                error: null
            };
        },

        onCreateOrder: function () {
            var oView = this.getView();
            var oViewModel = oView.getModel("manageModel");
            var oModel = oView.getModel();

            var aItems = oViewModel.getProperty("/items") || [];
            if (!aItems.length) {
                MessageToast.show("No order items found to create the order");
                return;
            }
            
            // Validate agent allocations quantities
            var oAllocValidation = this._validateAgentAllocations();
            if (!oAllocValidation.isValid) {
                MessageBox.error("Agent Allocation Validation Error: " + oAllocValidation.error, {
                    title: "Quantity Limit Exceeded"
                });
                return;
            }
            
            // Validate 3rd party agent selection for CL shipping
            var sShippingMethod = oViewModel.getProperty("/header/VSBED");
            var sThirdPartyAgent = oViewModel.getProperty("/thirdPartyAgent");
            
            if (sShippingMethod === "CL" && (!sThirdPartyAgent || sThirdPartyAgent === "")) {
                MessageBox.error("Please select 3rd Party Agent option. This is mandatory for Collected (CL) shipping method.", {
                    title: "Validation Error",
                    onClose: function() {
                        var oCombo = this.byId("thirdPartyAgentCombo");
                        if (oCombo) {
                            oCombo.setValueState("Error");
                            oCombo.setValueStateText("3rd Party Agent selection is required for CL shipping");
                            oCombo.focus();
                        }
                    }.bind(this)
                });
                return;
            }
            
            // Clear any previous validation state
            var oCombo = this.byId("thirdPartyAgentCombo");
            if (oCombo) {
                oCombo.setValueState("None");
            }
            
            oViewModel.setProperty("/busy", true);
            
            // Create deep entity: CustomerOrder with nested items
            var oDeepEntity = this._buildDeepEntity();
            console.log("Creating order with payload:", JSON.stringify(oDeepEntity, null, 2));
            
            oModel.create("/CustomerOrderSet", oDeepEntity, {
                success: function (oData) {
                    console.log("Order created successfully:", oData);
                    // Update UI with backend response (header + items)
                    oViewModel.setProperty("/header", Object.assign({}, oViewModel.getProperty("/header"), oData));
                    oViewModel.setProperty("/orderNo", oData.ORDER_NO);
                    if (oData.CustOrderHeadertoItem && oData.CustOrderHeadertoItem.results) {
                        var aReturnedItems = oData.CustOrderHeadertoItem.results;
                        var aExistingItems = oViewModel.getProperty("/items") || [];
                        var aMergedItems = aReturnedItems.map(function (oItem) {
                            var oExisting = aExistingItems.find(function (oOld) {
                                return oOld.POSNR === oItem.POSNR;
                            }) || {};
                            return Object.assign({}, oExisting, oItem);
                        });
                        oViewModel.setProperty("/items", aMergedItems);
                    }
                    oViewModel.setProperty("/orderCreated", true);
                    oViewModel.setProperty("/busy", false);
                    this._showSuccessDialog(oData);
                }.bind(this),
                error: function (oError) {
                    oViewModel.setProperty("/busy", false);
                    console.error("Order creation failed:", oError);
                    console.error("Error response:", oError.responseText);
                    
                    var sErrorMessage = "Failed to create order";
                    var sDetailedError = "";
                    try {
                        var oErrorResponse = JSON.parse(oError.responseText);
                        sErrorMessage = oErrorResponse.error.message.value || sErrorMessage;
                        
                        // Try to get more details from errordetails array
                        if (oErrorResponse.error.innererror && oErrorResponse.error.innererror.errordetails) {
                            var aDetails = oErrorResponse.error.innererror.errordetails;
                            if (aDetails.length > 0) {
                                sDetailedError = aDetails.map(function(d) { return d.message; }).join("; ");
                            }
                        }
                    } catch (e) {
                        sErrorMessage = oError.message || sErrorMessage;
                    }
                    
                    var sFullMessage = sErrorMessage + (sDetailedError ? "\n\nDetails: " + sDetailedError : "");
                    MessageBox.error(sFullMessage, {
                        title: "Order Creation Failed"
                    });
                }.bind(this)
            });
        },

        _buildDeepEntity: function () {
            var oViewModel = this.getView().getModel("manageModel");
            var oHeader = oViewModel.getProperty("/header");
            var aItems = oViewModel.getProperty("/items");
            var sOrderNo = oViewModel.getProperty("/orderNo") || "";
            var sThirdPartyAgent = oViewModel.getProperty("/thirdPartyAgent");
            var fnVal = function (v) {
                return v === undefined || v === null ? "" : v;
            };
            var sNavProp = "CustOrderHeadertoItem";
            var fnNormalizeThirdParty = function (v) {
                if (v === "1") {
                    return "YES";
                }
                if (v === "0") {
                    return "NO";
                }
                return v;
            };
            var sThirdParty = fnNormalizeThirdParty(sThirdPartyAgent);
            
            // Build deep entity with only metadata fields
            var oDeepEntity = {
                ORDER_NO: fnVal(oHeader.ORDER_NO || sOrderNo),
                KUNNR: fnVal(oHeader.KUNNR),
                KUNNR_DESC: fnVal(oHeader.BSTNK),
                SALESORDER: fnVal(oHeader.VBELN || oHeader.SALESORDER),
                SHIP_COND: fnVal(oHeader.VSBED || oHeader.SHIP_COND),
                NETWR: fnVal(oHeader.NETWR),
                WAERK: fnVal(oHeader.WAERK),
                BSTNK: fnVal(oHeader.BSTNK),
                BSTDK: fnVal(oHeader.BSTDK),
                THIRDPARTY: sThirdParty === "YES" ? "1" : "0"
            };

            oDeepEntity[sNavProp] = {
                results: aItems.map(function (oItem) {
                    var sQty = fnVal(oItem.KWMENG || oItem.QUANTITY);
                    return {
                        ORDER_NO: fnVal(oItem.ORDER_NO || oHeader.ORDER_NO || sOrderNo),
                        POSNR: fnVal(oItem.POSNR),
                        MATNR: fnVal(oItem.MATNR),
                        ARKTX: fnVal(oItem.ARKTX),
                        KWMENG: sQty,
                        VRKME: fnVal(oItem.VRKME),
                        NETPR: fnVal(oItem.NETPR),
                        WAERK: fnVal(oItem.WAERK),
                        WERKS: fnVal(oItem.WERKS),
                        USEDQTY: fnVal(oItem.USEDQTY) || "0"
                    };
                })
            };
            
            return oDeepEntity;
        },

        _createAgentAllocation: function (sOrderNo) {
            var oView = this.getView();
            var oViewModel = oView.getModel("manageModel");
            var oModel = oView.getModel();
            var aAllocations = oViewModel.getProperty("/agentAllocations") || [];
            var oHeader = oViewModel.getProperty("/header");

            if (!aAllocations.length) {
                MessageToast.show("Add at least one agent allocation.");
                return;
            }

            oViewModel.setProperty("/busy", true);

            var fnVal = function (v, fallback) {
                return v === undefined || v === null || v === "" ? fallback : v;
            };

            var aPayloads = aAllocations.map(function (oAllocation, iIndex) {
                var aItemResults = (oAllocation.items || []).map(function (oItem) {
                    var fQty = parseFloat(oItem.agentQuantity);
                    return {
                        ORDER_NO: sOrderNo,
                        ALLOCATION_ID: String(iIndex + 1),
                        AGENT_ID: oAllocation.AGENT_ID,
                        MATERIAL: oItem.MATNR,
                        QUANTITY: isNaN(fQty) ? "" : String(fQty),
                        UOM: oItem.VRKME,
                        DELIVERY_LOC: oItem.DELIVERY_LOC
                    };
                });

                return {
                    ORDER_NO: sOrderNo,
                    ALLOCATION_ID: String(iIndex + 1),
                    AGENT_ID: oAllocation.AGENT_ID,
                    AGENT_NAME: oAllocation.AGENT_NAME,
                    KUNNR: oHeader.KUNNR,
                    KUNNR_DESC: fnVal(oHeader.BSTNK, ""),
                    LOADING_DATE: oAllocation.LOADING_DATE,
                    TRANSPORTER: oAllocation.TRANSPORTER,
                    TRANS_NAME: oAllocation.TRANS_NAME,
                    TRANSPORTGSTN: oAllocation.TRANSPORTGSTN,
                    AgentOrderHeadertoItem: {
                        results: aItemResults
                    }
                };
            });

            var iPending = aPayloads.length;
            var bHadError = false;
            var sLastError = "";

            aPayloads.forEach(function (oPayload) {
                oModel.create("/AgentOrderAllocationSet", oPayload, {
                    success: function () {
                        iPending -= 1;
                        if (iPending === 0) {
                            oViewModel.setProperty("/busy", false);
                            if (bHadError) {
                                MessageToast.show(sLastError || "Some agent allocations failed to save.");
                            } else {
                                MessageToast.show("Agent allocations created successfully");
                            }
                        }
                    }.bind(this),
                    error: function (oError) {
                        bHadError = true;
                        iPending -= 1;
                        try {
                            var oErrorResponse = JSON.parse(oError.responseText);
                            sLastError = oErrorResponse.error.message.value || sLastError;
                        } catch (e) {
                            sLastError = oError.message || sLastError;
                        }

                        if (iPending === 0) {
                            oViewModel.setProperty("/busy", false);
                            MessageToast.show(sLastError || "Some agent allocations failed to save.");
                        }
                    }.bind(this)
                });
            }, this);
        },

        _showSuccessDialog: function (oOrderData) {
            var oViewModel = this.getView().getModel("manageModel");
            var fnVal = function (v, fallback) {
                return v === undefined || v === null || v === "" ? fallback : v;
            };

            var sOrderNo = fnVal(oOrderData.ORDER_NO, oViewModel.getProperty("/orderNo"));
            var sCustomer = fnVal(oOrderData.KUNNR, oViewModel.getProperty("/header/KUNNR"));
            var sCustomerRef = fnVal(oOrderData.BSTNK, oViewModel.getProperty("/header/BSTNK"));
            var sRefDate = fnVal(oOrderData.BSTDK, oViewModel.getProperty("/header/BSTDK"));
            var sSalesOrder = fnVal(oOrderData.SALESORDER, oViewModel.getProperty("/header/VBELN"));
            var sNet = fnVal(oOrderData.NETWR, oViewModel.getProperty("/header/NETWR"));
            var sCurr = fnVal(oOrderData.WAERK, oViewModel.getProperty("/header/WAERK"));
            var sNetValue = sNet && sCurr ? sNet + " " + sCurr : fnVal(sNet, "-");
            var aItems = oViewModel.getProperty("/items") || [];
            var sActionClose = "Close";

            var oContent = new VBox({
                width: "100%",
                items: [
                    new Text({ text: "Order created successfully." }).addStyleClass("order-success-title"),
                    new Text({ text: "Order No: " + fnVal(sOrderNo, "-") }).addStyleClass("order-success-meta"),
                    new Text({ text: "Sales Order: " + fnVal(sSalesOrder, "-") }).addStyleClass("order-success-meta"),
                    new Text({ text: "Customer Code: " + fnVal(sCustomer, "-") }).addStyleClass("order-success-meta"),
                    new Text({ text: "Customer Ref: " + fnVal(sCustomerRef, "-") }).addStyleClass("order-success-meta"),
                    new Text({ text: "Reference Date: " + fnVal(sRefDate, "-") }).addStyleClass("order-success-meta"),
                    new Text({ text: "Net Value: " + sNetValue }).addStyleClass("order-success-meta"),
                    new Text({ text: "Items: " + aItems.length }).addStyleClass("order-success-meta")
                ]
            });

            MessageBox.show(oContent, {
                icon: MessageBox.Icon.SUCCESS,
                title: "Order Created",
                actions: [sActionClose],
                emphasizedAction: sActionClose,
                styleClass: "order-success-dialog",
                onClose: function (sAction) {
                    MessageToast.show("Order number " + sOrderNo + " is ready for processing.");
                }.bind(this)
            });
        },

        onNavBack: function () {
            var oHistory = History.getInstance();
            var sPreviousHash = oHistory.getPreviousHash();

            if (sPreviousHash !== undefined) {
                window.history.back();
                return;
            }

            this.getOwnerComponent().getRouter().navTo("RouteCustomerIndent", {}, true);
        }
    });
});
