/*

Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-09-23

Description:
 
Creates, executes and deallocates a prepared statement 
using the string literal -- the value of a variable --
passed through the parameter in_ps_string.

*/

DROP PROCEDURE IF EXISTS exec_ps;
DELIMITER $$
CREATE PROCEDURE exec_ps(
	IN in_ps_string VARCHAR(4000)
)
	SQL SECURITY INVOKER
	READS SQL DATA
	COMMENT 'Creates, executes and deallocates 
	a prepared statement'
BEGIN
	
		DECLARE errno INT;
		DECLARE msg VARCHAR(255);
		DECLARE EXIT HANDLER FOR SQLEXCEPTION
		BEGIN
			GET CURRENT DIAGNOSTICS CONDITION 1
			errno = MYSQL_ERRNO, msg = MESSAGE_TEXT;
			SELECT CONCAT(
				  'Error executing exec_ps: '
				, errno
				, " - "
				, msg
			) AS "Error message";
		END;
		
			SELECT in_ps_string INTO @ps;
				PREPARE ps FROM @ps;
				EXECUTE ps;
				DEALLOCATE PREPARE ps;
				-- SET @ps = NULL;

END$$
DELIMITER ;