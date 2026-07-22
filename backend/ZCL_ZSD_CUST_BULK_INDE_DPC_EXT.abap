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
  methods SALESORDERHEADER_GET_ENTITY
    redefinition .
  methods SALESORDERHEADER_GET_ENTITYSET
    redefinition .
  methods SALESORDERITEMSE_GET_ENTITY
    redefinition .
  methods SALESORDERITEMSE_GET_ENTITYSET
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
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->SALESORDERITEMSE_GET_ENTITYSET
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
* | [<---] ET_ENTITYSET                   TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TT_SALESORDERITEM
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_CONTEXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method SALESORDERITEMSE_GET_ENTITYSET.

  types: begin of ty_usedqty,
             salesord type vbak-vbeln,
             posnr type vbap-posnr,
             matnr type mara-matnr,
             kwmeng type vbap-kwmeng,
          end of ty_usedqty.

  data:   lt_used type table of ty_usedqty,
          ls_used type ty_usedqty.

  DATA:   lt_items         TYPE TABLE OF zcl_zsd_custind_withou_mpc_ext=>ts_salesorderitem,
          lt_items2         TYPE TABLE OF zcl_zsd_custind_withou_mpc_ext=>ts_salesorderitem,
          lt_filter_so     TYPE /iwbep/t_mgw_select_option,
          ls_filter_so     TYPE /iwbep/s_mgw_select_option,
          lt_vbeln_range   TYPE RANGE OF vbap-vbeln,
          ls_vbeln_range   LIKE LINE OF lt_vbeln_range,
          lv_vbeln         TYPE vbap-vbeln,
          lt_nav_path      TYPE /iwbep/t_mgw_navigation_path,   " <-- FIXED: use this type!
          ls_nav_path      TYPE /iwbep/s_mgw_navigation_path,   " <-- also change to matching line type
          lo_filter        TYPE REF TO /iwbep/if_mgw_req_filter.


  data: lt_custord type table of zsd_customer_ord.
  data: lt_cstmr_orditms type table of zsd_cstmr_orditm.

  data lv_calc type vbap-kwmeng.

  " 1. Check for navigation from header (e.g., .../ToSALESORDERItem)
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

  " 4. Fetch items from VBAP
  SELECT *
    FROM vbap
    INTO CORRESPONDING FIELDS OF TABLE @lt_items
    WHERE vbeln IN @lt_vbeln_range.

  refresh lt_custord.
  select  * from zsd_customer_ord into corresponding fields of table lt_custord where salesorder IN lt_vbeln_range.

  clear ls_used.
  refresh lt_used.

  loop at lt_custord into data(ls_custord).
    refresh lt_cstmr_orditms.
    select * from zsd_cstmr_orditm into table lt_cstmr_orditms where order_no eq ls_custord-order_no.

    loop at lt_cstmr_orditms into data(ls_cstmr_orditms).
      read table lt_used into data(ls_used2) with key salesord = ls_custord-salesorder posnr = ls_cstmr_orditms-posnr.

      if ls_used2 is initial.
         ls_used-salesord = ls_custord-salesorder.
         ls_used-posnr = ls_cstmr_orditms-posnr.
         ls_used-matnr = ls_cstmr_orditms-matnr.
         ls_used-kwmeng = ls_cstmr_orditms-usedqty.

         append ls_used to lt_used.
      else.
         ls_used-salesord = ls_custord-salesorder.
         ls_used-posnr = ls_cstmr_orditms-posnr.
         ls_used-matnr = ls_cstmr_orditms-matnr.
         add ls_cstmr_orditms-usedqty to ls_used2-kwmeng.

         ls_used-kwmeng = ls_used2-kwmeng.

         delete lt_used where salesord eq ls_used-salesord and posnr eq ls_used-posnr.
         append ls_used to lt_used.
      endif.

      clear ls_used2.

    endloop.
  endloop.

  loop at lt_items into data(wa_items).
    read table lt_used into ls_used with key salesord = ls_custord-salesorder posnr = wa_items-posnr.
    wa_items-kwmeng = wa_items-kwmeng - ls_used-kwmeng.

    append wa_items to lt_items2.
  endloop.

  IF sy-subrc <> 0 OR lt_items IS INITIAL.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        http_status_code = '404'
        message     = 'No items found for the specified sales order(s)'.
  ENDIF.

  " Optional: sort, page, etc. (Gateway handles $top/$skip/$orderby if not overridden)
  et_entityset = lt_items2.
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->SALESORDERITEMSE_GET_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IO_REQUEST_OBJECT              TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY(optional)
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [<---] ER_ENTITY                      TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TS_SALESORDERITEM
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_ENTITY_CNTXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method SALESORDERITEMSE_GET_ENTITY.
DATA: ls_key_vbeln  TYPE /iwbep/s_mgw_name_value_pair,
        ls_key_posnr  TYPE /iwbep/s_mgw_name_value_pair,
        lv_vbeln      TYPE vbap-vbeln,
        lv_posnr      TYPE vbap-posnr,
        ls_item       TYPE zcl_zsd_custind_withou_mpc_ext=>ts_salesorderitem.

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
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->SALESORDERHEADER_GET_ENTITYSET
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
* | [<---] ET_ENTITYSET                   TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TT_SALESORDERHEADER
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_CONTEXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method SALESORDERHEADER_GET_ENTITYSET.
        data: lt_salesorder_headers type table of zcl_zsd_custind_withou_mpc_ext=>ts_salesorderheader,
              wa_salesorder_hdr like line of lt_salesorder_headers.

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

        " 4. Fetch data from VBAK (add more fields or WHERE clauses as needed)
        if lt_vbeln_range[] is initial.
          SELECT *
              FROM vbak
              into corresponding fields of table @lt_salesdoc
                   WHERE bstdk IN @lt_bstdk_range and kunnr eq @ls_customer-kunnr.
        elseif lt_bstdk_range is initial.
          SELECT *
              FROM vbak
              INTO CORRESPONDING FIELDS OF TABLE @lt_salesdoc
                   WHERE vbeln IN @lt_vbeln_range and kunnr eq @ls_customer-kunnr.
        else.
          SELECT *
              FROM vbak
              INTO CORRESPONDING FIELDS OF TABLE @lt_salesdoc
                   WHERE vbeln IN @lt_vbeln_range
                   AND bstdk IN @lt_bstdk_range and kunnr eq @ls_customer-kunnr.
        endif.


        if lt_salesdoc is not initial.
          loop at lt_salesdoc into data(wa_salesdoc).
            move-corresponding wa_salesdoc to wa_salesorder_hdr.

            concatenate 'C' lv_portal_user into data(lv_customerno).

            select single * from but000 into @data(wa_addr) where partner eq @lv_customerno.

            concatenate wa_addr-name_org1 wa_addr-name_org2 wa_addr-name_org3 into data(lv_addr) separated by space.
            shift lv_addr right deleting trailing space.

            wa_salesorder_hdr-delivloc = lv_addr.
            wa_salesorder_hdr-delivdate = wa_salesdoc-vdatu.

            append wa_salesorder_hdr to lt_salesorder_headers.

            clear lv_addr.

          endloop.
        endif.



        IF sy-subrc <> 0 OR  lt_salesorder_headers[] IS INITIAL.
          RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
            EXPORTING
              http_status_code = '404'
              message     = 'No sales orders found matching the filter'.
        ENDIF.

        et_entityset = lt_salesorder_headers.

ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_BULK_INDE_DPC_EXT->SALESORDERHEADER_GET_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IO_REQUEST_OBJECT              TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY(optional)
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [<---] ER_ENTITY                      TYPE        ZCL_ZSD_CUST_BULK_INDE_MPC=>TS_SALESORDERHEADER
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_ENTITY_CNTXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method SALESORDERHEADER_GET_ENTITY.
  DATA: ls_key        TYPE /iwbep/s_mgw_name_value_pair,
        lv_vbeln      TYPE vbak-vbeln,
        ls_salesdoc   TYPE vbak,
        ls_header     TYPE zcl_zsd_custind_withou_mpc_ext=>ts_salesorderheader.

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
        message     = |Sales Order { lv_vbeln } not found|.
  ENDIF.


  er_entity = ls_header.
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
        lr_salesorder   TYPE RANGE OF zsd_customer_ord-salesorder,
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

    READ TABLE it_filter_select_options INTO ls_filter WITH KEY property = 'SALESORDER'.
    IF sy-subrc = 0.
      lr_salesorder = VALUE #( FOR opt IN ls_filter-select_options
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
        AND salesorder IN @lr_salesorder
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
          AND salesorder IN @lr_salesorder.

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

  " 2. Optional: existence check + business rules
  SELECT SINGLE *
    FROM zsd_customer_ord
    INTO ls_cust_ord
    WHERE order_no = lv_order_no.

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

  " Fetch items
  SELECT
    order_no,
    posnr,
    matnr,
    arktx,
    kwmeng,
    vrkme,
    netpr,
    waerk,
    werks,   " duplicate? adjust if typo
    usedqty   " BALANCE ?
  FROM zsd_cstmr_orditm
  WHERE order_no IN @lr_order_no
    AND posnr    IN @lr_posnr
  ORDER BY order_no,posnr
  INTO CORRESPONDING FIELDS OF TABLE @lt_items
  UP TO @lv_top ROWS OFFSET @lv_skip    .

  " Inline count (optional)
  IF io_tech_request_context->has_inlinecount( ) = abap_true.
    SELECT COUNT(*)
      FROM zsd_cstmr_orditm
      INTO @data(lv_count)
      WHERE order_no IN @lr_order_no
        AND posnr    IN @lr_posnr.

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
            lv_salesord_key = ls_custheader_db-salesorder.
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
            "     These sales docs are VBTYP 'C' orders, so the governing
            "     contract is discovered from (KUNNR + MATNR). Requested
            "     quantities are aggregated per material and checked against
            "     the available balance (get_available_for_material). On an
            "     UPDATE the old items were already deleted above, so they are
            "     correctly excluded from the commitment sum below.
            " ────────────────────────────────────────────────────────────────
            DATA: lv_depot_chk TYPE werks_d,
                  lv_avail_chk TYPE vbap-zmeng.
            DATA: BEGIN OF ls_reqmat,
                    matnr TYPE matnr,
                    qty   TYPE vbap-zmeng,
                  END OF ls_reqmat,
                  lt_reqmat LIKE STANDARD TABLE OF ls_reqmat.

            SELECT SINGLE depot FROM zsd_cust_usr_map INTO @lv_depot_chk
              WHERE cust_user_id = @lv_portal_user.

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

            LOOP AT lt_reqmat INTO ls_reqmat.
              lv_avail_chk = get_available_for_material(
                               iv_shipto = ls_custheader_db-shipto
                               iv_matnr  = ls_reqmat-matnr
                               iv_depot  = lv_depot_chk ).
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
    " UOM: the result is returned in MT (customers enter quantities in MT).
    " Contracts are maintained in their native UOM (KG for the wax/sulphur
    " products), so a KG contract is bridged to MT as 1 MT = 1000 KG - the same
    " x1000 bridge the Without-Vehicle SAVE check used. Open commitments
    " (zsd_cstmr_orditm-KWMENG) are also stored in MT, so they subtract
    " directly. A non-KG contract is assumed to already be in MT and is not
    " scaled - revisit if that assumption is ever false.
    "
    " Contracts are matched on the ship-to partner (PARVW = 'WE'), replicating
    " the Without-Vehicle tab. IV_SHIPTO is the sales order's own WE partner,
    " resolved by the caller from VBPA (see the CustomerOrderSet create branch).
    DATA: lv_deliv  TYPE vbfa-rfmng_flo,
          lv_native TYPE vbap-zmeng,
          lv_commit TYPE vbap-zmeng,
          lv_uom    TYPE vbap-zieme.

    " candidate contracts (Without-Vehicle SELECT_CONTRACT_NVEH parity:
    " valid today / ship-to = customer / exact material / OWN-BOND valuation /
    " user's depot / real item category / not rejected)
    SELECT v~vbeln, a~posnr, a~zmeng, a~zieme
      FROM vbak AS v
      INNER JOIN vbpa AS p ON p~vbeln = v~vbeln
      INNER JOIN vbap AS a ON a~vbeln = v~vbeln
      INTO TABLE @DATA(lt_con)
      WHERE v~guebg <= @sy-datum AND v~gueen >= @sy-datum
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
      IF lv_uom IS INITIAL.
        lv_uom = ls_con-zieme.          " representative contract UOM
      ENDIF.
      CLEAR lv_deliv.
      SELECT SUM( rfmng_flo ) FROM vbfa INTO @lv_deliv
        WHERE vbelv = @ls_con-vbeln AND vbtyp_n = 'C' AND posnv = @ls_con-posnr.
      lv_native = lv_native + ( ls_con-zmeng - lv_deliv ).
    ENDLOOP.

    " bridge the contract balance to MT (customers enter MT). KG contract:
    " 1 MT = 1000 KG. Any other UOM is assumed already MT and left unscaled.
    IF lv_uom = 'KG'.
      rv_avail = lv_native / 1000.
    ELSE.
      rv_avail = lv_native.
    ENDIF.

    " open commitments already booked via the BULK portal for this
    " ship-to + material, in MT. zsd_cstmr_orditm carries no contract column,
    " so the commitment is counted at the (ship-to, material) grain - the same
    " grain the contract discovery above uses. Only OPEN indents count: once
    " the external processor sets STATUS = 'C', the indent stops consuming
    " balance (blank status = legacy/open, still counts - safe default).
    SELECT SUM( i~kwmeng )
      FROM zsd_cstmr_orditm AS i
      INNER JOIN zsd_customer_ord AS h ON h~order_no = i~order_no
      INTO @lv_commit
      WHERE h~shipto = @iv_shipto
        AND i~matnr  = @iv_matnr
        AND h~status <> 'C'.

    rv_avail = rv_avail - lv_commit.
  endmethod.
ENDCLASS.