CREATE OR REPLACE FUNCTION _aropenTrigger() RETURNS TRIGGER AS $$
DECLARE
  _openAmount NUMERIC;
  _p RECORD;
  _lateCount INTEGER := 0;
  _graceDays INTEGER;
  _checkLate BOOLEAN := false;
  _checkLimit BOOLEAN := false;
  _id INTEGER;
BEGIN
  -- Checks
  -- Start with privileges
  IF ( (NOT checkPrivilege('MaintainARMemos')) AND
       (NOT checkPrivilege('PostMiscInvoices')) AND
       (NOT checkPrivilege('PostARDocuments')) ) THEN
    RAISE EXCEPTION 'You do not have privileges to maintain A/R Memos.';
  END IF;

  IF ( (NEW.aropen_docnumber IS NULL) OR (LENGTH(NEW.aropen_docnumber) = 0) ) THEN
    RAISE EXCEPTION 'You must enter a valid Document # for this A/R Memo.';
  END IF;

  IF ( (NEW.aropen_amount IS NOT NULL) AND (NEW.aropen_amount <= 0) ) THEN
    RAISE EXCEPTION 'You must enter a positive Amount for this A/R Memo.';
  END IF;

  IF (TG_OP = 'INSERT') THEN
    SELECT aropen_id INTO _id
    FROM aropen
    WHERE ( (aropen_doctype=NEW.aropen_doctype)
      AND   (aropen_docnumber=NEW.aropen_docnumber) )
    LIMIT 1;
    IF (FOUND) THEN
      RAISE EXCEPTION 'This Document Type/Number already exists. You may not enter a duplicate A/R Memo.';
    END IF;
  END IF;

-- Determine the number of late invoices
  IF ( SELECT (metric_value='t')
         FROM metric
        WHERE(metric_name='AutoCreditWarnLateCustomers')) THEN
    _checkLate := true;

    SELECT COALESCE(metric_value::integer, _graceDays)
      INTO _graceDays
      FROM metric
     WHERE(metric_name='DefaultAutoCreditWarnGraceDays');
    IF (NOT FOUND) THEN
      _graceDays := 30;
    END IF;
    SELECT COALESCE(cust_gracedays, _graceDays)
      INTO _graceDays
      FROM custinfo
     WHERE(cust_id=NEW.aropen_cust_id);
    IF (NOT FOUND) THEN
      _graceDays := 30;
    END IF;

    SELECT count(aropen_id)
      INTO _lateCount
      FROM aropen
     WHERE((NEW.aropen_cust_id = aropen_cust_id)
       AND (aropen_open)
       AND (aropen_amount > aropen_paid)
       AND (aropen_doctype IN ('I', 'D'))
       AND (aropen_duedate < (CURRENT_DATE - _graceDays)));

  --  Adjust _lateCount if late invoice being paid
    IF ( (NEW.aropen_paid = NEW.aropen_amount)
     AND (NEW.aropen_doctype IN ('I', 'D'))
     AND (NEW.aropen_duedate < (CURRENT_DATE - _graceDays))) THEN
      _lateCount := _lateCount - 1;
    END IF;
  END IF;

--  Close this aropen if it is paid
  IF (NEW.aropen_paid = NEW.aropen_amount) THEN
    NEW.aropen_open=FALSE;
    IF (TG_OP = 'UPDATE') THEN
      IF ((OLD.aropen_open=TRUE) and (NEW.aropen_open=FALSE)) THEN
        NEW.aropen_closedate=current_date;
      END IF;
    END IF;

--  Remove any aropenco regards that reference this aropen item
    DELETE FROM aropenco WHERE (aropenco_aropen_id=NEW.aropen_id);
  END IF;

--  Only check if the customer in question has a non-zero Credit Limit
  SELECT cust_id, cust_creditlmt, cust_creditstatus,
         cust_autoupdatestatus, cust_autoholdorders INTO _p
  FROM cust
  WHERE (cust_id=NEW.aropen_cust_id);
  IF (_p.cust_creditlmt > 0) THEN
    _checkLimit := true;

    SELECT COALESCE(SUM( CASE WHEN (aropen_doctype IN ('I', 'D')) THEN (aropen_amount - aropen_paid)
                     ELSE ((aropen_amount - aropen_paid) * -1)
                END ), 0.0) INTO _openAmount
    FROM aropen AS current
    WHERE ( (current.aropen_cust_id=NEW.aropen_cust_id)
     AND (current.aropen_open)
     AND (current.aropen_id <> NEW.aropen_id) );

--  Add in the value of the current aropen item
    IF (NEW.aropen_doctype IN ('I', 'D')) THEN
      _openAmount := (_openAmount + (NEW.aropen_amount - NEW.aropen_paid));
    ELSE
      _openAmount := (_openAmount - (NEW.aropen_amount - NEW.aropen_paid));
    END IF;
  ELSE
    _openAmount := 0;
  END IF;

  IF (_checkLimit OR _checkLate) THEN
--  Handle a Customer that is going under its credit limit
    IF ((_p.cust_creditlmt >= _openAmount) AND (_lateCount <= 0)) THEN

--  Handle the Customer Status
      IF ( (_p.cust_autoupdatestatus) AND (_p.cust_creditstatus='W') ) THEN
        UPDATE custinfo
        SET cust_creditstatus='G'
        WHERE (cust_id=NEW.aropen_cust_id);
      END IF;

--  Handle the open Sales Orders
      IF (_p.cust_autoholdorders) THEN
        UPDATE cohead
        SET cohead_holdtype='N'
        FROM coitem
        WHERE ( (coitem_cohead_id=cohead_id)
         AND (cohead_holdtype='C')
         AND (coitem_status='O')
         AND (cohead_cust_id=_p.cust_id) );
      END IF;

--  Handle a Customer that is going over its credit limit
    ELSIF ((_p.cust_creditlmt < _openAmount) OR (_lateCount > 0)) THEN

--  Handle the Customer Status
      IF ( (_p.cust_autoupdatestatus) AND (_p.cust_creditstatus = 'G') ) THEN
        UPDATE custinfo
        SET cust_creditstatus='W'
        WHERE (cust_id=NEW.aropen_cust_id);
      END IF;

--  Handle the open Sales Orders
      IF (_p.cust_autoholdorders) THEN
        UPDATE cohead
        SET cohead_holdtype='C'
        FROM coitem
        WHERE ( (coitem_cohead_id=cohead_id)
         AND (cohead_holdtype='N')
         AND (coitem_status='O')
         AND (cohead_cust_id=_p.cust_id) );
      END IF;

    END IF;

  END IF;

  RETURN NEW;

END;
$$
 LANGUAGE 'plpgsql';

DROP TRIGGER aropenTrigger ON aropen;
CREATE TRIGGER aropenTrigger BEFORE INSERT OR UPDATE ON aropen FOR EACH ROW EXECUTE PROCEDURE _aropenTrigger();

CREATE OR REPLACE FUNCTION _aropenAfterTrigger() RETURNS TRIGGER AS $$
DECLARE
  _openAmount NUMERIC;
  _p RECORD;
  _lateCount INTEGER := 0;
  _graceDays INTEGER;
  _checkLate BOOLEAN := false;
  _checkLimit BOOLEAN := false;
  _id INTEGER;
BEGIN

-- If metric is set then auto close any associated incidents when AR is closed
  IF (fetchMetricBool('AutoCloseARIncident')) THEN
    IF (NEW.aropen_open = FALSE) THEN
      UPDATE incdt SET incdt_status='L' WHERE (incdt_aropen_id=OLD.aropen_id);
    END IF;
  END IF;

  RETURN NEW;

END;
$$
 LANGUAGE 'plpgsql';

SELECT dropIfExists('TRIGGER', 'aropenAfterTrigger');
CREATE TRIGGER aropenAfterTrigger AFTER INSERT OR UPDATE ON aropen FOR EACH ROW EXECUTE PROCEDURE _aropenAfterTrigger();

