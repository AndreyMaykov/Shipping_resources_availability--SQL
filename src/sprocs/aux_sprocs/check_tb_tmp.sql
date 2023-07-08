/*

Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-09-26

Description:
 
For a temporary table with the name passed through the parameter tb_name, 
this procedure checks whether the table exists.

*/


DROP PROCEDURE IF EXISTS check_tb_tmp;
DELIMITER $$
CREATE PROCEDURE check_tb_tmp(
	  IN tb_name VARCHAR(64)
	, OUT chk_result BOOLEAN
)
	SQL SECURITY DEFINER
	MODIFIES SQL DATA
	COMMENT 'Checks whether a temp table with the name
	tb_name exists'
	
sp: BEGIN

		DECLARE errno INT;
		DECLARE msg VARCHAR(255);
		DECLARE EXIT HANDLER FOR SQLEXCEPTION
		BEGIN
			GET CURRENT DIAGNOSTICS CONDITION 1
			errno = MYSQL_ERRNO , msg = MESSAGE_TEXT;
			SELECT CONCAT(
				  'Error executing check_tb_tmp: '
				, errno
				, " - "
				, msg
			) AS "Error message";
		END;
	
	
		SET @check_extg = CONCAT(
			  'CALL sys.table_exists(DATABASE(), \'' 
			, tb_name
			, '\', @tb_exists);'
		); 
	
		PREPARE check_extg FROM @check_extg;
		EXECUTE check_extg;
		DEALLOCATE PREPARE check_extg;
		
		SET chk_result = IF (@tb_exists = 'TEMPORARY', 1, 0);
	
END$$
DELIMITER ;

