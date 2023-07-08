/*

Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-09-27

Description:
 
For the table with the name passed through the parameter tb_orig, 
this procedure:
 
	creates a temporary table -- a copy of tb_orig -- 
	with the name passed through the parameter tb_copy
	if no temporary table with the name tb_copy exists;
	
	replaces the temporary table tb_copy (provided it
	exists) by a copy of tb_orig if repl_extg = 1;
	
	makes no changes if the temporary table tb_copy exists 
	and repl_extg = 0.

*/


DROP PROCEDURE IF EXISTS copy_tb_tmp;
DELIMITER $$
CREATE PROCEDURE copy_tb_tmp(
	  IN tb_orig VARCHAR(64)
	, IN repl_extg BOOLEAN 
	, IN tb_copy VARCHAR(64)
)
	SQL SECURITY INVOKER
	MODIFIES SQL DATA
	COMMENT 'Creates a copy of a table (conditions apply)'
	
sp: BEGIN

		DECLARE errno INT;
		DECLARE msg VARCHAR(255);
		DECLARE EXIT HANDLER FOR SQLEXCEPTION
		BEGIN
			GET CURRENT DIAGNOSTICS CONDITION 1
			errno = MYSQL_ERRNO , msg = MESSAGE_TEXT;
			SELECT CONCAT(
				  'Error executing copy_tb_tmp: '
				, errno
				, " - "
				, msg
			) AS "Error message";
		END;
	
		IF tb_orig = tb_copy THEN 
			LEAVE sp; 
		END IF;
	
		SET @check_extg = CONCAT(
			  'CALL sys.table_exists(DATABASE(), \'' 
			, tb_copy
			, '\', @tb_copy_exists);'
		); 
	
		PREPARE check_extg FROM @check_extg;
		EXECUTE check_extg;
		DEALLOCATE PREPARE check_extg;
		
		IF @tb_copy_exists = 'TEMPORARY' THEN
	
			IF repl_extg = 1 THEN
				SET @drop_tb_copy = CONCAT(
					  'DROP TEMPORARY TABLE IF EXISTS '
					, tb_copy
					, ';'
				);
			
				PREPARE drop_tb_copy FROM @drop_tb_copy;
				EXECUTE drop_tb_copy;
				DEALLOCATE PREPARE drop_tb_copy;
			ELSE LEAVE sp;
			END IF;
		
		END IF;
	
		SET @create_tb_copy = CONCAT(
			  'CREATE TEMPORARY TABLE '  
			, tb_copy
			, ' AS SELECT * FROM '
			, tb_orig
		);

		PREPARE create_tb_copy FROM @create_tb_copy;
		EXECUTE create_tb_copy;
		DEALLOCATE PREPARE create_tb_copy; 

END$$
DELIMITER ;