class ZCL_ZSD_CUST_BULK_INDE_DPC_EXT definition
  public
  inheriting from ZCL_ZSD_CUST_BULK_INDE_DPC
  create public .

public section.

  methods /IWBEP/IF_MGW_APPL_SRV_RUNTIME~CREATE_DEEP_ENTITY
    redefinition .
protected section.

  methods AGENTDETAILSSET_CREATE_ENTITY
    redefinition .
  methods AGENTDETAILSSET_DELETE_ENTITY
    redefinition .
  methods AGENTDETAILSSET_GET_ENTITY
    redefinition .
  methods AGENTDETAILSSET_GET_ENTITYSET
    redefinition .
  methods AGENTORDERALLO01_DELETE_ENTITY
    redefinition .
  methods AGENTORDERALLO01_GET_ENTITYSET
    redefinition .
  methods AGENTORDERALLOCA_DELETE_ENTITY
    redefinition .
  methods AGENTORDERALLOCA_GET_ENTITY
    redefinition .
  methods AGENTORDERALLOCA_GET_ENTITYSET
    redefinition .
  methods CUSTOMERORDERITE_DELETE_ENTITY
    redefinition .
  methods CUSTOMERORDERITE_GET_ENTITY
    redefinition .
  methods CUSTOMERORDERITE_GET_ENTITYSET
    redefinition .
  methods CUSTOMERORDERITE_UPDATE_ENTITY
    redefinition .
  methods CUSTOMERORDERSET_DELETE_ENTITY
    redefinition .
  methods CUSTOMERORDERSET_GET_ENTITY
    redefinition .
  methods CUSTOMERORDERSET_GET_ENTITYSET
    redefinition .
  methods CONTRACTHEADER_GET_ENTITY
    redefinition .
  methods CONTRACTHEADER_GET_ENTITYSET
    redefinition .
  methods CONTRACTITEMSE_GET_ENTITY
    redefinition .
  methods CONTRACTITEMSE_GET_ENTITYSET
    redefinition .
  methods TRANSPORTERDETAI_GET_ENTITYSET
    redefinition .
private section.

  " Remaining contract balance available to a customer for one material.
  " Discovers the governing contract(s) from (customer + material) - these
  " sales docs are VBTYP 'C' orders, so there is no direct contract link.
  " Commitments are counted from the bulk tables only (the Without-Vehicle
  " tab is retired).
  methods GET_AVAILABLE_FOR_MATERIAL
    importing
      !IV_SHIPTO type KUNNR
      !IV_MATNR  type MATNR
      !IV_DEPOT  type WERKS_D
    returning
      value(RV_AVAIL) type VBAP-ZMENG .

  " Remaining balance of ONE specific contract for one material, matching the
  " open qty shown on the contract card (CONTRACTITEMSE_GET_ENTITYSET) 1:1.
  " Used by the create/save enforcement so screen and save agree by construction.
  methods GET_AVAILABLE_FOR_CONTRACT
    importing
      !IV_VBELN type VBELN_VA
      !IV_MATNR type MATNR
    returning
      value(RV_AVAIL) type VBAP-ZMENG .

  " Effective quantity ONE open indent commits against the contract for one
  " material. For a 3rd-party indent the customer only lifts what has been
  " allocated to agents, so the commitment is the SUM of agent allocations
  " (zsd_agnt_ordritm-QUANTITY) for this order + material. A self-lift indent
  " (No/N/A third party) has no agent rows, so it falls back to the full item
  " line (zsd_cstmr_orditm-KWMENG). Returned in the SAME unit as IV_LINE_QTY -
  " agent QUANTITY and item KWMENG are both stored on the item's own scale, so
  " every caller applies its existing KG/MT bridge unchanged.
  methods GET_COMMITTED_QTY
    importing
      !IV_ORDER_NO type ZSD_CSTMR_ORDITM-ORDER_NO
      !IV_MATNR    type MATNR
      !IV_LINE_QTY type ZSD_CSTMR_ORDITM-KWMENG
    returning
      value(RV_QTY) type ZSD_CSTMR_ORDITM-KWMENG .

  " Quantity of a bulk order + material that has ALREADY been shipped out. Reads
  " the Automate-TT staging tables (ZSAUTOMATETT_TBL volume / ZSAUTOMATETT_LPG
  " weight), summing the QUAN columns for rows that carry a shipment number
  " (SHNUMBER <> space; SHNUMBER is a shipment no., NOT a sales-order VBELN).
  " Subtracted from the open bulk commitment so the shipped portion is not double-
  " counted against the contract-side VBFA releases. See the body for the reversal
  " caveat inherent to the data model.
  methods GET_RELEASED_QTY
    importing
      !IV_ORDER_NO type ZSD_CSTMR_ORDITM-ORDER_NO
      !IV_MATNR    type MATNR
    returning
      value(RV_QTY) type ZSD_CSTMR_ORDITM-KWMENG .
ENDCLASS.



CLASS ZCL_ZSD_CUST_BULK_INDE_DPC_EXT IMPLEMENTATION.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->TRANSPORTERDETAI_GET_ENTITYSET
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_FILTER_SELECT_OPTIONS       TYPE        /IWBEP/T_MGW_SELECT_OPTION
* | [--->] IS_PAGING                      TYPE        /IWBEP/S_MGW_PAGING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [--->] IT_ORDER                       TYPE        /IWBEP/T_MGW_SORTING_ORDER
* | [--->] IV_FILTER_STRING               TYPE        STRING
* | [--->] IV_SEARCH_STRING               TYPE        STRING
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITYSET(optional)
* | [<---] ET_ENTITYSET                   TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TT_TRANSPORTERDETAILS
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_CONTEXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method TRANSPORTERDETAI_GET_ENTITYSET.
    DATA:
            lt_filter_so  TYPE /iwbep/t_mgw_select_option,
            ls_filter_so  TYPE /iwbep/s_mgw_select_option,
            lo_filter     TYPE REF TO /iwbep/if_mgw_req_filter,
            lt_range_id   TYPE RANGE OF oigsv-cre_date.


    DATA:
          lt_transporters TYPE TABLE OF zcl_zsd_custind_withou_mpc_ext=>ts_transporterdetails,
          ls_transporter  TYPE zcl_zsd_custind_withou_mpc_ext=>ts_transporterdetails,
          lt_lfa1         TYPE TABLE OF lfa1,
          lt_adrc         TYPE TABLE OF adrc,
          lt_adr6         TYPE TABLE OF adr6.

    TYPES: BEGIN OF ty_carrier,
               carrier TYPE oigsv-carrier,
             END OF ty_carrier.

    DATA: lt_carriers TYPE TABLE OF ty_carrier.



    lo_filter = io_tech_request_context->get_filter( ).
    lt_filter_so = lo_filter->get_filter_select_options( ).

    " Example: filter on agent ID
    READ TABLE lt_filter_so INTO ls_filter_so WITH KEY property = 'CRE_DATE'.
    IF sy-subrc = 0.
      lt_range_id = VALUE #( FOR ls_opt IN ls_filter_so-select_options
                             ( sign   = ls_opt-sign
                               option = ls_opt-option
                               low    = ls_opt-low
                               high   = ls_opt-high ) ).
    ENDIF.


*     Step 2: Get distinct carrier codes from OIGSV, filtered by plantcode (werks) and fromdate (erdat >= fromdate)
    select distinct carrier
      from oigsv
      into table lt_carriers
      where cre_date in lt_range_id
        and carrier <> ''.

    delete adjacent duplicates from lt_carriers.

*     Step 3: Fetch vendor details from LFA1
    if lt_carriers is not initial.
      select *
        from lfa1
        into table @lt_lfa1
        for all entries in @lt_carriers
        where lifnr = @lt_carriers-carrier.
    endif.

*     Step 4: Fetch address details from ADRC
    IF lt_lfa1 IS NOT INITIAL.
      SELECT *
        FROM adrc
        INTO TABLE @lt_adrc
        FOR ALL ENTRIES IN @lt_lfa1
        WHERE addrnumber = @lt_lfa1-adrnr.

*Fetch email from ADR6 (SMTP addresses)
      select *
        from adr6
        into table @lt_adr6
        for all entries in @lt_lfa1
        where addrnumber = @lt_lfa1-adrnr.
    endif.

*     Step 5: Build the transporters list
    loop at lt_lfa1 assigning field-symbol(<fs_lfa1>).
      clear ls_transporter.

      ls_transporter-carrier = <fs_lfa1>-lifnr.
      ls_transporter-gstn  = <fs_lfa1>-stcd3.
      ls_transporter-name = <fs_lfa1>-name1.
      ls_transporter-phone = <fs_lfa1>-telf1.

*     Get address from ADRC
      read table lt_adrc into data(ls_adrc) with key addrnumber = <fs_lfa1>-adrnr.
      if sy-subrc = 0.
        ls_transporter-addr = |{ ls_adrc-street } { ls_adrc-house_num1 }, { ls_adrc-city1 }, { ls_adrc-post_code1 }, { ls_adrc-country }|.
      endif.

*     Get email from ADR6 (take the first one if multiple)
      read table lt_adr6 into data(ls_adr6) with key addrnumber = <fs_lfa1>-adrnr.
      if sy-subrc = 0.
        ls_transporter-email = ls_adr6-smtp_addr.
      endif.

      append ls_transporter to lt_transporters.
    endloop.

*     Step 5.1: Remove any potential duplicates (sort and delete adjacent)
    sort lt_transporters by carrier.
    delete adjacent duplicates from lt_transporters comparing carrier.

    move lt_transporters to et_entityset.
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->GET_AVAILABLE_FOR_MATERIAL
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_SHIPTO                      TYPE        KUNNR
* | [--->] IV_MATNR                       TYPE        MATNR
* | [--->] IV_DEPOT                       TYPE        WERKS_D
* | [<-()] RV_AVAIL                       TYPE        VBAP-ZMENG
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method GET_AVAILABLE_FOR_MATERIAL.
    " Remaining contract balance available to a customer for one material,
    " aggregated across every currently-valid contract (the bulk portal has
    " no per-contract picker, unlike the retired Without-Vehicle tab):
    "
    "   available = SUM over valid contracts ( VBAP-ZMENG - delivered VBFA )
    "             - open commitments already booked via the bulk portal
    "
    " Returns -1 when the customer has NO valid contract for the material
    " (distinct from a genuine zero balance).
    "
    " UOM: the result is returned in the contract's native UOM. No MT/KG
    " bridge is applied - the contract balance and the open commitments
    " (zsd_cstmr_orditm-KWMENG) are used and subtracted as stored.
    "
    " Contracts are matched on the ship-to partner (PARVW = 'WE'), replicating
    " the Without-Vehicle tab. IV_SHIPTO is the sales order's own WE partner,
    " resolved by the caller from VBPA (see the CustomerOrderSet create branch).
    DATA: lv_deliv  TYPE vbfa-rfmng_flo,
          lv_native TYPE vbap-zmeng,
          lv_commit TYPE vbap-zmeng.

    " candidate contracts (Without-Vehicle SELECT_CONTRACT_NVEH parity:
    " valid today / ship-to = customer / exact material / OWN-BOND valuation /
    " user's depot / real item category / not rejected)
    SELECT v~vbeln, a~posnr, a~zmeng, a~zieme
      FROM vbak AS v
      INNER JOIN vbpa AS p ON p~vbeln = v~vbeln
      INNER JOIN vbap AS a ON a~vbeln = v~vbeln
      INTO TABLE @DATA(lt_con)
      WHERE v~guebg <= @sy-datum AND v~gueen >= @sy-datum
        AND v~auart = 'ZCQ'
        AND p~kunnr = @iv_shipto AND p~parvw = 'WE'
        AND a~matnr = @iv_matnr
        AND a~bwtar = 'OWN-BOND'
        AND a~werks = @iv_depot
        AND a~pstyv <> 'ZTAE'
        AND a~abgru = @space.                                       "#EC CI_BUFFJOIN

    IF lt_con IS INITIAL.
      rv_avail = -1.            " no valid contract for this customer + material
      RETURN.
    ENDIF.

    " ordered - delivered, summed over the contract lines (contract native UOM)
    LOOP AT lt_con INTO DATA(ls_con).
      CLEAR lv_deliv.
      SELECT SUM( rfmng_flo ) FROM vbfa INTO @lv_deliv
        WHERE vbelv = @ls_con-vbeln AND vbtyp_n = 'C' AND posnv = @ls_con-posnr.
      lv_native = lv_native + ( ls_con-zmeng - lv_deliv ).
    ENDLOOP.

    " contract balance in its native UOM (no MT/KG bridge applied).
    rv_avail = lv_native.

    " open commitments already booked via the BULK portal for this
    " ship-to + material. zsd_cstmr_orditm carries no contract column,
    " so the commitment is counted at the (ship-to, material) grain - the same
    " grain the contract discovery above uses. Only OPEN indents count: once
    " the external processor sets STATUS = 'C', the indent stops consuming
    " balance (blank status = legacy/open, still counts - safe default).
    SELECT i~order_no, i~kwmeng
      FROM zsd_cstmr_orditm AS i
      INNER JOIN zsd_customer_ord AS h ON h~order_no = i~order_no
      INTO TABLE @DATA(lt_pc)
      WHERE h~shipto = @iv_shipto
        AND i~matnr  = @iv_matnr
        AND h~status <> 'C'.

    " collapse to one row per order for this material: get_committed_qty and
    " get_released_qty already aggregate at the (order, material) grain, so
    " calling them once per item line would count an order that carries the same
    " material on more than one line twice. COLLECT sums KWMENG per order.
    TYPES: BEGIN OF ty_ord,
             order_no TYPE zsd_cstmr_orditm-order_no,
             kwmeng   TYPE zsd_cstmr_orditm-kwmeng,
           END OF ty_ord.
    DATA lt_ord TYPE STANDARD TABLE OF ty_ord.
    DATA ls_ord TYPE ty_ord.

    CLEAR lt_ord.
    LOOP AT lt_pc INTO DATA(ls_pc).
      ls_ord-order_no = ls_pc-order_no.
      ls_ord-kwmeng   = ls_pc-kwmeng.
      COLLECT ls_ord INTO lt_ord.
    ENDLOOP.

    CLEAR lv_commit.
    LOOP AT lt_ord INTO ls_ord.
      " agent-allocated qty for 3rd-party indents, full item line otherwise,
      " MINUS what has already become a sales order. The released part is already
      " netted out via the VBFA 'C' releases above, so leaving it in the
      " commitment would double-subtract it.
      DATA(lv_line) = get_committed_qty( iv_order_no = ls_ord-order_no
                                         iv_matnr    = iv_matnr
                                         iv_line_qty = ls_ord-kwmeng ).
      lv_line = lv_line - get_released_qty( iv_order_no = ls_ord-order_no
                                            iv_matnr    = iv_matnr ).
      IF lv_line > 0.
        lv_commit = lv_commit + lv_line.
      ENDIF.
    ENDLOOP.

    rv_avail = rv_avail - lv_commit.
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->CUSTOMERORDERSET_GET_ENTITYSET
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_FILTER_SELECT_OPTIONS       TYPE        /IWBEP/T_MGW_SELECT_OPTION
* | [--->] IS_PAGING                      TYPE        /IWBEP/S_MGW_PAGING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [--->] IT_ORDER                       TYPE        /IWBEP/T_MGW_SORTING_ORDER
* | [--->] IV_FILTER_STRING               TYPE        STRING
* | [--->] IV_SEARCH_STRING               TYPE        STRING
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITYSET(optional)
* | [<---] ET_ENTITYSET                   TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TT_CUSTOMERORDER
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_CONTEXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method CUSTOMERORDERSET_GET_ENTITYSET.
    DATA: lt_header       TYPE TABLE OF zcl_zsd_custind_withou_mpc=>ts_customerorder,
        lr_order_no     TYPE RANGE OF zsd_customer_ord-order_no,
        lr_CONTRACT   TYPE RANGE OF zsd_customer_ord-CONTRACT,
        lv_top          TYPE i,
        lv_skip         TYPE i,
        lv_orderby      TYPE string.               " ← we will build the ORDER BY clause here

    " Paging
    lv_top  = io_tech_request_context->get_top( ).
    lv_skip = io_tech_request_context->get_skip( ).

    IF lv_top IS INITIAL.
      lv_top = 500.   " ← adjust or remove this fallback depending on your requirements
    ENDIF.

    " Filters – convert select options to ranges
    READ TABLE it_filter_select_options INTO DATA(ls_filter) WITH KEY property = 'ORDER_NO'.
    IF sy-subrc = 0.
      lr_order_no = VALUE #( FOR opt IN ls_filter-select_options
                               ( sign   = opt-sign
                                 option = opt-option
                                 low    = opt-low
                                 high   = opt-high ) ).
    ENDIF.

    READ TABLE it_filter_select_options INTO ls_filter WITH KEY property = 'CONTRACT'.
    IF sy-subrc = 0.
      lr_CONTRACT = VALUE #( FOR opt IN ls_filter-select_options
                                 ( sign   = opt-sign
                                   option = opt-option
                                   low    = opt-low
                                   high   = opt-high ) ).
    ENDIF.

    " ────────────────────────────────────────────────
    " Build dynamic ORDER BY clause from $orderby
    " ────────────────────────────────────────────────
    DATA(lt_orderby) = io_tech_request_context->get_orderby( ).

    LOOP AT lt_orderby INTO DATA(ls_order).
      IF lv_orderby IS NOT INITIAL.
        lv_orderby = lv_orderby && `, `.
      ENDIF.

      lv_orderby = lv_orderby && ls_order-property.

      " Note: in most systems the value is lowercase 'asc' / 'desc'
      CASE ls_order-order.
        WHEN 'desc' OR 'DESC'.
          lv_orderby = lv_orderby && ` DESC`.
        WHEN OTHERS.
          lv_orderby = lv_orderby && ` ASC`.   " default
      ENDCASE.
    ENDLOOP.

    " Very important: fallback sort when client sends no $orderby
    IF lv_orderby IS INITIAL.
      lv_orderby = 'ORDER_NO'.          " or 'ORDER_NO DESC' or 'PRIMARY KEY' etc.
    ENDIF.

    " Read all request headers then find the one we need
     DATA(lt_headers) = io_tech_request_context->get_request_headers( ).

     DATA(lv_portal_user) = VALUE string( ).
     READ TABLE lt_headers INTO DATA(ls_header1)
         WITH KEY name = 'x-portal-user'.
     IF sy-subrc = 0.
         lv_portal_user = ls_header1-value.
     ENDIF.

     IF lv_portal_user IS INITIAL.
         lv_portal_user = sy-uname.  " fallback
     ENDIF.


    select single *
        from zsd_cust_usr_map into @data(ls_customer) where cust_user_id eq @lv_portal_user.

    " ────────────────────────────────────────────────
    " Main SELECT with dynamic ORDER BY
    " ────────────────────────────────────────────────
    SELECT *
      FROM zsd_customer_ord
      WHERE kunnr eq @ls_customer-kunnr
        AND order_no   IN @lr_order_no
        AND CONTRACT IN @lr_CONTRACT
      ORDER BY (lv_orderby)               " ← string variable → correct syntax
      INTO CORRESPONDING FIELDS OF TABLE @lt_header
      UP TO @lv_top ROWS OFFSET @lv_skip.

    " Inline count
    IF io_tech_request_context->has_inlinecount( ) = abap_true
    OR io_tech_request_context->has_count( ) = abap_true.
      SELECT COUNT(*)
        FROM zsd_customer_ord
        INTO @data(lv_count)
        WHERE kunnr eq @ls_customer-kunnr
          AND order_no   IN @lr_order_no
          AND CONTRACT IN @lr_CONTRACT.

      es_response_context-inlinecount = lv_count.
    ENDIF.

    move-corresponding lt_header to et_entityset.
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->CUSTOMERORDERSET_GET_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IO_REQUEST_OBJECT              TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY(optional)
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [<---] ER_ENTITY                      TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TS_CUSTOMERORDER
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_ENTITY_CNTXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method CUSTOMERORDERSET_GET_ENTITY.
    DATA: ls_keys     TYPE /iwbep/s_mgw_name_value_pair,
            lv_order_no TYPE zsd_customer_ord-order_no,
            ls_header   TYPE ZCL_ZSD_CUSTIND_WITHOU_MPC=>ts_customerorder.

      " Read key(s) – assuming ORDER_NO is the main/only key
      READ TABLE it_key_tab INTO ls_keys WITH KEY name = 'ORDER_NO'.
      IF sy-subrc = 0.
        lv_order_no = ls_keys-value.
      ENDIF.

      IF lv_order_no IS INITIAL.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            message = 'Order number is mandatory'.
      ENDIF.

      " Read all request headers then find the one we need
      DATA(lt_headers) = io_tech_request_context->get_request_headers( ).

      DATA(lv_portal_user) = VALUE string( ).
      READ TABLE lt_headers INTO DATA(ls_header1)
          WITH KEY name = 'x-portal-user'.
      IF sy-subrc = 0.
          lv_portal_user = ls_header1-value.
      ENDIF.

      IF lv_portal_user IS INITIAL.
          lv_portal_user = sy-uname.  " fallback
      ENDIF.

      select single *
        from zsd_cust_usr_map into @data(ls_customer) where cust_user_id eq @lv_portal_user.

      select single
          *
      from zsd_customer_ord
      into corresponding fields of @ls_header
      where order_no = @lv_order_no and kunnr eq @ls_customer-kunnr.

      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            message = 'Customer Order not found'.
      ENDIF.

     move-corresponding ls_header to er_entity.
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->CUSTOMERORDERSET_DELETE_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY_D(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method CUSTOMERORDERSET_DELETE_ENTITY.

  DATA:
      lv_order_no TYPE zsd_customer_ord-order_no,
      ls_key      TYPE /iwbep/s_mgw_name_value_pair.

  DATA: ls_cust_ord TYPE zsd_customer_ord.

  " 1. Read the key (ORDER_NO) from the request URI
  READ TABLE it_key_tab INTO ls_key WITH KEY name = 'ORDER_NO'.
  IF sy-subrc <> 0.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        message_unlimited = 'Order number (ORDER_NO) is mandatory for delete'.
  ENDIF.

  lv_order_no = ls_key-value.

  " Resolve the portal user -> owning customer so a delete is scoped to the
  " caller's own indents (the ORDER_NO key alone is guessable).
  DATA(lt_headers) = io_tech_request_context->get_request_headers( ).
  DATA(lv_portal_user) = VALUE string( ).
  READ TABLE lt_headers INTO DATA(ls_header1) WITH KEY name = 'x-portal-user'.
  IF sy-subrc = 0.
    lv_portal_user = ls_header1-value.
  ENDIF.
  IF lv_portal_user IS INITIAL.
    lv_portal_user = sy-uname.  " fallback
  ENDIF.

  SELECT SINGLE * FROM zsd_cust_usr_map
    INTO @DATA(ls_customer) WHERE cust_user_id eq @lv_portal_user.

  " 2. Existence check + ownership: the order must belong to THIS customer
  SELECT SINGLE *
    FROM zsd_customer_ord
    INTO @ls_cust_ord
    WHERE order_no = @lv_order_no
      AND kunnr    = @ls_customer-kunnr.

  IF sy-subrc <> 0.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        message_unlimited = |Customer Order { lv_order_no } does not exist|.
  ENDIF.

  " 3. Delete all dependent items (cascading delete)
  DELETE FROM zsd_cstmr_orditm
    WHERE order_no = @lv_order_no.

  " Optional: check if delete failed (rare, but good practice)
  IF sy-subrc <> 0 AND sy-dbcnt > 0.
    " Log or handle partial failure if needed
  ENDIF.


  " 4. Delete the header
  DELETE FROM zsd_customer_ord
    WHERE order_no = @lv_order_no.

  IF sy-subrc <> 0.
    ROLLBACK WORK.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        message_unlimited = |Failed to delete Customer Order { lv_order_no }|.
  ENDIF.

  " 5. Commit the transaction
  COMMIT WORK.

  " No need to set er_entity – DELETE returns 204 No Content on success
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->CUSTOMERORDERITE_UPDATE_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY_U(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [--->] IO_DATA_PROVIDER               TYPE REF TO /IWBEP/IF_MGW_ENTRY_PROVIDER(optional)
* | [<---] ER_ENTITY                      TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TS_CUSTOMERORDERITEM
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
method CUSTOMERORDERITE_UPDATE_ENTITY.
  data: ls_keys           type /iwbep/s_mgw_name_value_pair,
    lv_order_no       type char10,               " ← adjust to your actual type (e.g. vbeln or custom)
    lv_posnr          type posnr_va,             " usually char6 / numc10
    ls_entity         type zcl_zsd_custind_withou_mpc_ext=>ts_customerorderitem,  " mpc entity type
    ls_db             type ZSD_CSTMR_ORDITM,                     " e.g. zsd_custind_withoutvehnew or your structure
    ls_modify         type ZSD_CSTMR_ORDITM.                     " work area for modify


  " -------------------------------------------------------------------------
  " 1. Extract keys from request
  " -------------------------------------------------------------------------
  READ TABLE it_key_tab INTO ls_keys WITH KEY name = 'ORDER_NO'.
  IF sy-subrc = 0.
    lv_order_no = ls_keys-value.
  ELSE.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING message_unlimited = 'Key field ORDER_NO missing'.
  ENDIF.

  READ TABLE it_key_tab INTO ls_keys WITH KEY name = 'POSNR'.
  IF sy-subrc = 0.
    lv_posnr = ls_keys-value.
  ELSE.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING message_unlimited = 'Key field POSNR missing'.
  ENDIF.

  " -------------------------------------------------------------------------
  " 1b. Ownership: resolve portal user -> customer and confirm the parent
  "     order belongs to the caller before touching the item (the item table
  "     carries no customer column, so scope via the header's KUNNR).
  " -------------------------------------------------------------------------
  DATA(lt_headers) = io_tech_request_context->get_request_headers( ).
  DATA(lv_portal_user) = VALUE string( ).
  READ TABLE lt_headers INTO DATA(ls_header1) WITH KEY name = 'x-portal-user'.
  IF sy-subrc = 0.
    lv_portal_user = ls_header1-value.
  ENDIF.
  IF lv_portal_user IS INITIAL.
    lv_portal_user = sy-uname.  " fallback
  ENDIF.

  SELECT SINGLE * FROM zsd_cust_usr_map
    INTO @DATA(ls_customer) WHERE cust_user_id eq @lv_portal_user.

  SELECT SINGLE kunnr FROM zsd_customer_ord
    INTO @DATA(lv_owner)
    WHERE order_no = @lv_order_no.
  IF sy-subrc <> 0 OR lv_owner <> ls_customer-kunnr.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING message_unlimited = 'Customer Order Item not found'.
  ENDIF.

  " -------------------------------------------------------------------------
  " 2. Read incoming payload (delta / fields to change)
  " -------------------------------------------------------------------------
  io_data_provider->read_entry_data( IMPORTING es_data = ls_entity ).

  " -------------------------------------------------------------------------
  " 3. Read current DB record (to validate existence + start merge)
  "    Replace <your_table_or_cds> with real table / CDS view name
  " -------------------------------------------------------------------------
  SELECT SINGLE *
    FROM ZSD_CSTMR_ORDITM               " ← your actual persistence (table / CDS)
    INTO @ls_db
   WHERE order_no = @lv_order_no
     AND posnr    = @lv_posnr.

  IF sy-subrc <> 0.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING message_unlimited = 'Customer Order Item not found'.
  ENDIF.

  " -------------------------------------------------------------------------
  " 4. Prepare work area for MODIFY → merge existing + incoming changes
  " -------------------------------------------------------------------------
  MOVE-CORRESPONDING ls_db TO ls_modify.   " start with full current record

  " Overwrite only fields provided in payload (simple non-initial check)
  " Adjust conditions if you want to allow explicit initial/zero values
  IF ls_entity-matnr IS NOT INITIAL.
    ls_modify-matnr = ls_entity-matnr.
  ENDIF.

  IF ls_entity-arktx IS NOT INITIAL.
    ls_modify-arktx = ls_entity-arktx.
  ENDIF.

  IF ls_entity-kwmeng IS NOT INITIAL OR ls_entity-kwmeng = 0.
    ls_modify-kwmeng = ls_entity-kwmeng.
  ENDIF.

  IF ls_entity-vrkme IS NOT INITIAL.
    ls_modify-vrkme = ls_entity-vrkme.
  ENDIF.

  IF ls_entity-netpr IS NOT INITIAL OR ls_entity-netpr = 0.
    ls_modify-netpr = ls_entity-netpr.
  ENDIF.

  IF ls_entity-waerk IS NOT INITIAL.
    ls_modify-waerk = ls_entity-waerk.
  ENDIF.

  IF ls_entity-werks IS NOT INITIAL.
    ls_modify-werks = ls_entity-werks.
  ENDIF.

  IF ls_entity-usedqty IS NOT INITIAL OR ls_entity-usedqty = 0.
    ls_modify-usedqty = ls_entity-usedqty.   " ← main field you probably want to change
  ENDIF.

  " ... add other changeable fields the same way (skip key fields!)

  " Important: Ensure keys are set in work area (MODIFY uses them to find row)
  ls_modify-order_no = lv_order_no.
  ls_modify-posnr    = lv_posnr.

  " -------------------------------------------------------------------------
  " 5. Perform the modification (insert or update based on key)
  "    Since we checked existence → it will always update here
  " -------------------------------------------------------------------------
  MODIFY ZSD_CSTMR_ORDITM FROM @ls_modify.

  IF sy-subrc <> 0.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING message_unlimited = 'Modify failed - database error'.
  ENDIF.

  COMMIT WORK AND WAIT.   " ← use if no automatic commit (e.g. no BAPI wrapper)

  " -------------------------------------------------------------------------
  " 6. Return updated entity
  " -------------------------------------------------------------------------
  MOVE-CORRESPONDING ls_modify TO ls_entity.   " map back to OData entity type
  er_entity = ls_entity.
endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->CUSTOMERORDERITE_GET_ENTITYSET
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_FILTER_SELECT_OPTIONS       TYPE        /IWBEP/T_MGW_SELECT_OPTION
* | [--->] IS_PAGING                      TYPE        /IWBEP/S_MGW_PAGING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [--->] IT_ORDER                       TYPE        /IWBEP/T_MGW_SORTING_ORDER
* | [--->] IV_FILTER_STRING               TYPE        STRING
* | [--->] IV_SEARCH_STRING               TYPE        STRING
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITYSET(optional)
* | [<---] ET_ENTITYSET                   TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TT_CUSTOMERORDERITEM
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_CONTEXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method CUSTOMERORDERITE_GET_ENTITYSET.
   DATA: lt_items      TYPE TABLE OF zcl_zsd_custind_withou_mpc=>ts_customerorderitem,
        lv_order_no   TYPE zsd_cstmr_orditm-order_no,
        lt_filter_opt TYPE /iwbep/t_mgw_select_option,
        lr_order_no   TYPE RANGE OF zsd_cstmr_orditm-order_no,
        lr_posnr      TYPE RANGE OF zsd_cstmr_orditm-posnr,
        lv_top        TYPE i,
        lv_skip       TYPE i.


  " Paging
  lv_top  = io_tech_request_context->get_top( ).
  lv_skip = io_tech_request_context->get_skip( ).
  IF lv_top IS INITIAL. lv_top = 500. ENDIF.

  " Get parent key when called via navigation
  READ TABLE it_key_tab INTO DATA(ls_key) WITH KEY name = 'ORDER_NO'.
  IF sy-subrc = 0.
    lv_order_no = ls_key-value.
  ENDIF.

  " Or via $filter (direct access)
  READ TABLE it_filter_select_options INTO DATA(ls_filter) WITH KEY property = 'ORDER_NO'.
  IF sy-subrc = 0.
    lr_order_no = VALUE #( FOR opt IN ls_filter-select_options
                             ( sign = opt-sign option = opt-option low = opt-low high = opt-high ) ).
  ENDIF.

  " Combine navigation key + filter
  IF lv_order_no IS NOT INITIAL.
    lr_order_no = VALUE #( ( sign = 'I' option = 'EQ' low = lv_order_no ) ).
  ENDIF.

  READ TABLE it_filter_select_options INTO ls_filter WITH KEY property = 'POSNR'.
  IF sy-subrc = 0.
    lr_posnr = VALUE #( FOR opt IN ls_filter-select_options
                          ( sign = opt-sign option = opt-option low = opt-low high = opt-high ) ).
  ENDIF.

  " Resolve the portal user -> owning customer so only the caller's own order
  " items are returned. The item table carries no customer column, so scope
  " via the parent header's KUNNR (inner join to zsd_customer_ord).
  DATA(lt_headers) = io_tech_request_context->get_request_headers( ).
  DATA(lv_portal_user) = VALUE string( ).
  READ TABLE lt_headers INTO DATA(ls_header1) WITH KEY name = 'x-portal-user'.
  IF sy-subrc = 0.
    lv_portal_user = ls_header1-value.
  ENDIF.
  IF lv_portal_user IS INITIAL.
    lv_portal_user = sy-uname.  " fallback
  ENDIF.

  SELECT SINGLE * FROM zsd_cust_usr_map
    INTO @DATA(ls_customer) WHERE cust_user_id eq @lv_portal_user.

  " Fetch items (scoped to the caller's own orders via the header KUNNR)
  SELECT
    i~order_no,
    i~posnr,
    i~matnr,
    i~arktx,
    i~kwmeng,
    i~vrkme,
    i~netpr,
    i~waerk,
    i~werks,
    i~usedqty
  FROM zsd_cstmr_orditm AS i
  INNER JOIN zsd_customer_ord AS h ON h~order_no = i~order_no
  WHERE i~order_no IN @lr_order_no
    AND i~posnr    IN @lr_posnr
    AND h~kunnr     = @ls_customer-kunnr
  ORDER BY i~order_no, i~posnr
  INTO CORRESPONDING FIELDS OF TABLE @lt_items
  UP TO @lv_top ROWS OFFSET @lv_skip.

  " Inline count (optional)
  IF io_tech_request_context->has_inlinecount( ) = abap_true.
    SELECT COUNT(*)
      FROM zsd_cstmr_orditm AS i
      INNER JOIN zsd_customer_ord AS h ON h~order_no = i~order_no
      INTO @data(lv_count)
      WHERE i~order_no IN @lr_order_no
        AND i~posnr    IN @lr_posnr
        AND h~kunnr     = @ls_customer-kunnr.

      es_response_context-inlinecount = lv_count.
  ENDIF.

  move-corresponding lt_items to et_entityset.

  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->CUSTOMERORDERITE_GET_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IO_REQUEST_OBJECT              TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY(optional)
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [<---] ER_ENTITY                      TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TS_CUSTOMERORDERITEM
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_ENTITY_CNTXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method CUSTOMERORDERITE_GET_ENTITY.
      DATA: ls_key            TYPE /iwbep/s_mgw_name_value_pair,
        lv_order_no       TYPE vbeln_va,          " ← adjust to real type (often char10 or your domain)
        lv_posnr          TYPE posnr_va,          " usually posnr_va / numc6 / char6
        ls_entity         TYPE zcl_zsd_custind_withou_mpc_ext=>ts_customerorderitem,  " ← use your MPC generated type
        ls_db             TYPE ZSD_CSTMR_ORDITM.   " ← replace with real structure type (e.g. zsd_custind_withoutvehnew or your CDS line type)


      " -------------------------------------------------------------------------
      " 1. Extract keys from the request (mandatory for GET_ENTITY)
      "    Usually ORDER_NO + POSNR are the keys
      " -------------------------------------------------------------------------
      READ TABLE it_key_tab INTO ls_key WITH KEY name = 'ORDER_NO'.
      IF sy-subrc = 0.
        lv_order_no = ls_key-value.
      ELSE.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            message_unlimited = 'Key field ORDER_NO is missing'.
      ENDIF.

      READ TABLE it_key_tab INTO ls_key WITH KEY name = 'POSNR'.
      IF sy-subrc = 0.
        lv_posnr = ls_key-value.
      ELSE.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            message_unlimited = 'Key field POSNR is missing'.
      ENDIF.

      " -------------------------------------------------------------------------
      " 1b. Ownership: resolve portal user -> customer, confirm the parent order
      "     belongs to the caller before returning the item.
      " -------------------------------------------------------------------------
      DATA(lt_headers) = io_tech_request_context->get_request_headers( ).
      DATA(lv_portal_user) = VALUE string( ).
      READ TABLE lt_headers INTO DATA(ls_header1) WITH KEY name = 'x-portal-user'.
      IF sy-subrc = 0.
        lv_portal_user = ls_header1-value.
      ENDIF.
      IF lv_portal_user IS INITIAL.
        lv_portal_user = sy-uname.  " fallback
      ENDIF.

      SELECT SINGLE * FROM zsd_cust_usr_map
        INTO @DATA(ls_customer) WHERE cust_user_id eq @lv_portal_user.

      SELECT SINGLE kunnr FROM zsd_customer_ord
        INTO @DATA(lv_owner)
        WHERE order_no = @lv_order_no.
      IF sy-subrc <> 0 OR lv_owner <> ls_customer-kunnr.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            message_unlimited = 'Customer Order Item not found'
            http_status_code  = 404.
      ENDIF.

      " -------------------------------------------------------------------------
      " 2. Read single record from database / CDS / BAPI / ...
      "    Replace your_table_or_cds with actual table or view name
      " -------------------------------------------------------------------------
      SELECT SINGLE
             order_no,
             posnr,
             matnr,
             arktx,
             kwmeng,
             vrkme,
             netpr,
             waerk,
             werks,
             usedqty
        FROM ZSD_CSTMR_ORDITM              " ← e.g. zsd_custind_withoutvehnew or your CDS entity
        INTO CORRESPONDING FIELDS OF @ls_db
       WHERE order_no = @lv_order_no
         AND posnr    = @lv_posnr.

      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING
            message_unlimited = 'Customer Order Item not found'
            http_status_code       = 404.   " optional - nicer HTTP response
      ENDIF.

      " -------------------------------------------------------------------------
      " 3. Map DB fields → OData entity fields
      "    (use MOVE-CORRESPONDING if names match perfectly)
      " -------------------------------------------------------------------------
      MOVE-CORRESPONDING ls_db TO ls_entity.

      " Manual mapping if names differ or special conversion needed
      ls_entity-order_no   = ls_db-order_no.
      ls_entity-posnr      = ls_db-posnr.
      ls_entity-matnr      = ls_db-matnr.
      ls_entity-arktx      = ls_db-arktx.
      ls_entity-kwmeng     = ls_db-kwmeng.
      ls_entity-vrkme      = ls_db-vrkme.
      ls_entity-netpr      = ls_db-netpr.
      ls_entity-waerk      = ls_db-waerk.
      ls_entity-werks      = ls_db-werks.
      ls_entity-usedqty    = ls_db-usedqty.   " ← probably the most interesting field

      " -------------------------------------------------------------------------
      " 4. Return the entity
      " -------------------------------------------------------------------------
      er_entity = ls_entity.

      " Optional: set response context if needed (e.g. etag for concurrency)
      " es_response_context-etag = ...
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->CUSTOMERORDERITE_DELETE_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY_D(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method CUSTOMERORDERITE_DELETE_ENTITY.
    DATA: lv_order_no TYPE zsd_cstmr_orditm-order_no,
            lv_posnr    TYPE zsd_cstmr_orditm-posnr,
            ls_key      TYPE /iwbep/s_mgw_name_value_pair.


      READ TABLE it_key_tab INTO ls_key WITH KEY name = 'ORDER_NO'.
      IF sy-subrc = 0. lv_order_no = ls_key-value. ENDIF.

      READ TABLE it_key_tab INTO ls_key WITH KEY name = 'POSNR'.
      IF sy-subrc = 0. lv_posnr = ls_key-value. ENDIF.

      IF lv_order_no IS INITIAL OR lv_posnr IS INITIAL.
        RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
          EXPORTING message = 'Both ORDER_NO and POSNR required'.
      ENDIF.

      DELETE FROM zsd_cstmr_orditm
        WHERE order_no = @lv_order_no
          AND posnr    = @lv_posnr.

      COMMIT WORK.
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->AGENTORDERALLOCA_GET_ENTITYSET
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_FILTER_SELECT_OPTIONS       TYPE        /IWBEP/T_MGW_SELECT_OPTION
* | [--->] IS_PAGING                      TYPE        /IWBEP/S_MGW_PAGING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [--->] IT_ORDER                       TYPE        /IWBEP/T_MGW_SORTING_ORDER
* | [--->] IV_FILTER_STRING               TYPE        STRING
* | [--->] IV_SEARCH_STRING               TYPE        STRING
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITYSET(optional)
* | [<---] ET_ENTITYSET                   TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TT_AGENTORDERALLOCATIONHEADER
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_CONTEXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method AGENTORDERALLOCA_GET_ENTITYSET.
    DATA: lt_header       TYPE TABLE OF ZCL_ZSD_CUSTIND_WITHOU_MPC_EXT=>ts_agentorderallocationheader,
        lt_filter_opt   TYPE /iwbep/t_mgw_select_option,
        lr_agent_id     TYPE RANGE OF zsd_agent_order-agent_id,
        lr_order_no     TYPE RANGE OF zsd_agent_order-order_no,
        lr_loading_date TYPE RANGE OF zsd_agent_order-loading_date,
        lv_top          TYPE i,
        lv_skip         TYPE i,
        lv_max          TYPE i.
  " ────────────────────────────────────────
  " Paging ($top / $skip)
  " ────────────────────────────────────────
  lv_top  = io_tech_request_context->get_top( ).
  lv_skip = io_tech_request_context->get_skip( ).

  IF lv_top IS INITIAL.
    lv_top = 10000.    " ← fallback / max records – adjust to your needs or system setting
  ENDIF.

  " ────────────────────────────────────────
  " Filter – use IT_FILTER_SELECT_OPTIONS (recommended)
  " ────────────────────────────────────────
  READ TABLE it_filter_select_options INTO DATA(ls_filter) WITH KEY property = 'AGENT_ID'.


  IF sy-subrc = 0.
    LOOP AT ls_filter-select_options INTO DATA(ls_opt).
      APPEND VALUE #( sign   = ls_opt-sign
                      option = ls_opt-option
                      low    = ls_opt-low
                      high   = ls_opt-high ) TO lr_agent_id.
    ENDLOOP.
  ENDIF.


 READ TABLE it_filter_select_options INTO ls_filter WITH KEY property = 'ORDER_NO'.

 clear ls_opt.
 IF sy-subrc = 0.
    LOOP AT ls_filter-select_options INTO ls_opt.
      APPEND VALUE #( sign   = ls_opt-sign
                      option = ls_opt-option
                      low    = ls_opt-low
                      high   = ls_opt-high ) TO lr_order_no.
    ENDLOOP.
  ENDIF.

 READ TABLE it_filter_select_options INTO ls_filter WITH KEY property = 'LOADING_DATE'.

 clear ls_opt.
 IF sy-subrc = 0.
    LOOP AT ls_filter-select_options INTO ls_opt.
      APPEND VALUE #( sign   = ls_opt-sign
                      option = ls_opt-option
                      low    = ls_opt-low
                      high   = ls_opt-high ) TO lr_loading_date.
    ENDLOOP.
  ENDIF.

  " Add more properties as needed ↑

  " ────────────────────────────────────────
  " Main SELECT (with filters + paging via UP TO / OFFSET)
  " ────────────────────────────────────────
  SELECT
        *
    FROM zsd_agent_order


    WHERE agent_id     IN @lr_agent_id
      AND order_no     IN @lr_order_no
      AND loading_date IN @lr_loading_date

    ORDER BY PRIMARY KEY

    INTO CORRESPONDING FIELDS OF TABLE @lt_header
    UP TO @lv_top ROWS OFFSET @lv_skip
            " or dynamic ORDER BY if you parse it_orderby
    .

  " ────────────────────────────────────────
  " $inlinecount support ($count or $inlinecount=allpages)
  " ────────────────────────────────────────
  IF io_tech_request_context->has_inlinecount( ) = abap_true
  OR io_tech_request_context->has_count( ) = abap_true.   " both variants exist depending on SP
    SELECT COUNT(*)
      FROM zsd_agent_order
      INTO @DATA(lv_count)
      WHERE agent_id     IN @lr_agent_id
        AND order_no     IN @lr_order_no
        AND loading_date IN @lr_loading_date.

    es_response_context-inlinecount = lv_count.
  ENDIF.

  " ────────────────────────────────────────
  " Output
  " ────────────────────────────────────────

  move-corresponding lt_header to et_entityset.

ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->AGENTORDERALLOCA_GET_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IO_REQUEST_OBJECT              TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY(optional)
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [<---] ER_ENTITY                      TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TS_AGENTORDERALLOCATIONHEADER
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_ENTITY_CNTXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method AGENTORDERALLOCA_GET_ENTITY.
        DATA: ls_key_tab    TYPE /iwbep/s_mgw_name_value_pair,
              lv_alloc_id   TYPE zsd_agent_order-allocation_id,
              ls_header     TYPE ZCL_ZSD_CUSTIND_WITHOU_mpc_ext=>ts_agentorderallocationheader.


        READ TABLE it_key_tab INTO ls_key_tab WITH KEY name = 'ALLOCATION_ID'.
        IF sy-subrc = 0.
          lv_alloc_id = ls_key_tab-value.
        ENDIF.

        " B) Optional: also support ORDER_NO + AGENT_ID combination if needed
        IF lv_alloc_id IS INITIAL.
          READ TABLE it_key_tab INTO ls_key_tab WITH KEY name = 'ORDER_NO'.
          IF sy-subrc = 0.
            DATA(lv_order_no) = CONV zsd_agent_order-order_no( ls_key_tab-value ).
          ENDIF.

          READ TABLE it_key_tab INTO ls_key_tab WITH KEY name = 'AGENT_ID'.
          IF sy-subrc = 0.
            DATA(lv_agent_id) = CONV zsd_agent_order-agent_id( ls_key_tab-value ).
          ENDIF.
        ENDIF.

        " C) Select single header
        IF lv_alloc_id IS NOT INITIAL.

          SELECT SINGLE
              *
          FROM zsd_agent_order
          INTO CORRESPONDING FIELDS OF @ls_header
          WHERE allocation_id = @lv_alloc_id.

        ELSEIF lv_order_no IS NOT INITIAL AND lv_agent_id IS NOT INITIAL.

          SELECT SINGLE
            *
          FROM zsd_agent_order
          INTO CORRESPONDING FIELDS OF @ls_header
          WHERE order_no  = @lv_order_no
            AND agent_id  = @lv_agent_id.

        ENDIF.

        IF sy-subrc <> 0.
          RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
            EXPORTING
              textid = /iwbep/cx_mgw_busi_exception=>business_error
              message = 'Allocation not found'.
        ENDIF.

        move-corresponding ls_header to er_entity.
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->AGENTORDERALLOCA_DELETE_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY_D(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method AGENTORDERALLOCA_DELETE_ENTITY.
DATA:
    lv_allocation_id TYPE zsd_agent_order-allocation_id,
    lv_agent_id      TYPE zsd_agent_order-agent_id,
    lv_order_no      TYPE zsd_agent_order-order_no,
    ls_key           TYPE /iwbep/s_mgw_name_value_pair,
    lv_found         TYPE abap_bool.


  " 1. Read the composite key from URI
  CLEAR: lv_allocation_id, lv_agent_id, lv_order_no.

  READ TABLE it_key_tab INTO ls_key WITH KEY name = 'ALLOCATION_ID'.
  IF sy-subrc = 0.
    lv_allocation_id = ls_key-value.
  ENDIF.

  READ TABLE it_key_tab INTO ls_key WITH KEY name = 'AGENT_ID'.
  IF sy-subrc = 0.
    lv_agent_id = ls_key-value.
  ENDIF.

  READ TABLE it_key_tab INTO ls_key WITH KEY name = 'ORDER_NO'.
  IF sy-subrc = 0.
    lv_order_no = ls_key-value.
  ENDIF.

  IF lv_allocation_id IS INITIAL OR lv_agent_id IS INITIAL OR lv_order_no IS INITIAL.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        message_unlimited = 'All three keys (ALLOCATION_ID, AGENT_ID, ORDER_NO) are required for delete'.
  ENDIF.

  " 2. Check existence (important for composite key)
  SELECT SINGLE @abap_true
    FROM zsd_agent_order
    INTO @lv_found
   WHERE allocation_id = @lv_allocation_id
     AND agent_id      = @lv_agent_id
     AND order_no      = @lv_order_no.

  IF sy-subrc <> 0 OR lv_found = abap_false.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        message_unlimited = |Allocation { lv_allocation_id } / Agent { lv_agent_id } / Order { lv_order_no } not found|.
  ENDIF.

  " 3. Optional business validations
  " Example: prevent delete if already loaded/transported
  " SELECT SINGLE ... FROM some_status_table ...
  "   WHERE allocation_id = @lv_allocation_id AND status = 'LOADED'
  "   INTO @DATA(lv_protected).
  " IF lv_protected = abap_true.
  "   RAISE EXCEPTION ... 'Cannot delete already processed allocation'.
  " ENDIF.

  " 4. Delete all dependent items first (cascading)
  DELETE FROM zsd_agnt_ordritm
    WHERE allocation_id = @lv_allocation_id
      AND agent_id      = @lv_agent_id
      AND order_no      = @lv_order_no.

  " No need to check sy-subrc strictly – if no items existed, it's still ok

  " 5. Delete the header
  DELETE FROM zsd_agent_order
    WHERE allocation_id = @lv_allocation_id
      AND agent_id      = @lv_agent_id
      AND order_no      = @lv_order_no.

  IF sy-subrc <> 0.
    ROLLBACK WORK.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        message_unlimited = |Failed to delete Agent Allocation { lv_allocation_id }|.
  ENDIF.

  COMMIT WORK.

  " DELETE returns 204 No Content – no response body needed
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->AGENTORDERALLO01_GET_ENTITYSET
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_FILTER_SELECT_OPTIONS       TYPE        /IWBEP/T_MGW_SELECT_OPTION
* | [--->] IS_PAGING                      TYPE        /IWBEP/S_MGW_PAGING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [--->] IT_ORDER                       TYPE        /IWBEP/T_MGW_SORTING_ORDER
* | [--->] IV_FILTER_STRING               TYPE        STRING
* | [--->] IV_SEARCH_STRING               TYPE        STRING
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITYSET(optional)
* | [<---] ET_ENTITYSET                   TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TT_AGENTORDERALLOCATIONITM
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_CONTEXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
METHOD agentorderallo01_get_entityset.
  DATA: lt_allocation     type standard table of zcl_zsd_custind_withou_mpc_ext=>ts_agentorderallocationitm,
        lt_filter_opt   TYPE /iwbep/t_mgw_select_option,
        lr_order_no     TYPE RANGE OF zsd_agent_order-order_no,
        lr_alloc_no     TYPE RANGE OF zsd_agent_order-allocation_id,
        lr_loading_date TYPE RANGE OF zsd_agent_order-loading_date,
        lv_top          TYPE i,
        lv_skip         TYPE i,
        lv_max          TYPE i.
  " ────────────────────────────────────────
  " Paging ($top / $skip)
  " ────────────────────────────────────────
  lv_top  = io_tech_request_context->get_top( ).
  lv_skip = io_tech_request_context->get_skip( ).

  IF lv_top IS INITIAL.
    lv_top = 10000.    " ← fallback / max records – adjust to your needs or system setting
  ENDIF.

  " ────────────────────────────────────────
  " Filter – use IT_FILTER_SELECT_OPTIONS (recommended)
  " ────────────────────────────────────────
  READ TABLE it_filter_select_options INTO DATA(ls_filter) WITH KEY property = 'ORDER_NO'.


  IF sy-subrc = 0.
    LOOP AT ls_filter-select_options INTO DATA(ls_opt).
      APPEND VALUE #( sign   = ls_opt-sign
                      option = ls_opt-option
                      low    = ls_opt-low
                      high   = ls_opt-high ) TO lr_order_no.
    ENDLOOP.
  ENDIF.


 READ TABLE it_filter_select_options INTO ls_filter WITH KEY property = 'ALLOCATION_ID'.

 clear ls_opt.
 IF sy-subrc = 0.
    LOOP AT ls_filter-select_options INTO ls_opt.
      APPEND VALUE #( sign   = ls_opt-sign
                      option = ls_opt-option
                      low    = ls_opt-low
                      high   = ls_opt-high ) TO lr_alloc_no.
    ENDLOOP.
  ENDIF.


  " Add more properties as needed ↑

  " ────────────────────────────────────────
  " Main SELECT (with filters + paging via UP TO / OFFSET)
  " ────────────────────────────────────────
  SELECT order_no,
         allocation_id,
         agent_id,
         material,
         quantity,
         uom
    FROM ZSD_AGNT_ORDRITM   " ← CHANGE THIS TO YOUR ACTUAL TABLE / CDS !!!
    INTO CORRESPONDING FIELDS OF TABLE @lt_allocation
    WHERE order_no in @lr_order_no
      AND allocation_id in @lr_alloc_no.


  " ────────────────────────────────────────
  " $inlinecount support ($count or $inlinecount=allpages)
  " ────────────────────────────────────────
  IF io_tech_request_context->has_inlinecount( ) = abap_true
           OR io_tech_request_context->has_count( ) = abap_true.   " both variants exist depending on SP
             SELECT COUNT(*)
               FROM ZSD_AGNT_ORDRITM
               INTO @DATA(lv_count)
               WHERE order_no     IN @lr_order_no
                 AND allocation_id in @lr_alloc_no.

             es_response_context-inlinecount = lv_count.
  ENDIF.

  " ────────────────────────────────────────
  " Output
  " ────────────────────────────────────────

  move-corresponding lt_allocation to et_entityset.

ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->AGENTORDERALLO01_DELETE_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY_D(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method AGENTORDERALLO01_DELETE_ENTITY.
    DATA:
    lv_allocation_id TYPE zsd_agnt_ordritm-allocation_id,
    lv_order_no      TYPE zsd_agnt_ordritm-order_no,
    lv_agent_id      TYPE zsd_agnt_ordritm-agent_id,
    ls_key           TYPE /iwbep/s_mgw_name_value_pair.


  " Read keys (depending on your item key definition)
  READ TABLE it_key_tab INTO ls_key WITH KEY name = 'ALLOCATION_ID'.
  IF sy-subrc = 0. lv_allocation_id = ls_key-value. ENDIF.

  READ TABLE it_key_tab INTO ls_key WITH KEY name = 'ORDER_NO'.
  IF sy-subrc = 0. lv_order_no = ls_key-value. ENDIF.

  READ TABLE it_key_tab INTO ls_key WITH KEY name = 'AGENT_ID'.
  IF sy-subrc = 0. lv_agent_id = ls_key-value. ENDIF.

  " If your item key is different (e.g. only ALLOCATION_ID + something else),
  " adjust the keys accordingly

  IF lv_allocation_id IS INITIAL.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING message = 'ALLOCATION_ID is required'.
  ENDIF.

  " Delete single item (or all items for this allocation if no further key)
  DELETE FROM zsd_agnt_ordritm
    WHERE allocation_id = @lv_allocation_id
      AND agent_id      = @lv_agent_id
      AND order_no      = @lv_order_no.

  IF sy-subrc <> 0.
    " Could be "not found" → decide if you want to raise exception or silent success
  ENDIF.

  COMMIT WORK.
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->AGENTDETAILSSET_GET_ENTITYSET
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_FILTER_SELECT_OPTIONS       TYPE        /IWBEP/T_MGW_SELECT_OPTION
* | [--->] IS_PAGING                      TYPE        /IWBEP/S_MGW_PAGING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [--->] IT_ORDER                       TYPE        /IWBEP/T_MGW_SORTING_ORDER
* | [--->] IV_FILTER_STRING               TYPE        STRING
* | [--->] IV_SEARCH_STRING               TYPE        STRING
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITYSET(optional)
* | [<---] ET_ENTITYSET                   TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TT_AGENTDETAILS
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_CONTEXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method AGENTDETAILSSET_GET_ENTITYSET.
DATA:   lt_agents     TYPE TABLE OF zcl_zsd_custind_withou_mpc=>ts_agentdetails,
        lt_range_id   TYPE RANGE OF zsd_agent_detail-agent_id,
        lt_filter_so  TYPE /iwbep/t_mgw_select_option,
        ls_filter_so  TYPE /iwbep/s_mgw_select_option,
        lo_filter     TYPE REF TO /iwbep/if_mgw_req_filter.

  lo_filter = io_tech_request_context->get_filter( ).
  lt_filter_so = lo_filter->get_filter_select_options( ).

  " Example: filter on agent ID
  READ TABLE lt_filter_so INTO ls_filter_so WITH KEY property = 'AGENT_ID'.
  IF sy-subrc = 0.
    lt_range_id = VALUE #( FOR ls_opt IN ls_filter_so-select_options
                           ( sign   = ls_opt-sign
                             option = ls_opt-option
                             low    = ls_opt-low
                             high   = ls_opt-high ) ).
  ENDIF.

  if lt_range_id is initial.
    SELECT mandt,
           agent_id,
           agent_name,
           agent_mail,
           agent_ph,
           agent_addr,
           created_by,
           created_on,
           kunnr
      FROM zsd_agent_detail
      INTO CORRESPONDING FIELDS OF TABLE @lt_agents.
  else.
    SELECT mandt,
           agent_id,
           agent_name,
           agent_mail,
           agent_ph,
           agent_addr,
           created_by,
           created_on,
           kunnr
      FROM zsd_agent_detail
      INTO CORRESPONDING FIELDS OF TABLE @lt_agents
      WHERE agent_id IN @lt_range_id.
  endif.
  " If no data found → return empty set (preferred over raising exception)
  et_entityset = lt_agents.
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->AGENTDETAILSSET_GET_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IO_REQUEST_OBJECT              TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY(optional)
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [<---] ER_ENTITY                      TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TS_AGENTDETAILS
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_ENTITY_CNTXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method AGENTDETAILSSET_GET_ENTITY.
DATA: ls_key        TYPE /iwbep/s_mgw_name_value_pair,
      lv_agent_id   TYPE zsd_agent_detail-agent_id,
      ls_agent      TYPE zcl_zsd_custind_withou_mpc=>ts_agentdetails.


  READ TABLE it_key_tab INTO ls_key WITH KEY name = 'AGENT_ID'.
  IF sy-subrc = 0.
    lv_agent_id = ls_key-value.
  ELSE.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        http_status_code = '400'
        message     = 'Missing key field AGENT_ID'.
  ENDIF.

  SELECT SINGLE mandt,
                agent_id,
                agent_name,
                agent_mail,
                agent_ph,
                agent_addr,
                created_by,
                created_on,
                kunnr
    FROM zsd_agent_detail
    INTO CORRESPONDING FIELDS OF @ls_agent
    WHERE agent_id = @lv_agent_id.

  IF sy-subrc <> 0.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        http_status_code = '404'
        message     = |Agent { lv_agent_id } not found|.
  ENDIF.

  er_entity = ls_agent.
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->AGENTDETAILSSET_DELETE_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY_D(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
method AGENTDETAILSSET_DELETE_ENTITY.
  DATA: ls_key      TYPE /iwbep/s_mgw_name_value_pair,
        lv_agent_id TYPE zsd_agent_detail-agent_id,
        lv_kunnr    TYPE zsd_agent_detail-kunnr,
        lv_exists   TYPE abap_bool.

  " --- AGENT_ID ---
  READ TABLE it_key_tab INTO ls_key WITH KEY name = 'AGENT_ID'.
  IF sy-subrc <> 0.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        http_status_code = '400'
        message          = 'Missing key: AGENT_ID'.
  ENDIF.
  lv_agent_id = ls_key-value.

  " --- KUNNR ---
  READ TABLE it_key_tab INTO ls_key WITH KEY name = 'KUNNR'.
  IF sy-subrc <> 0.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        http_status_code = '400'
        message          = 'Missing key: KUNNR'.
  ENDIF.
  lv_kunnr = ls_key-value.

  " leading-zero conversion so unpadded OData values match padded DB keys
  CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
    EXPORTING input = lv_kunnr    IMPORTING output = lv_kunnr.
  CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
    EXPORTING input = lv_agent_id IMPORTING output = lv_agent_id.

  " --- existence check on BOTH keys ---
  SELECT SINGLE @abap_true
    FROM zsd_agent_detail
    INTO @lv_exists
    WHERE agent_id = @lv_agent_id
      AND kunnr    = @lv_kunnr.

  IF lv_exists <> abap_true.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        http_status_code = '404'
        message          = |Agent { lv_agent_id } not found|.
  ENDIF.

  " --- delete on BOTH keys ---
  DELETE FROM zsd_agent_detail
    WHERE agent_id = @lv_agent_id
      AND kunnr    = @lv_kunnr.

  IF sy-subrc <> 0.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        http_status_code = '500'
        message          = |Agent { lv_agent_id } / customer { lv_kunnr } not found|.

  ENDIF.
endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->AGENTDETAILSSET_CREATE_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY_C(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [--->] IO_DATA_PROVIDER               TYPE REF TO /IWBEP/IF_MGW_ENTRY_PROVIDER(optional)
* | [<---] ER_ENTITY                      TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TS_AGENTDETAILS
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
method AGENTDETAILSSET_CREATE_ENTITY.
DATA: ls_agent_in   TYPE zcl_zsd_custind_withou_mpc=>ts_agentdetails,
      ls_agent_db   TYPE zsd_agent_detail.   " ← your actual table type/structure

  " Read data from client request
  io_data_provider->read_entry_data( IMPORTING es_data = ls_agent_in ).

  " Mandatory check
  IF ls_agent_in-agent_id IS INITIAL.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING http_status_code = '400' message = 'Agent ID is mandatory'.
  ENDIF.

  " Duplicate check
  SELECT SINGLE @abap_true FROM zsd_agent_detail
    INTO @DATA(lv_exists)
    WHERE agent_id = @ls_agent_in-agent_id.

  IF lv_exists = abap_true.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING http_status_code = '409' message = |Agent { ls_agent_in-agent_id } already exists|.
  ENDIF.

  " Move data + fill system fields
  MOVE-CORRESPONDING ls_agent_in TO ls_agent_db.
  ls_agent_db-mandt      = sy-mandt.
  ls_agent_db-created_by = sy-uname.
  ls_agent_db-created_on = sy-datum.           " ← today's date: 20260203

  " *** This line actually saves the record to the database ***
  modify zsd_agent_detail FROM @ls_agent_db.

  IF sy-subrc <> 0.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING http_status_code = '500' message = 'Failed to create agent'.
  ENDIF.

  " Return the newly created record to the client
  MOVE-CORRESPONDING ls_agent_db TO er_entity.
endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Public Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->/IWBEP/IF_MGW_APPL_SRV_RUNTIME~CREATE_DEEP_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING(optional)
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING(optional)
* | [--->] IV_SOURCE_NAME                 TYPE        STRING(optional)
* | [--->] IO_DATA_PROVIDER               TYPE REF TO /IWBEP/IF_MGW_ENTRY_PROVIDER
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH(optional)
* | [--->] IO_EXPAND                      TYPE REF TO /IWBEP/IF_MGW_ODATA_EXPAND
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY_C(optional)
* | [<---] ER_DEEP_ENTITY                 TYPE REF TO DATA
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method /IWBEP/IF_MGW_APPL_SRV_RUNTIME~CREATE_DEEP_ENTITY.
    DATA lv_entity_set TYPE string.

  " 1. Get which entity set was targeted in the POST

  DATA: ls_agentalloc_deep     TYPE zcl_zsd_custind_withou_mpc_ext=>ts_deep_agentorderalloc,
        ls_custord_deep TYPE zcl_zsd_custind_withou_mpc_ext=>ts_deep_customerorder,
        lv_alloc_id TYPE zsd_agent_order-allocation_id,
        lv_order_no TYPE zsd_customer_ord-order_no,
        lv_is_update TYPE abap_bool.


  DATA:  lt_custitems_db TYPE TABLE OF ZSD_CSTMR_ORDITM,
         lt_agentitems_db TYPE TABLE OF zsd_agnt_ordritm.

  " Read deep payload (same as before)


  lv_entity_set = io_tech_request_context->get_entity_set_name( ).


   " Read all request headers then find the one we need
  DATA(lt_headers) = io_tech_request_context->get_request_headers( ).

  DATA(lv_portal_user) = VALUE string( ).
  READ TABLE lt_headers INTO DATA(ls_header1)
      WITH KEY name = 'x-portal-user'.
  IF sy-subrc = 0.
      lv_portal_user = ls_header1-value.
  ENDIF.

  IF lv_portal_user IS INITIAL.
      lv_portal_user = sy-uname.  " fallback
  ENDIF.



  CASE lv_entity_set.


      WHEN 'AgentOrderAllocationSet'.
            io_data_provider->read_entry_data( IMPORTING es_data = ls_agentalloc_deep ).

            lv_alloc_id = ls_agentalloc_deep-allocation_id.

            ls_agentalloc_deep-mandt = sy-mandt.
            ls_agentalloc_deep-created_by = lv_portal_user.
            ls_agentalloc_deep-created_on = sy-datum.

            " Decide create vs update
            IF lv_alloc_id IS INITIAL.
              " ────────────── CREATE ──────────────
              " Generate new key (your number range / GUID logic)
              CALL FUNCTION 'NUMBER_GET_NEXT'
                EXPORTING
                  nr_range_nr = '01'
                  object      = 'ZSD_ALLOC_'
                IMPORTING
                  number      = lv_alloc_id
                EXCEPTIONS
                  OTHERS      = 1.
              IF sy-subrc <> 0.
                RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                  EXPORTING message = 'Key generation failed'.
              ENDIF.

              ls_agentalloc_deep-allocation_id = lv_alloc_id.
              lv_is_update = abap_false.
            ELSE.
              " ────────────── UPDATE ──────────────
              " Check if header exists (optimistic lock / existence check)
              SELECT SINGLE allocation_id
                FROM zsd_agent_order
                INTO @DATA(lv_dummy)
                WHERE allocation_id = @lv_alloc_id.
              IF sy-subrc <> 0.
                RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                  EXPORTING message = 'Allocation not found - cannot update'.
              ENDIF.

              lv_is_update = abap_true.
            ENDIF.

            " ────────────── Header processing ──────────────
            DATA ls_agentheader_db TYPE zsd_agent_order.
            MOVE-CORRESPONDING ls_agentalloc_deep TO ls_agentheader_db.

            IF lv_is_update = abap_true.
              " Optional: Compare / merge logic, ETag check, etc.
              modify zsd_agent_order FROM ls_agentheader_db.
              IF sy-subrc <> 0.
                ROLLBACK WORK.
                RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                  EXPORTING message = 'Header update failed'.
              ENDIF.
            ELSE.
              INSERT zsd_agent_order FROM ls_agentheader_db.
              IF sy-subrc <> 0.
                ROLLBACK WORK.
                RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                  EXPORTING message = 'Header insert failed'.
              ENDIF.
            ENDIF.

            " ────────────── Items processing ──────────────
            " Strategy A: Replace all items (delete old → insert new)
            IF lv_is_update = abap_true.
              DELETE FROM zsd_agnt_ordritm WHERE allocation_id = @lv_alloc_id.
              " → You may want to log / audit instead of blind delete
            ENDIF.


            LOOP AT ls_agentalloc_deep-agentorderheadertoitem ASSIGNING FIELD-SYMBOL(<fs_item>).
              DATA ls_agentitem_db LIKE LINE OF lt_agentitems_db.
              MOVE-CORRESPONDING <fs_item> TO ls_agentitem_db.

              ls_agentitem_db-allocation_id = lv_alloc_id.
              ls_agentitem_db-mandt = sy-mandt.
              " Copy other linking fields if needed (agent_id, order_no, ...)

              " Validate item...
              APPEND ls_agentitem_db TO lt_agentitems_db.
            ENDLOOP.

            IF lt_agentitems_db IS NOT INITIAL.
              INSERT zsd_agnt_ordritm FROM TABLE lt_agentitems_db.
              IF sy-subrc <> 0.
                ROLLBACK WORK.
                RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                  EXPORTING message = 'Items insert failed'.
              ENDIF.
            ENDIF.

            COMMIT WORK AND WAIT.

            " Return the updated / created deep entity
            ls_agentalloc_deep-allocation_id = lv_alloc_id.   " make sure key is filled
            copy_data_to_ref(
              EXPORTING is_data = ls_agentalloc_deep
              CHANGING  cr_data = er_deep_entity ).
      WHEN 'CustomerOrderSet'.
            " ────────────────────────────────────────────────────────────────
            " Read deep payload for CustomerOrder
            " ────────────────────────────────────────────────────────────────
            io_data_provider->read_entry_data( IMPORTING es_data = ls_custord_deep ).
            lv_order_no = ls_custord_deep-order_no.
            " Decide create vs update/modify

            IF lv_order_no IS INITIAL.
            " CREATE - auto generate ORDER_NO in a different series (new number range object)
                      CALL FUNCTION 'NUMBER_GET_NEXT'
                            EXPORTING               " different series (e.g., '02' instead of '01' for agent)
                            nr_range_nr = '02'
                            object      = 'ZSDCUSTORD'       " dedicated number range object for customer orders (create in SNRO)
                            IMPORTING
                            number      = lv_order_no
                            EXCEPTIONS
                            OTHERS      = 1.

                      IF sy-subrc <> 0.
                             RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                             EXPORTING message = 'Failed to generate order number'.
                      ENDIF.
                      ls_custord_deep-mandt = sy-mandt.
                      ls_custord_deep-order_no = lv_order_no.
                      lv_is_update = abap_false.

            ELSE.
            " MODIFY/UPDATE - check existence
            SELECT SINGLE @abap_true
                    FROM zsd_customer_ord
                               WHERE order_no = @lv_order_no
                                                INTO @DATA(lv_exists).

            IF sy-subrc <> 0.
                   RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                   EXPORTING message = 'Order not found – cannot modify'.
            ENDIF.

            lv_is_update = abap_true.
            ENDIF.
            " ────────────────────────────────────────────────────────────────
            " 2. Map & validate header
            " ────────────────────────────────────────────────────────────────
            DATA ls_custheader_db TYPE zsd_customer_ord.
            ls_custord_deep-mandt = sy-mandt.
            MOVE-CORRESPONDING ls_custord_deep TO ls_custheader_db.
            " Optional validations (add your business rules)
            IF ls_custheader_db-kunnr IS INITIAL.
                RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                EXPORTING message = 'Customer number (KUNNR) is mandatory'.
            ENDIF.
            " Normalize KUNNR to its padded internal form so it matches the
            " padded keys used by the GET reads and the contract discovery
            " below (deep-service KUNNRs arrive unpadded - see project notes).
            CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
              EXPORTING input  = ls_custheader_db-kunnr
              IMPORTING output = ls_custheader_db-kunnr.

            " Resolve this sales order's ship-to (its WE partner). Contracts are
            " matched on the ship-to, replicating the Without-Vehicle tab whose
            " identity space (get_scope_customers) was built from KNVP WE
            " partners. Stored on the indent so the commitment sum can be keyed
            " on the SAME ship-to grain as the contract discovery.
            DATA lv_salesord_key TYPE vbeln.
            lv_salesord_key = ls_custheader_db-CONTRACT.
            CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
              EXPORTING input  = lv_salesord_key
              IMPORTING output = lv_salesord_key.
            SELECT SINGLE kunnr FROM vbpa INTO @ls_custheader_db-shipto
              WHERE vbeln = @lv_salesord_key AND posnr = '000000' AND parvw = 'WE'.
            IF sy-subrc <> 0 OR ls_custheader_db-shipto IS INITIAL.
              " fall back to the sold-to if the order carries no header WE partner
              ls_custheader_db-shipto = ls_custheader_db-kunnr.
            ENDIF.

            " New indents start OPEN. The external processor flips STATUS to 'C'
            " when the indent is consumed, so it stops using contract balance
            " (see get_available_for_material commitment filter).
            IF lv_is_update = abap_false.
              ls_custheader_db-status = 'O'.
            ELSE.
              " preserve the persisted status on update - a customer edit must
              " not silently reopen an indent the external system has closed.
              SELECT SINGLE status FROM zsd_customer_ord
                INTO @ls_custheader_db-status
                WHERE order_no = @lv_order_no.
            ENDIF.
            " ────────────────────────────────────────────────────────────────
            " 3. Process items (for modify: full replace logic)
            " ────────────────────────────────────────────────────────────────
            IF lv_is_update = abap_true.
                  " For modify: delete existing items (replace all)
                  DELETE FROM zsd_cstmr_orditm WHERE order_no = @lv_order_no.
            ENDIF.

            LOOP AT ls_custord_deep-custorderheadertoitem ASSIGNING FIELD-SYMBOL(<fs_item1>).
                   DATA ls_custitem_db LIKE LINE OF lt_custitems_db.

                   MOVE-CORRESPONDING <fs_item1> TO ls_custitem_db.


                   ls_custitem_db-order_no = lv_order_no.   " link to header

                   " Optional: for modify, you could add item-level update logic here (e.g., if POSNR exists, UPDATE else INSERT)
                   " But for simplicity, we use replace all – adjust if delta needed
                   " Basic validation
                   IF ls_custitem_db-matnr IS INITIAL OR ls_custitem_db-kwmeng <= 0.

                   ELSE.
                        APPEND ls_custitem_db TO lt_custitems_db.
                   ENDIF.
            ENDLOOP.

            IF lt_custitems_db IS INITIAL.
                  RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                  EXPORTING message = 'At least one item is required'.
            ENDIF.
            " ────────────────────────────────────────────────────────────────
            " 3b. Contract-balance enforcement
            "     Enforced against the SPECIFIC contract the indent is booked
            "     against (ls_custheader_db-CONTRACT), so it matches the open
            "     balance shown on the contract card 1:1 - get_available_for_
            "     contract uses the same ZMENG - VBFA releases - open indents
            "     math as CONTRACTITEMSE_GET_ENTITYSET. Requested quantities
            "     are aggregated per material and checked in MT. On an UPDATE the
            "     old items were already deleted above, so they are correctly
            "     excluded from the commitment sum.
            " ────────────────────────────────────────────────────────────────
            DATA: lv_avail_chk TYPE vbap-zmeng.
            DATA: BEGIN OF ls_reqmat,
                    matnr TYPE matnr,
                    qty   TYPE vbap-zmeng,
                  END OF ls_reqmat,
                  lt_reqmat LIKE STANDARD TABLE OF ls_reqmat.

            " aggregate the requested quantity per material for this order
            CLEAR lt_reqmat.
            LOOP AT lt_custitems_db INTO ls_custitem_db.
              READ TABLE lt_reqmat INTO ls_reqmat
                   WITH KEY matnr = ls_custitem_db-matnr.
              IF sy-subrc = 0.
                ls_reqmat-qty = ls_reqmat-qty + ls_custitem_db-kwmeng.
                MODIFY lt_reqmat FROM ls_reqmat INDEX sy-tabix.
              ELSE.
                CLEAR ls_reqmat.
                ls_reqmat-matnr = ls_custitem_db-matnr.
                ls_reqmat-qty   = ls_custitem_db-kwmeng.
                APPEND ls_reqmat TO lt_reqmat.
              ENDIF.
            ENDLOOP.

            " lv_salesord_key = the picked contract, ALPHA-padded above
            LOOP AT lt_reqmat INTO ls_reqmat.
              lv_avail_chk = get_available_for_contract(
                               iv_vbeln = lv_salesord_key
                               iv_matnr = ls_reqmat-matnr ).
              IF lv_avail_chk < 0.
                RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                  EXPORTING message =
                    |No valid contract found for material { ls_reqmat-matnr }|.
              ENDIF.
              IF ls_reqmat-qty > lv_avail_chk.
                RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                  EXPORTING message =
                    |Requested { ls_reqmat-qty } MT for material { ls_reqmat-matnr } | &&
                    |exceeds available contract balance { lv_avail_chk } MT|.
              ENDIF.
            ENDLOOP.
            " ────────────────────────────────────────────────────────────────
            " 4. Database operations (create or modify)
            " ────────────────────────────────────────────────────────────────
            IF lv_is_update = abap_true.
                   MODIFY zsd_customer_ord FROM ls_custheader_db.   " ← MODIFY for update (handles key-based update)
                   IF sy-subrc <> 0.
                          ROLLBACK WORK.
                          RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                          EXPORTING message = 'Header modify failed'.
                   ENDIF.
            ELSE.
                   INSERT zsd_customer_ord FROM ls_custheader_db.
                   IF sy-subrc <> 0.
                          ROLLBACK WORK.
                          RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                          EXPORTING message = 'Header creation failed'.
                   ENDIF.
            ENDIF.

            INSERT zsd_cstmr_orditm FROM TABLE lt_custitems_db.

            IF sy-subrc <> 0.
                   ROLLBACK WORK.
                   RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
                   EXPORTING message = 'Items insert/modify failed'.
            ENDIF.

            COMMIT WORK AND WAIT.
            " ────────────────────────────────────────────────────────────────
            " 5. Return created/modified deep entity
            " ────────────────────────────────────────────────────────────────
            ls_custord_deep-order_no = lv_order_no.

            copy_data_to_ref(
                        EXPORTING is_data = ls_custord_deep
                        CHANGING  cr_data = er_deep_entity ).
  ENDCASE.
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->GET_RELEASED_QTY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ORDER_NO                    TYPE        ZSD_CSTMR_ORDITM-ORDER_NO
* | [--->] IV_MATNR                       TYPE        MATNR
* | [<-()] RV_QTY                         TYPE        ZSD_CSTMR_ORDITM-KWMENG
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method GET_RELEASED_QTY.
    " Qty of this bulk order + material that has already been SHIPPED OUT. STP's
    " SUBMIT_INDENT writes every processed indent into the Automate-TT staging
    " tables - ZSAUTOMATETT_TBL (volume/liquid tankers) and ZSAUTOMATETT_LPG
    " (SOLID products: WAX / SUL / RPC) - stamping ORDER_NO with the bulk order
    " and spreading up to 8 products across PROD_CMPn (material) with qty in
    " QUAN_COMPn (_TBL) / PROD_QUANn (_LPG). A material is either liquid or solid,
    " so a given order populates exactly ONE of the two tables.
    "
    " "Released" is gated on SHNUMBER <> space. Confirmed from ZAUTOTTLOAD:
    " SHNUMBER is the SHIPMENT number (ZLPG_HDR-SHNUM = NXTMBR, the generated
    " shipment no.; that value is ALPHA-formatted and MODIFY'd onto the staging
    " row in the same COMMIT that stamps SHNUM on the gate-pass headers). It is
    " NOT a sales-order VBELN, so it cannot be cross-checked against VBFA - we use
    " it purely as the flag "this row has been shipped" and take the quantity from
    " the staging QUAN columns. Un-shipped rows (SHNUMBER = space) are the still-
    " open part and are excluded; ZAUTOTTLOAD itself deletes blank rows for the day.
    "
    " REBRANDING: STP can ship a bulk order under a rebranded material number, so
    " the staging PROD_CMPn may not equal the indent's IV_MATNR. Matching on the
    " material number alone would then miss the shipped line and wrongly return 0,
    " over-stating availability. We resolve this by the SHAPE of the shipped data
    " rather than a ZREBRAND mapping table: a bulk order is usually SINGLE-product,
    " so when only one distinct product was shipped for the order we attribute the
    " whole shipped qty to IV_MATNR, brand-agnostic (the shipped product IS the
    " rebranded form of the indent material). Only when 2+ distinct products were
    " shipped (rare) do we fall back to an exact ALPHA match on PROD_CMPn - without
    " a mapping we cannot safely re-attribute a rebranded line across products, so
    " that case keeps the prior behaviour (a rebranded multi-product line still
    " returns 0 -> availability over-stated; documented residual).
    "
    " CAVEAT (data-model, not this filter): there is no SO/VBELN handle on these
    " tables, so a shipment later reversed WITHOUT SHNUMBER being cleared keeps
    " counting here -> released over-stated -> availability over-stated. A VBFA-
    " direct fix is not possible while SHNUMBER holds a shipment number; it would
    " need a shipment->delivery->SO walk (SHNUMBER -> VTTP -> LIPS -> VBFA), which
    " also loses the clean 'subset of the contract-side VBFA sum' property.
    "
    " Stored in the material's own UOM (KG for solids) - same scale as KWMENG, no
    " bridge. ORDER_NO is indexed on both tables. MATNR is ALPHA-normalised on both
    " sides so a numeric material (zero-padded in VBAP, raw on the staging row)
    " still matches.
    DATA lv_rel   TYPE zsd_cstmr_orditm-kwmeng.
    DATA lv_matnr TYPE matnr.
    DATA lv_cmp   TYPE matnr.

    TYPES: BEGIN OF ty_ship,
             matnr TYPE matnr,
             qty   TYPE zsd_cstmr_orditm-kwmeng,
           END OF ty_ship.
    DATA lt_ship TYPE STANDARD TABLE OF ty_ship.
    DATA ls_ship TYPE ty_ship.

    lv_matnr = iv_matnr.
    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
      EXPORTING input  = lv_matnr
      IMPORTING output = lv_matnr.

    " gather every SHIPPED product line for this order (liquid table).
    " qty column is QUAN_COMPn.
    SELECT * FROM zsautomatett_tbl INTO @DATA(ls_t)
      WHERE order_no = @iv_order_no AND shnumber <> @space.
      DO 8 TIMES.
        ASSIGN COMPONENT |PROD_CMP{ sy-index }| OF STRUCTURE ls_t TO FIELD-SYMBOL(<ct>).
        IF sy-subrc = 0 AND <ct> IS NOT INITIAL.
          lv_cmp = <ct>.
          CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
            EXPORTING input  = lv_cmp
            IMPORTING output = lv_cmp.
          ASSIGN COMPONENT |QUAN_COMP{ sy-index }| OF STRUCTURE ls_t TO FIELD-SYMBOL(<qt>).
          IF sy-subrc = 0.
            CLEAR ls_ship.
            ls_ship-matnr = lv_cmp.
            ls_ship-qty   = <qt>.
            APPEND ls_ship TO lt_ship.
          ENDIF.
        ENDIF.
      ENDDO.
    ENDSELECT.

    " ... and the solid table (WAX / SUL / RPC). qty column is PROD_QUANn.
    SELECT * FROM zsautomatett_lpg INTO @DATA(ls_l)
      WHERE order_no = @iv_order_no AND shnumber <> @space.
      DO 8 TIMES.
        ASSIGN COMPONENT |PROD_CMP{ sy-index }| OF STRUCTURE ls_l TO FIELD-SYMBOL(<cl>).
        IF sy-subrc = 0 AND <cl> IS NOT INITIAL.
          lv_cmp = <cl>.
          CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
            EXPORTING input  = lv_cmp
            IMPORTING output = lv_cmp.
          ASSIGN COMPONENT |PROD_QUAN{ sy-index }| OF STRUCTURE ls_l TO FIELD-SYMBOL(<ql>).
          IF sy-subrc = 0.
            CLEAR ls_ship.
            ls_ship-matnr = lv_cmp.
            ls_ship-qty   = <ql>.
            APPEND ls_ship TO lt_ship.
          ENDIF.
        ENDIF.
      ENDDO.
    ENDSELECT.

    " distinct products actually shipped on this order
    DATA lt_prod LIKE lt_ship.
    lt_prod = lt_ship.
    SORT lt_prod BY matnr.
    DELETE ADJACENT DUPLICATES FROM lt_prod COMPARING matnr.

    IF lines( lt_prod ) = 1.
      " single-product order (the usual case): attribute ALL shipped qty to the
      " indent material, regardless of any rebranded material number on the row.
      LOOP AT lt_ship INTO ls_ship.
        lv_rel = lv_rel + ls_ship-qty.
      ENDLOOP.
    ELSE.
      " multi-product order (rare): no ZREBRAND mapping to re-attribute a
      " rebranded line, so keep the exact ALPHA match (prior behaviour).
      LOOP AT lt_ship INTO ls_ship WHERE matnr = lv_matnr.
        lv_rel = lv_rel + ls_ship-qty.
      ENDLOOP.
    ENDIF.

    rv_qty = lv_rel.
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->GET_COMMITTED_QTY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ORDER_NO                    TYPE        ZSD_CSTMR_ORDITM-ORDER_NO
* | [--->] IV_MATNR                       TYPE        MATNR
* | [--->] IV_LINE_QTY                    TYPE        ZSD_CSTMR_ORDITM-KWMENG
* | [<-()] RV_QTY                         TYPE        ZSD_CSTMR_ORDITM-KWMENG
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method GET_COMMITTED_QTY.
    " Total quantity allocated to agents for this indent + material.
    DATA lv_alloc TYPE zsd_agnt_ordritm-quantity.

    SELECT SUM( quantity ) FROM zsd_agnt_ordritm
      INTO @lv_alloc
      WHERE order_no = @iv_order_no
        AND material = @iv_matnr.

    IF sy-subrc = 0 AND lv_alloc IS NOT INITIAL AND lv_alloc > 0.
      rv_qty = lv_alloc.        " 3rd-party indent: commit only what is lifted
    ELSE.
      rv_qty = iv_line_qty.     " self-lift / not yet allocated: commit full line
    ENDIF.
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->GET_AVAILABLE_FOR_CONTRACT
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_VBELN                       TYPE        VBELN_VA
* | [--->] IV_MATNR                       TYPE        MATNR
* | [<-()] RV_AVAIL                       TYPE        VBAP-ZMENG
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method GET_AVAILABLE_FOR_CONTRACT.
    " Remaining balance of ONE contract for one material, matching the figure
    " shown on the contract card (CONTRACTITEMSE_GET_ENTITYSET) 1:1:
    "
    "   available = SUM over this contract's lines for the material
    "                 ( VBAP-ZMENG - released VBFA, VBTYP_N 'C' )
    "             - open bulk-portal indents for this contract (STATUS <> 'C')
    "
    " Returns -1 when IV_VBELN is not a ZCQ contract line for the material
    " (distinct from a genuine zero balance) - same sentinel as the discovery
    " variant. Result is in the contract's native UOM: no MT/KG bridge is
    " applied; open indents subtract as stored. IV_VBELN must be ALPHA-padded.
    DATA: lv_deliv  TYPE vbfa-rfmng_flo,
          lv_native TYPE vbap-zmeng,
          lv_commit TYPE vbap-zmeng,
          lv_sokey  TYPE vbeln.

    " the picked contract's lines for this material (must be a ZCQ contract)
    SELECT a~posnr, a~zmeng, a~vrkme
      FROM vbak AS v
      INNER JOIN vbap AS a ON a~vbeln = v~vbeln
      INTO TABLE @DATA(lt_con)
      WHERE v~vbeln = @iv_vbeln
        AND v~auart = 'ZCQ'
        AND a~matnr = @iv_matnr.

    IF lt_con IS INITIAL.
      rv_avail = -1.           " picked doc is not a ZCQ contract for this material
      RETURN.
    ENDIF.

    " ordered - delivered, summed over the contract lines (contract native UOM)
    LOOP AT lt_con INTO DATA(ls_con).
      CLEAR lv_deliv.
      SELECT SUM( rfmng_flo ) FROM vbfa INTO @lv_deliv
        WHERE vbelv = @iv_vbeln AND vbtyp_n = 'C' AND posnv = @ls_con-posnr.
      lv_native = lv_native + ( ls_con-zmeng - lv_deliv ).
    ENDLOOP.

    " contract balance in its native UOM (no MT/KG bridge applied).
    rv_avail = lv_native.

    " open portal commitments for THIS contract + material (STATUS <> 'C').
    " CONTRACT is stored unpadded, so normalise before matching - mirrors the
    " display path in CONTRACTITEMSE_GET_ENTITYSET.
    SELECT h~CONTRACT, h~order_no, i~kwmeng
      FROM zsd_customer_ord AS h
      INNER JOIN zsd_cstmr_orditm AS i ON i~order_no = h~order_no
      INTO TABLE @DATA(lt_pc)
      WHERE i~matnr = @iv_matnr
        AND h~status <> 'C'.

    " keep only commitments booked against THIS contract, then collapse to one
    " row per order: get_committed_qty / get_released_qty aggregate at the
    " (order, material) grain, so calling them per item line would count an
    " order carrying the material on more than one line twice. COLLECT sums
    " KWMENG per order (contract is fixed = iv_vbeln for every kept row).
    TYPES: BEGIN OF ty_ord,
             order_no TYPE zsd_cstmr_orditm-order_no,
             kwmeng   TYPE zsd_cstmr_orditm-kwmeng,
           END OF ty_ord.
    DATA lt_ord TYPE STANDARD TABLE OF ty_ord.
    DATA ls_ord TYPE ty_ord.

    CLEAR lt_ord.
    LOOP AT lt_pc INTO DATA(ls_pc).
      lv_sokey = ls_pc-CONTRACT.
      CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
        EXPORTING input  = lv_sokey
        IMPORTING output = lv_sokey.
      IF lv_sokey = iv_vbeln.
        ls_ord-order_no = ls_pc-order_no.
        ls_ord-kwmeng   = ls_pc-kwmeng.
        COLLECT ls_ord INTO lt_ord.
      ENDIF.
    ENDLOOP.

    LOOP AT lt_ord INTO ls_ord.
      " agent-allocated qty for 3rd-party indents, full line otherwise, MINUS
      " what has already become a sales order: the released part is already
      " counted via the VBFA 'C' releases above.
      DATA(lv_line) = get_committed_qty( iv_order_no = ls_ord-order_no
                                         iv_matnr    = iv_matnr
                                         iv_line_qty = ls_ord-kwmeng ).
      lv_line = lv_line - get_released_qty( iv_order_no = ls_ord-order_no
                                            iv_matnr    = iv_matnr ).
      IF lv_line > 0.
        lv_commit = lv_commit + lv_line.
      ENDIF.
    ENDLOOP.

    rv_avail = rv_avail - lv_commit.
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->CONTRACTITEMSE_GET_ENTITYSET
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_FILTER_SELECT_OPTIONS       TYPE        /IWBEP/T_MGW_SELECT_OPTION
* | [--->] IS_PAGING                      TYPE        /IWBEP/S_MGW_PAGING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [--->] IT_ORDER                       TYPE        /IWBEP/T_MGW_SORTING_ORDER
* | [--->] IV_FILTER_STRING               TYPE        STRING
* | [--->] IV_SEARCH_STRING               TYPE        STRING
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITYSET(optional)
* | [<---] ET_ENTITYSET                   TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TT_CONTRACTITEM
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_CONTEXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method CONTRACTITEMSE_GET_ENTITYSET.

  " Contract items with their STILL-OPEN balance. For a contract (AUART 'ZCQ')
  " the total quantity is VBAP-ZMENG; the entity's KWMENG is overwritten below
  " with the open balance:
  "    open = ZMENG
  "         - SUM( VBFA-RFMNG_FLO where VBTYP_N = 'C' )   "released sales orders
  "         - open bulk-portal indents (zsd_customer_ord STATUS <> 'C')
  " Released orders link to the contract via VBFA (VBELV = contract,
  " POSNV = contract item). Open portal indents subtract as stored - no MT/KG
  " bridge is applied, mirroring get_available_for_material.

  types: begin of ty_commit,
             vbeln  type vbap-vbeln,               " padded contract number
             matnr  type vbap-matnr,
             qty_mt type zsd_cstmr_orditm-kwmeng,   " open portal commitment, MT
          end of ty_commit.

  DATA:   lt_items         TYPE TABLE OF zcl_zsd_custind_withou_mpc_ext=>ts_CONTRACTitem,
          wa_item          TYPE zcl_zsd_custind_withou_mpc_ext=>ts_CONTRACTitem,
          lt_filter_so     TYPE /iwbep/t_mgw_select_option,
          ls_filter_so     TYPE /iwbep/s_mgw_select_option,
          lt_vbeln_range   TYPE RANGE OF vbap-vbeln,
          ls_vbeln_range   LIKE LINE OF lt_vbeln_range,
          lv_vbeln         TYPE vbap-vbeln,
          lt_nav_path      TYPE /iwbep/t_mgw_navigation_path,
          ls_nav_path      TYPE /iwbep/s_mgw_navigation_path,
          lo_filter        TYPE REF TO /iwbep/if_mgw_req_filter.

  DATA:   lt_commit        TYPE TABLE OF ty_commit,
          lv_deliv         TYPE vbfa-rfmng_flo,
          lv_open          TYPE vbap-zmeng,
          lv_sokey         TYPE vbeln.

  " 1. Check for navigation from header (e.g., .../ToCONTRACTItem)
  lt_nav_path = it_navigation_path.
  READ TABLE lt_nav_path INTO ls_nav_path WITH KEY nav_prop = 'ToItem'.  " adjust case/name if your navigation property is different (check SEGW)
  IF sy-subrc = 0.
    " Navigation context → get VBELN from the source entity (header) key
    READ TABLE it_key_tab INTO DATA(ls_key) WITH KEY name = 'VBELN'.
    IF sy-subrc = 0.
      lv_vbeln = ls_key-value.

      CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
      EXPORTING
        input  = lv_vbeln
      IMPORTING
        output = lv_vbeln.


      lt_vbeln_range = VALUE #( ( sign = 'I' option = 'EQ' low = lv_vbeln ) ).
    ELSE.
      RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
        EXPORTING
          http_status_code = '400'
          message     = 'Navigation requested but VBELN key missing'.
    ENDIF.
  ELSE.
    " Standalone query → use $filter
    lo_filter = io_tech_request_context->get_filter( ).
    lt_filter_so = lo_filter->get_filter_select_options( ).

    " Extract VBELN filter if present
    READ TABLE lt_filter_so INTO ls_filter_so WITH KEY property = 'VBELN'.
    IF sy-subrc = 0.
      lt_vbeln_range = VALUE #( FOR ls_opt IN ls_filter_so-select_options
                                ( sign   = ls_opt-sign
                                  option = ls_opt-option
                                  low    = ls_opt-low
                                  high   = ls_opt-high ) ).
      " Alpha-pad the filter values so they match VBAP-VBELN and the
      " alpha-padded lv_sokey used in the commitment scope check below
      " (the navigation path already pads; the $filter path did not).
      LOOP AT lt_vbeln_range ASSIGNING FIELD-SYMBOL(<fs_rng>).
        CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
          EXPORTING input  = <fs_rng>-low
          IMPORTING output = <fs_rng>-low.
        IF <fs_rng>-high IS NOT INITIAL.
          CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
            EXPORTING input  = <fs_rng>-high
            IMPORTING output = <fs_rng>-high.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDIF.

  " If no filter and no navigation → optional: return empty or raise error
  IF lt_vbeln_range IS INITIAL.
    " You can decide policy: allow empty result, or restrict to filtered queries only
    " For safety (avoid dumping entire VBAP), raise exception or return empty
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        http_status_code = '400'
        message     = 'Please provide VBELN filter or navigate from a sales order header'.
  ENDIF.

  " 4. Fetch contract items from VBAP. ZMENG (target quantity) is the contract
  "    total; the entity's KWMENG is overwritten below with the open balance.
  SELECT vbeln, posnr, matnr, arktx, zmeng, vrkme, netpr, waerk, werks
    FROM vbap
    INTO TABLE @DATA(lt_vbap)
    WHERE vbeln IN @lt_vbeln_range.

  IF lt_vbap IS INITIAL.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        http_status_code = '404'
        message     = 'No items found for the specified contract(s)'.
  ENDIF.

  " Open bulk-portal commitments per (contract, material). Only OPEN indents
  " count (header STATUS <> 'C'; blank = legacy/open). CONTRACT is stored
  " unpadded, so normalise it to the padded VBELN before matching.
  SELECT h~CONTRACT, h~order_no, i~matnr, i~kwmeng
    FROM zsd_customer_ord AS h
    INNER JOIN zsd_cstmr_orditm AS i ON i~order_no = h~order_no
    INTO TABLE @DATA(lt_pc)
    WHERE h~status <> 'C'.

  " collapse to one row per (contract, order, material): get_committed_qty /
  " get_released_qty aggregate at the (order, material) grain, so calling them
  " per item line would count an order carrying the same material on more than
  " one line twice. COLLECT sums KWMENG per group.
  TYPES: BEGIN OF ty_pc,
           contract TYPE zsd_customer_ord-contract,
           order_no TYPE zsd_cstmr_orditm-order_no,
           matnr    TYPE zsd_cstmr_orditm-matnr,
           kwmeng   TYPE zsd_cstmr_orditm-kwmeng,
         END OF ty_pc.
  DATA lt_pcs TYPE STANDARD TABLE OF ty_pc.
  DATA ls_pcs TYPE ty_pc.

  LOOP AT lt_pc INTO DATA(ls_pc0).
    CLEAR ls_pcs.
    ls_pcs-contract = ls_pc0-contract.
    ls_pcs-order_no = ls_pc0-order_no.
    ls_pcs-matnr    = ls_pc0-matnr.
    ls_pcs-kwmeng   = ls_pc0-kwmeng.
    COLLECT ls_pcs INTO lt_pcs.
  ENDLOOP.

  LOOP AT lt_pcs INTO DATA(ls_pc).
    lv_sokey = ls_pc-CONTRACT.
    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
      EXPORTING input  = lv_sokey
      IMPORTING output = lv_sokey.

    " keep only commitments booked against the contracts in scope
    IF NOT line_exists( lt_vbeln_range[ low = lv_sokey ] ).
      CONTINUE.
    ENDIF.

    " 3rd-party indents commit only the agent-allocated (lifted) quantity;
    " self-lift indents commit the full item line. Same unit as KWMENG.
    DATA(lv_committed) = get_committed_qty( iv_order_no = ls_pc-order_no
                                            iv_matnr    = ls_pc-matnr
                                            iv_line_qty = ls_pc-kwmeng ).

    " subtract what has already become a sales order (STP indents at ZTT_STATUS
    " 2/3). Those releases are already netted out below via the VBFA 'C' sum, so
    " leaving them in the commitment double-subtracts them and the badge wrongly
    " reads "Fully Assigned". Reserve only the un-released remainder.
    lv_committed = lv_committed - get_released_qty( iv_order_no = ls_pc-order_no
                                                    iv_matnr    = ls_pc-matnr ).
    IF lv_committed < 0.
      lv_committed = 0.
    ENDIF.

    READ TABLE lt_commit ASSIGNING FIELD-SYMBOL(<fs_cm>)
         WITH KEY vbeln = lv_sokey matnr = ls_pc-matnr.
    IF sy-subrc = 0.
      <fs_cm>-qty_mt = <fs_cm>-qty_mt + lv_committed.
    ELSE.
      APPEND VALUE #( vbeln  = lv_sokey
                      matnr  = ls_pc-matnr
                      qty_mt = lv_committed ) TO lt_commit.
    ENDIF.
  ENDLOOP.

  " 5. Build each item with its open balance:
  "      open = ZMENG - VBFA releases (VBTYP_N 'C') - un-released bulk indents
  "    (the bulk commitment is netted of its already-released qty above, so the
  "     portion that became a sales order is not subtracted twice)
  LOOP AT lt_vbap INTO DATA(ls_vbap).
    CLEAR lv_deliv.
    SELECT SUM( rfmng_flo ) FROM vbfa INTO @lv_deliv
      WHERE vbelv = @ls_vbap-vbeln AND vbtyp_n = 'C' AND posnv = @ls_vbap-posnr.

    lv_open = ls_vbap-zmeng - lv_deliv.

    " subtract the open portal commitment for this material, ONCE per contract
    " (material grain mirrors get_available_for_material). Consume the entry so a
    " second contract line of the same material cannot subtract it twice.
    READ TABLE lt_commit ASSIGNING <fs_cm>
         WITH KEY vbeln = ls_vbap-vbeln matnr = ls_vbap-matnr.
    IF sy-subrc = 0 AND <fs_cm>-qty_mt > 0.
      lv_open = lv_open - <fs_cm>-qty_mt.
      CLEAR <fs_cm>-qty_mt.
    ENDIF.

    IF lv_open < 0.
      lv_open = 0.                 " never expose a negative open balance
    ENDIF.

    CLEAR wa_item.
    wa_item-vbeln  = ls_vbap-vbeln.
    wa_item-posnr  = ls_vbap-posnr.
    wa_item-matnr  = ls_vbap-matnr.
    wa_item-arktx  = ls_vbap-arktx.
    wa_item-kwmeng = lv_open.
    wa_item-zmeng  = ls_vbap-zmeng.   " contract total quantity (Total Contract Qty column)
    wa_item-vrkme  = ls_vbap-vrkme.
    wa_item-netpr  = ls_vbap-netpr.
    wa_item-waerk  = ls_vbap-waerk.
    wa_item-werks  = ls_vbap-werks.
    APPEND wa_item TO lt_items.
  ENDLOOP.

  " Optional: sort, page, etc. (Gateway handles $top/$skip/$orderby if not overridden)
  et_entityset = lt_items.
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->CONTRACTITEMSE_GET_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IO_REQUEST_OBJECT              TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY(optional)
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [<---] ER_ENTITY                      TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TS_CONTRACTITEM
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_ENTITY_CNTXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method CONTRACTITEMSE_GET_ENTITY.
DATA: ls_key_vbeln  TYPE /iwbep/s_mgw_name_value_pair,
        ls_key_posnr  TYPE /iwbep/s_mgw_name_value_pair,
        lv_vbeln      TYPE vbap-vbeln,
        lv_posnr      TYPE vbap-posnr,
        ls_item       TYPE zcl_zsd_custind_withou_mpc_ext=>ts_CONTRACTitem.

  " Get VBELN key
  READ TABLE it_key_tab INTO ls_key_vbeln WITH KEY name = 'Vbeln'.
  IF sy-subrc <> 0.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        http_status_code = '400'
        message     = 'Missing mandatory key field: VBELN'.
  ENDIF.

  lv_vbeln = ls_key_vbeln-value.

  " Get POSNR key
  READ TABLE it_key_tab INTO ls_key_posnr WITH KEY name = 'Posnr'.
  IF sy-subrc <> 0.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        http_status_code = '400'
        message     = 'Missing mandatory key field: POSNR'.
  ENDIF.

  lv_posnr = ls_key_posnr-value.

  " Fetch single item
  SELECT SINGLE vbeln,posnr,matnr,arktx,kwmeng,vrkme,werks
    FROM vbap
    INTO CORRESPONDING FIELDS OF @ls_item
    WHERE vbeln = @lv_vbeln
      AND posnr = @lv_posnr.

  IF sy-subrc <> 0.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        http_status_code = '404'
        message     = |Item { lv_posnr } for Sales Order { lv_vbeln } not found|.
  ENDIF.

  er_entity = ls_item.
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->CONTRACTHEADER_GET_ENTITYSET
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_FILTER_SELECT_OPTIONS       TYPE        /IWBEP/T_MGW_SELECT_OPTION
* | [--->] IS_PAGING                      TYPE        /IWBEP/S_MGW_PAGING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [--->] IT_ORDER                       TYPE        /IWBEP/T_MGW_SORTING_ORDER
* | [--->] IV_FILTER_STRING               TYPE        STRING
* | [--->] IV_SEARCH_STRING               TYPE        STRING
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITYSET(optional)
* | [<---] ET_ENTITYSET                   TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TT_CONTRACTHEADER
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_CONTEXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method CONTRACTHEADER_GET_ENTITYSET.
        data: lt_CONTRACT_headers type zcl_zsd_cust_bulk_inde_mpc=>tt_CONTRACTheader,
              wa_CONTRACT_hdr like line of lt_CONTRACT_headers.

        data: lt_salesdoc type table of vbak.

        DATA: lt_bstdk_range TYPE RANGE OF vbak-bstdk,
              lt_vbeln_range TYPE RANGE OF vbak-vbeln,
              lt_filter_so   TYPE TABLE OF /iwbep/s_mgw_select_option,
              ls_filter_so   TYPE /iwbep/s_mgw_select_option,
              lo_filter      TYPE REF TO /iwbep/if_mgw_req_filter.

        " 1. Try select-options first (for simple filters)
        lo_filter = io_tech_request_context->get_filter( ).
        lt_filter_so = lo_filter->get_filter_select_options( ).

        READ TABLE lt_filter_so INTO ls_filter_so WITH KEY property = 'BSTDK'.
        IF sy-subrc = 0.

          LOOP AT ls_filter_so-select_options ASSIGNING FIELD-SYMBOL(<fs_opt>).
            DATA(lv_low)  = <fs_opt>-low.
            DATA(lv_high) = <fs_opt>-high.

            " Remove '-' if present and length matches ISO date
            REPLACE ALL OCCURRENCES OF '-' IN lv_low  WITH ''.
            REPLACE ALL OCCURRENCES OF '-' IN lv_high WITH ''.

            IF strlen( lv_low ) = 8 AND lv_low CO '0123456789'.
              APPEND VALUE #( sign = <fs_opt>-sign option = <fs_opt>-option
                              low = lv_low high = lv_high ) TO lt_bstdk_range.
            ELSEIF lv_low IS NOT INITIAL.
              " Optional: raise error or ignore invalid date
              " RAISE EXCEPTION ... 'Invalid date format in filter BSTDK'.
            ENDIF.
          ENDLOOP.

        ENDIF.

        READ TABLE lt_filter_so INTO ls_filter_so WITH KEY property = 'VBELN'.

        IF sy-subrc = 0.
          lt_vbeln_range = VALUE #( FOR ls_opt IN ls_filter_so-select_options
                                    ( sign   = ls_opt-sign
                                      option = ls_opt-option
                                      low    = ls_opt-low
                                      high   = ls_opt-high ) ).
        ENDIF.


     " Read all request headers then find the one we need
      DATA(lt_headers) = io_tech_request_context->get_request_headers( ).

      DATA(lv_portal_user) = VALUE string( ).
      READ TABLE lt_headers INTO DATA(ls_header1)
          WITH KEY name = 'x-portal-user'.
      IF sy-subrc = 0.
          lv_portal_user = ls_header1-value.
      ENDIF.

      IF lv_portal_user IS INITIAL.
          lv_portal_user = sy-uname.  " fallback
      ENDIF.

        select single *
        from zsd_cust_usr_map into @data(ls_customer) where cust_user_id eq @lv_portal_user.

        " 4. Fetch data from VBAK. Only CONTRACTS (AUART = 'ZCQ') are surfaced in
        "    the bulk portal - a single contract carries the total quantity and
        "    many sales orders are released against it. The still-open balance is
        "    computed per contract item in CONTRACTITEMSE_GET_ENTITYSET
        "    (VBAP-ZMENG - VBFA releases - open portal indents) and flows up here
        "    through the ToItem expand.
        if lt_vbeln_range[] is initial.
          SELECT *
              FROM vbak
              into corresponding fields of table @lt_salesdoc
                   WHERE bstdk IN @lt_bstdk_range and kunnr eq @ls_customer-kunnr
                   and auart eq 'ZCQ'.
        elseif lt_bstdk_range is initial.
          SELECT *
              FROM vbak
              INTO CORRESPONDING FIELDS OF TABLE @lt_salesdoc
                   WHERE vbeln IN @lt_vbeln_range and kunnr eq @ls_customer-kunnr
                   and auart eq 'ZCQ'.
        else.
          SELECT *
              FROM vbak
              INTO CORRESPONDING FIELDS OF TABLE @lt_salesdoc
                   WHERE vbeln IN @lt_vbeln_range
                   AND bstdk IN @lt_bstdk_range and kunnr eq @ls_customer-kunnr
                   and auart eq 'ZCQ'.
        endif.


        if lt_salesdoc is not initial.
          loop at lt_salesdoc into data(wa_salesdoc).
            move-corresponding wa_salesdoc to wa_CONTRACT_hdr.

            concatenate 'C' lv_portal_user into data(lv_customerno).

            select single * from but000 into @data(wa_addr) where partner eq @lv_customerno.

            concatenate wa_addr-name_org1 wa_addr-name_org2 wa_addr-name_org3 into data(lv_addr) separated by space.
            shift lv_addr right deleting trailing space.

            wa_CONTRACT_hdr-delivloc = lv_addr.
            wa_CONTRACT_hdr-delivdate = wa_salesdoc-vdatu.

            append wa_CONTRACT_hdr to lt_CONTRACT_headers.

            clear lv_addr.

          endloop.
        endif.



        IF sy-subrc <> 0 OR  lt_CONTRACT_headers[] IS INITIAL.
          RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
            EXPORTING
              http_status_code = '404'
              message     = 'No contracts found matching the filter'.
        ENDIF.

        et_entityset = lt_CONTRACT_headers.

ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->CONTRACTHEADER_GET_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IO_REQUEST_OBJECT              TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY(optional)
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [<---] ER_ENTITY                      TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TS_CONTRACTHEADER
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_ENTITY_CNTXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method CONTRACTHEADER_GET_ENTITY.
  DATA: ls_key        TYPE /iwbep/s_mgw_name_value_pair,
        lv_vbeln      TYPE vbak-vbeln,
        ls_salesdoc   TYPE vbak,
        ls_header     TYPE zcl_zsd_cust_bulk_inde_mpc=>TS_CONTRACTHEADER.

  DATA: lv_customerno type string.

  " Get the key value for VBELN
  READ TABLE it_key_tab INTO ls_key WITH KEY name = 'VBELN'.
  IF sy-subrc = 0.
    lv_vbeln = ls_key-value.
  ELSE.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        http_status_code = '400'
        message     = 'Missing mandatory key field: VBELN'.
  ENDIF.

  " Read all request headers then find the one we need
  DATA(lt_headers) = io_tech_request_context->get_request_headers( ).

  DATA(lv_portal_user) = VALUE string( ).
  READ TABLE lt_headers INTO DATA(ls_header1)
      WITH KEY name = 'x-portal-user'.
  IF sy-subrc = 0.
      lv_portal_user = ls_header1-value.
  ENDIF.

  IF lv_portal_user IS INITIAL.
      lv_portal_user = sy-uname.  " fallback
  ENDIF.


  select single *
        from zsd_cust_usr_map into @data(ls_customer) where cust_user_id eq @lv_portal_user.

  " Fetch single sales order header
  SELECT SINGLE *
    FROM vbak
    INTO CORRESPONDING FIELDS OF @ls_salesdoc
    WHERE vbeln = @lv_vbeln and kunnr eq @ls_customer-kunnr.

  concatenate 'C' lv_portal_user into lv_customerno.

  select single * from but000 into @data(ls_delivaddr) where partner eq @lv_customerno.

  concatenate ls_delivaddr-name_org1 ls_delivaddr-name_org2 ls_delivaddr-name_org3 ls_delivaddr-name_org3
              into data(lv_address) separated by space.

  shift lv_address right deleting trailing space.
  move-corresponding ls_salesdoc to ls_header.


  ls_header-delivloc = lv_address.
  ls_header-delivdate = ls_salesdoc-vdatu.

  IF sy-subrc <> 0.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        http_status_code = '404'
        message     = |Contract { lv_vbeln } not found|.
  ENDIF.


  move-corresponding ls_header to er_entity.
  endmethod.
ENDCLASS.