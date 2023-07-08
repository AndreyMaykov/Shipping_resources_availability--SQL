/*

Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-09-30

Description:
 
Defines a mapping between the names of original
tables and the coreesponding suffixes (<sfx>) used in the names
of their snapshots (<sfx>_snp) and modification variants (<sfx>_mod)
For example, staff_regular_availability is assigned the suffix sra,
which gives sra_snp and sra_mod.

*/

DROP PROCEDURE IF EXISTS set_sfx;
DELIMITER $$
CREATE PROCEDURE set_sfx()
	SQL SECURITY DEFINER
	READS SQL DATA
	COMMENT 'Defines suffixes used for snapshots and
	modification variants of original tables'
	
sp: BEGIN
	
		DECLARE errno INT;
		DECLARE msg VARCHAR(255);
		DECLARE EXIT HANDLER FOR SQLEXCEPTION
		BEGIN
			GET CURRENT DIAGNOSTICS CONDITION 1
			errno = MYSQL_ERRNO, msg = MESSAGE_TEXT;
			SELECT CONCAT(
				  'Error executing set_sfx: '
				, errno
				, " - "
				, msg
			) AS "Error message";
		END;
		
		
		CALL check_tb_tmp('sfx_tb', @cont_flag_1);
		IF 
		@cont_flag_1 = 0
		THEN
			CREATE TEMPORARY TABLE IF NOT EXISTS sfx_tb (
				  id INT AUTO_INCREMENT UNIQUE
				, tb_name VARCHAR(64) UNIQUE
				, sfx VARCHAR(32)	UNIQUE
		    ); 
			INSERT INTO sfx_tb (tb_name, sfx)
			VALUES
				  ('staff_regular_availability', 'sra')
				, ('blocked_periods', 'bp')
				, ('wave_timings', 'wt')
				, ('vehicles_not_in_service', 'nis')
				, ('wave_available_staff', 'ws')
				, ('ws_detailed', 'wsd')
				, ('wave_available_vehicles', 'wv')
				, ('wv_detailed', 'wvd')
			;
		END IF;

END$$
DELIMITER ;						
														