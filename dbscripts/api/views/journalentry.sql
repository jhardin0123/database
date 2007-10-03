BEGIN;

-- Simple Journal Entry
DROP VIEW api.journalentry;
CREATE VIEW api.journalentry
AS 
   SELECT  
     curr_abbr AS currency,
     d.gltrans_amount AS amount,
     d.gltrans_date as dist_date,
     d.gltrans_docnumber as doc_number,
     formatglaccount(da.accnt_id) AS debit,
     formatglaccount(ca.accnt_id) AS credit,
     d.gltrans_notes AS notes
   FROM gltrans d, gltrans c, accnt da, accnt ca, curr_symbol
   WHERE ((d.gltrans_sequence=c.gltrans_sequence)
   AND (d.gltrans_accnt_id=da.accnt_id)
   AND (c.gltrans_accnt_id=ca.accnt_id)
   AND (d.gltrans_amount < 0)
   AND (c.gltrans_amount > 0)
   AND (d.gltrans_doctype='JE')
   AND (c.gltrans_doctype='JE')
   AND (curr_id=basecurrid()))
   ORDER BY d.gltrans_date DESC;

GRANT ALL ON TABLE api.journalentry TO openmfg;
COMMENT ON VIEW api.journalentry IS '
This view can be used as an interface to import Journal Entry data directly  
into the system.  Required fields will be checked and default values will be 
populated';

--Rules

CREATE OR REPLACE RULE "_INSERT" AS
    ON INSERT TO api.journalentry DO INSTEAD

SELECT insertGLTransaction( 
     'G/L'::text,
     'JE'::text, 
     NEW.doc_number, 
     NEW.notes,
     getGlAccntId(NEW.credit),
     getGlAccntId(NEW.debit),
     -1,
     currtobase(getCurrId(NEW.currency),NEW.amount,NEW.dist_date),
     NEW.dist_date 
     );

CREATE OR REPLACE RULE "_UPDATE" AS 
    ON UPDATE TO api.journalentry DO INSTEAD

  NOTHING;
           
CREATE OR REPLACE RULE "_DELETE" AS 
    ON DELETE TO api.journalentry DO INSTEAD

  NOTHING;

COMMIT;
