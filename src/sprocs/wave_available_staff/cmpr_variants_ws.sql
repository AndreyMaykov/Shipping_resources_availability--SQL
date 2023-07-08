/*

Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-10-15

Description:
 
For data contained in tables t_k (k = 1, ... , kmax)
whose structure is identical to that of wave_available_staff,
this procedure creates a comparison table. 

Note: the actual names of the tables and columns here are passed 
to the procedure and thus can be any valid table/column names.

For each k, all the data originating in the same row of t_k
are inserted in a single row of the comparison table.

In the comparison table, the data is organized as follows:
- the values retrieved from the columns wave_id_k (k = 1, ..., kmax)
are gathered in the comparison table's column with the name wave_id;
- the values retrieved from the columns user_id_k
are inserted in separate columns t_k_user_id of the comparison table.

*/

DROP PROCEDURE IF EXISTS cmpr_variants_ws;
DELIMITER $$
CREATE PROCEDURE cmpr_variants_ws(
	-- The tables to be compared:
	  IN in_tbs_to_compare VARCHAR(64)
	-- The name of the resulting comparison table:
	, IN foj_result VARCHAR(64)
)
	SQL SECURITY INVOKER
	READS SQL DATA
	COMMENT 'Compares variants of wave_available_staff'

BEGIN
	
	DECLARE errno INT;
	DECLARE msg VARCHAR(255);
	DECLARE EXIT HANDLER FOR SQLEXCEPTION
	BEGIN
		GET CURRENT DIAGNOSTICS CONDITION 1
	    errno = MYSQL_ERRNO , msg = MESSAGE_TEXT;
	    SELECT CONCAT(
	    	  'Error executing cmpr_variants_ws(): '
			, errno
	    	, " - "
	    	, msg
	    ) AS "Error message";
	END;

	DROP TEMPORARY TABLE IF EXISTS id_cols_ws;
	CREATE TEMPORARY TABLE id_cols_ws (
		id INT,
		col_name VARCHAR(64)
	);
	INSERT INTO id_cols_ws 
	VALUES 
		  (1, 'wave_id')
	;

	DROP TEMPORARY TABLE IF EXISTS dat_cols_ws;
	CREATE TEMPORARY TABLE dat_cols_ws (
		id INT,
		col_name VARCHAR(64)
	);
	INSERT INTO dat_cols_ws 
	VALUES 
		  (1, 'user_id')
	;
	
	CALL compare_variants(
		  in_tbs_to_compare
		, 'id_cols_ws'
		, 'dat_cols_ws'
		, foj_result
	);

END$$
DELIMITER ;