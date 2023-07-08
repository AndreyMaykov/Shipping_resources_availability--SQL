/*

Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-10-12

Description:
 
For data contained in tables t_k (k = 1, ... , kmax)
whose structure is identical to that of vehicles_not_in_service,
this procedure creates a comparison table. 

Note: the actual names of the tables and columns here are passed 
to the procedure and thus can be any valid table/column names.

For each k, all the data originating in the same row of t_k
are inserted in a single row of the comparison table.

In the comparison table, the data is organized as follows:
- the values retrieved from the columns vehicle_id_k (k = 1, ..., kmax)
are gathered in the comparison table's column with the name vehicle_id;
- the values retrieved from the columns nis_beginning_k and nis_end_k 
are inserted in separate columns t_k_nis_beginning and t_k_nis_end 
of the comparison table.

*/

DROP PROCEDURE IF EXISTS cmpr_variants_nis;
DELIMITER $$
CREATE PROCEDURE cmpr_variants_nis(
	-- The tables to be compared:
	  IN in_tbs_to_compare VARCHAR(64)
	-- The name of the resulting comparison table:
	, IN foj_result VARCHAR(64)
)
	SQL SECURITY INVOKER
	READS SQL DATA
	COMMENT 'Compares variants of vehicles_not_in_service'

BEGIN
	
	DECLARE errno INT;
	DECLARE msg VARCHAR(255);
	DECLARE EXIT HANDLER FOR SQLEXCEPTION
	BEGIN
		GET CURRENT DIAGNOSTICS CONDITION 1
	    errno = MYSQL_ERRNO , msg = MESSAGE_TEXT;
	    SELECT CONCAT(
	    	  'Error executing cmpr_variants_nis(): '
			, errno
	    	, " - "
	    	, msg
	    ) AS "Error message";
	END;

	DROP TEMPORARY TABLE IF EXISTS id_cols_nis;
	CREATE TEMPORARY TABLE id_cols_nis (
		id INT,
		col_name VARCHAR(64)
	);
	INSERT INTO id_cols_nis 
	VALUES 
		  (1, 'vehicle_id')
	;

	DROP TEMPORARY TABLE IF EXISTS dat_cols_nis;
	CREATE TEMPORARY TABLE dat_cols_nis (
		id INT,
		col_name VARCHAR(64)
	);
	INSERT INTO dat_cols_nis 
	VALUES 
		  (1, 'nis_beginning')
		, (2, 'nis_end')
	;
	
	CALL compare_variants(
		  in_tbs_to_compare
		, 'id_cols_nis'
		, 'dat_cols_nis'
		, foj_result
	);

END$$
DELIMITER ;