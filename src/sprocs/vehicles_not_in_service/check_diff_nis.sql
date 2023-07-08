/*

Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-09-25

Description:

For two tables with the names passed through
the parameters in_t1 and in_t2 respectively and
the column structures matching that of 
vehicles_not_in_service, the procedure checks
whether:
	a. 	the tables exist and 
	b. 	the datasets contained in the tables
		are identical.
 
The OUT parameter diff_flag_result is set to: 
	1 if both of the conditions are met; 
	0 otherwise.

*/

DROP PROCEDURE IF EXISTS check_diff_nis;
DELIMITER $$
CREATE PROCEDURE check_diff_nis(
	  IN in_t1 VARCHAR(64)
	, IN in_t2 VARCHAR(64)
	, OUT diff_flag_result BOOLEAN
)
	SQL SECURITY DEFINER
	READS SQL DATA
	COMMENT 'Checks whether the datasets
    in two vehicles_not_in_service-type tables 
	are identical'
	
BEGIN
	
	DECLARE errno INT;
	DECLARE msg VARCHAR(255);
	DECLARE EXIT HANDLER FOR SQLEXCEPTION
	BEGIN
		GET CURRENT DIAGNOSTICS CONDITION 1
	    errno = MYSQL_ERRNO , msg = MESSAGE_TEXT;
	    SELECT CONCAT(
	    	  'Error executing check_diff_nis: '
			, errno
	    	, " - "
	    	, msg
	    ) AS "Error message";
	END;
	
	/* 
		Create tables tbs_nis, id_cols_nis and 
		dat_cols_nis required for using 
		the compare_variants stored procedure 
		and insert the necessary data into them
	*/

	DROP TEMPORARY TABLE IF EXISTS tbs_nis;
	CREATE TEMPORARY TABLE tbs_nis (
		  id INT AUTO_INCREMENT UNIQUE
		, table_name VARCHAR(64)
	);


	SET @ins_tbs = CONCAT(
		'INSERT INTO tbs_nis (table_name)
			VALUES 
		  		  (\'', in_t1,'\')
				, (\'', in_t2, '\');'
	);

	PREPARE ins_tbs FROM @ins_tbs;
	EXECUTE ins_tbs;
	DEALLOCATE PREPARE ins_tbs;
	SET @ins_tbs = NULL;

	DROP TEMPORARY TABLE IF EXISTS id_cols_nis;
	CREATE TEMPORARY TABLE id_cols_nis (
		  id INT AUTO_INCREMENT UNIQUE
		, col_name VARCHAR(64)
	);
	INSERT INTO id_cols_nis (col_name)
	VALUES 
		  ('id')
	;

	DROP TEMPORARY TABLE IF EXISTS dat_cols_nis;
	CREATE TEMPORARY TABLE dat_cols_nis (
		  id INT AUTO_INCREMENT UNIQUE
		, col_name VARCHAR(64)
	);
	INSERT INTO dat_cols_nis (col_name)
	VALUES 
		  ('vehicle_id')
		, ('nis_beginning')
		, ('nis_end')
	;


	/* 
		Use compare_variants() and a selection
		query dfr to check whether the tables
		in_t1 and in_t2
		contain identical datasets 
	*/

	DROP TEMPORARY TABLE IF EXISTS nis_cf;
	CALL compare_variants(
		  'tbs_nis'
		, 'id_cols_nis'
		, 'dat_cols_nis'
		, 'nis_cf'
	);


	SET @tmp_nis = 0;
	SET diff_flag_result = @tmp_nis;

	SET @dfr = CONCAT(
		'SELECT 1 WHERE NOT EXISTS(
			SELECT * FROM nis_cf
			WHERE 
				', in_t1, '_vehicle_id IS NULL
				OR 
				', in_t2, '_vehicle_id IS NULL
		)
		INTO  @tmp_nis;'
	);

	PREPARE dfr FROM @dfr;
	EXECUTE dfr;
	DEALLOCATE PREPARE dfr;
	SET @dfr = NULL;

	SET diff_flag_result = @tmp_nis;
	SET @tmp_nis = NULL;

END$$
DELIMITER ;
