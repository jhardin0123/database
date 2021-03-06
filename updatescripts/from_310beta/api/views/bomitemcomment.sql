BEGIN;

-- Bill of Material Item Comment

DROP VIEW api.bomitemcomment;
CREATE VIEW api.bomitemcomment
AS 
   SELECT 
     item_number::varchar(100) AS bom_item_number,
     bomhead_revision::varchar(100) AS bom_revision,
     bomitem_seqnumber AS sequence_number,
     cmnttype_name AS type,
     comment_date AS date,
     comment_user AS username,
     comment_text AS text
   FROM bomitem
     LEFT OUTER JOIN bomhead ON ((bomitem_parent_item_id=bomhead_item_id) 
                             AND (bomitem_rev_id=bomhead_rev_id)),
     item, cmnttype, comment
   WHERE ((comment_source='BMI')
   AND (comment_source_id=bomitem_id)
   AND (comment_cmnttype_id=cmnttype_id)
   AND (bomitem_parent_item_id=item_id));

GRANT ALL ON TABLE api.bomitemcomment TO openmfg;
COMMENT ON VIEW api.bomitemcomment IS 'Bill of Material Comment';

--Rules

CREATE OR REPLACE RULE "_INSERT" AS
    ON INSERT TO api.bomitemcomment DO INSTEAD

  INSERT INTO comment (
    comment_date,
    comment_source,
    comment_source_id,
    comment_user,
    comment_cmnttype_id,
    comment_text
    )
  VALUES (
    COALESCE(NEW.date,now()),
    'BMI',
    getBomItemId(NEW.bom_item_number::text,NEW.bom_revision::text,NEW.sequence_number::text),
    COALESCE(NEW.username,current_user),
    getCmntTypeId(NEW.type),
    NEW.text);

CREATE OR REPLACE RULE "_UPDATE" AS
    ON UPDATE TO api.bomitemcomment DO INSTEAD NOTHING;

CREATE OR REPLACE RULE "_DELETE" AS
    ON DELETE TO api.bomitemcomment DO INSTEAD NOTHING;

COMMIT;