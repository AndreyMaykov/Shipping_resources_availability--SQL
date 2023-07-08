/*

Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-09-25

Description:

For two tables with the names passed through
the parameters in_t1 and in_t2 respectively and
the column structures matching that of 
blocked_periods, the procedure checks
whether:
	a. 	the tables exist and 
	b. 	the datasets contained in the tables
		are identical.
 
The OUT parameter diff_flag_result is set to: 
	1 if both of the conditions are met; 
	0 otherwise.

*/ 

DROP PROCEDURE IF EXISTS check_diff_bp;
DELIMITER $$
CREATE PROCEDURE check_diff_bp(
	  IN in_t1 VARCHAR(64)
	, IN in_t2 VARCHAR(64)
	, OUT diff_flag_result BOOLEAN
)
	SQL SECURITY DEFINER
	READS SQL DATA
	COMMENT 'Checks whether the datasets
    in two blocked_periods-type tables 
	are identical'
	
BEGIN
	
	DECLARE errno INT;
	DECLARE msg VARCHAR(255);
	DECLARE EXIT HANDLER FOR SQLEXCEPTION
	BEGIN
		GET CURRENT DIAGNOSTICS CONDITION 1
	    errno = MYSQL_ERRNO , msg = MESSAGE_TEXT;
	    SELECT CONCAT(
	    	  'Error executing check_diff_bp: '
			, errno
	    	, " - "
	    	, msg
	    ) AS "Error message";
	END;
	
	/* 
		Create tables tbs_bp, id_cols_bp and 
		dat_cols_bp required for using 
		the compare_variants stored procedure 
		and insert the necessary data into them
	*/

	DROP TEMPORARY TABLE IF EXISTS tbs_bp;
	CREATE TEMPORARY TABLE tbs_bp (
		  id INT AUTO_INCREMENT UNIQUE
		, table_name VARCHAR(64)
	);


	SET @ins_tbs = CONCAT(
		'INSERT INTO tbs_bp (table_name)
			VALUES 
		  		  (\'', in_t1,'\')
				, (\'', in_t2, '\');'
	);

	PREPARE ins_tbs FROM @ins_tbs;
	EXECUTE ins_tbs;
	DEALLOCATE PREPARE ins_tbs;
	SET @ins_tbs = NULL;

	DROP TEMPORARY TABLE IF EXISTS id_cols_bp;
	CREATE TEMPORARY TABLE id_cols_bp (
		  id INT AUTO_INCREMENT UNIQUE
		, col_name VARCHAR(64)
	);
	INSERT INTO id_cols_bp (col_name)
	VALUES 
		  ('id')
	;

	DROP TEMPORARY TABLE IF EXISTS dat_cols_bp;
	CREATE TEMPORARY TABLE dat_cols_bp (
		  id INT AUTO_INCREMENT UNIQUE
		, col_name VARCHAR(64)
	);
	INSERT INTO dat_cols_bp (col_name)
	VALUES 
		  ('user_id')
		, ('period_beginning')
		, ('period_end')
	;


	/* 
		Use compare_variants() and a selection
		query dfr to check whether the tables
		in_t1 and in_t2
		contain identical datasets 
	*/

	DROP TEMPORARY TABLE IF EXISTS bp_cf;
	CALL compare_variants(
		  'tbs_bp'
		, 'id_cols_bp'
		, 'dat_cols_bp'
		, 'bp_cf'
	);


	SET @tmp_bp = 0;
	SET diff_flag_result = @tmp_bp;

	SET @dfr = CONCAT(
		'SELECT 1 WHERE NOT EXISTS(
			SELECT * FROM bp_cf
			WHERE 
				', in_t1, '_user_id IS NULL
				OR 
				', in_t2, '_user_id IS NULL
		)
		INTO  @tmp_bp;'
	);

	PREPARE dfr FROM @dfr;
	EXECUTE dfr;
	DEALLOCATE PREPARE dfr;
	SET @dfr = NULL;

	SET diff_flag_result = @tmp_bp;
	SET @tmp_bp = NULL;

END$$
DELIMITER ;
