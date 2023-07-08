/*

Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-09-25

Description:

For two tables with the names passed through
the parameters in_t1 and in_t2 respectively and
the column structures matching that of 
staff_regular_availability, the procedure checks
whether:
	a. 	the tables exist and 
	b. 	the datasets contained in the tables
		are identical.
 
The OUT parameter diff_flag_result is set to: 
	1 if both of the conditions are met; 
	0 otherwise.

*/

DROP PROCEDURE IF EXISTS check_diff_sra;
DELIMITER $$
CREATE PROCEDURE check_diff_sra(
	  IN in_t1 VARCHAR(64)
	, IN in_t2 VARCHAR(64)
	, OUT diff_flag_result BOOLEAN
)
	SQL SECURITY DEFINER
	READS SQL DATA
	COMMENT 'Checks whether the datasets
    in two staff_regular_availability-type
	tables are identical'
	
BEGIN
	
	DECLARE errno INT;
	DECLARE msg VARCHAR(255);
	DECLARE EXIT HANDLER FOR SQLEXCEPTION
	BEGIN
		GET CURRENT DIAGNOSTICS CONDITION 1
	    errno = MYSQL_ERRNO , msg = MESSAGE_TEXT;
	    SELECT CONCAT(
	    	  'Error executing check_diff_sra: '
			, errno
	    	, " - "
	    	, msg
	    ) AS "Error message";
	END;
	
	/* 
		Create tables tbs_sra, id_cols_sra and 
		dat_cols_sra required for using 
		the compare_variants stored procedure 
		and insert the necessary data into them
	*/

	DROP TEMPORARY TABLE IF EXISTS tbs_sra;
	CREATE TEMPORARY TABLE tbs_sra (
		  id INT AUTO_INCREMENT UNIQUE
		, table_name VARCHAR(64)
	);


	SET @ins_tbs = CONCAT(
		'INSERT INTO tbs_sra (table_name)
			VALUES 
		  		  (\'', in_t1,'\')
				, (\'', in_t2, '\');'
	);

	PREPARE ins_tbs FROM @ins_tbs;
	EXECUTE ins_tbs;
	DEALLOCATE PREPARE ins_tbs;
	SET @ins_tbs = NULL;

	DROP TEMPORARY TABLE IF EXISTS id_cols_sra;
	CREATE TEMPORARY TABLE id_cols_sra (
		  id INT AUTO_INCREMENT UNIQUE
		, col_name VARCHAR(64)
	);
	INSERT INTO id_cols_sra (col_name)
	VALUES 
		  ('id')
	;

	DROP TEMPORARY TABLE IF EXISTS dat_cols_sra;
	CREATE TEMPORARY TABLE dat_cols_sra (
		  id INT AUTO_INCREMENT UNIQUE
		, col_name VARCHAR(64)
	);
	INSERT INTO dat_cols_sra (col_name)
	VALUES 
		  ('user_id')
		, ('wday')
		, ('interval_beginning')
		, ('interval_end')
	;

	/* 
		Use compare_variants() and a selection
		query dfr to check whether the tables
		in_t1 and in_t2
		contain identical datasets 
	*/
	DROP TEMPORARY TABLE IF EXISTS sra_cf;
	CALL compare_variants(
		  'tbs_sra'
		, 'id_cols_sra'
		, 'dat_cols_sra'
		, 'sra_cf'
	);


	SET @tmp_sra = 0;
	SET diff_flag_result = @tmp_sra;

	SET @dfr = CONCAT(
		'SELECT 1 WHERE NOT EXISTS(
			SELECT * FROM sra_cf
			WHERE 
				', in_t1, '_wday IS NULL
				OR 
				', in_t2, '_wday IS NULL
		)
		INTO  @tmp_sra;'
	);
	PREPARE dfr FROM @dfr;
	EXECUTE dfr;
	DEALLOCATE PREPARE dfr;
	SET @dfr = NULL;

	SET diff_flag_result = @tmp_sra;
	SET @tmp_sra = NULL;

END$$
DELIMITER ;