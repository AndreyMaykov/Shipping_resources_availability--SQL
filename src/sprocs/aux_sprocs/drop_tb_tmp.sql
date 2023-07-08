/*

Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-09-20

Description:
 
Drops the temporary table whose names is
passed through the parameter in_tb_name.

*/


DROP PROCEDURE IF EXISTS drop_tb_tmp;

DELIMITER $$
CREATE PROCEDURE drop_tb_tmp(IN in_tb_name VARCHAR(64))
BEGIN
	
	SET @dtt = CONCAT(
		  'DROP TEMPORARY TABLE IF EXISTS '
		, in_tb_name
		, ';'
	);

	PREPARE dtt FROM @dtt;
	EXECUTE dtt;
	DEALLOCATE PREPARE dtt;
END $$
DELIMITER ;