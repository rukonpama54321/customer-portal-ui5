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

  " optional: leading-zero conversion if the DB stores padded values
  " CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
  "   EXPORTING input = lv_agent_id IMPORTING output = lv_agent_id.
  " CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
  "   EXPORTING input = lv_kunnr    IMPORTING output = lv_kunnr.

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

  IF sy-subrc = 0.
    COMMIT WORK AND WAIT.
  ELSE.
    ROLLBACK WORK.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        http_status_code = '500'
        message          = 'Failed to delete agent'.
  ENDIF.
endmethod.