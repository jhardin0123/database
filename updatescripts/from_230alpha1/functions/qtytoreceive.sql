CREATE OR REPLACE FUNCTION qtyToReceive(TEXT, INTEGER) RETURNS NUMERIC AS '
DECLARE
  pordertype	ALIAS FOR $1;
  porderitemid	ALIAS FOR $2;
  _qty		NUMERIC;

BEGIN
  IF (pordertype = ''TO'' AND NOT fetchMetricBool(''MultiWhs'')) THEN
    RETURN 0;
  END IF;

  IF (pordertype = ''RA'' AND NOT fetchMetricBool(''EnableReturnAuth'')) THEN
    RETURN 0;
  END IF;

  SELECT SUM(recv_qty) INTO _qty
  FROM recv
  WHERE ((recv_orderitem_id=porderitemid)
    AND  (NOT recv_posted)
    AND  (recv_order_type=pordertype));

  RETURN COALESCE(_qty, 0.0);

END;
' LANGUAGE 'plpgsql';
