
/*
Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-09-30

Description:

Based on the table with the name passed through
the parameter in_nis_mod, this procedure changes both 
vehicles_not_in_service3 and nis_snp so that the datasets 
of the columns (vehicle_id, nis_beginning, nis_end)
contained in the three tables become identical.

Note. The procedure does not save the dataset contained 
in vehicles_no_in_service/nis_snp; to save, 
use a separate procedure (e.g. copy_tb_tmp) 
before change_nis.
		
*/

DROP PROCEDURE IF EXISTS change_nis;
DELIMITER $$
CREATE PROCEDURE change_nis(
	IN in_nis_mod VARCHAR(64)
)
sp: BEGIN
	
		DECLARE errno INT;
		DECLARE msg VARCHAR(255);
		DECLARE EXIT HANDLER FOR SQLEXCEPTION
		BEGIN
			GET CURRENT DIAGNOSTICS CONDITION 1
			errno = MYSQL_ERRNO, msg = MESSAGE_TEXT;
			SELECT CONCAT(
				  'Error executing change_nis(): '
				, errno
				, " - "
				, msg
			) AS "Error message";
		ROLLBACK;
		END;

	/*
		Verify whether changes based on in_nis_mod 
		can be made to vehicles_not_in_service; 
		if not, explain the reasons to the user
	*/
	
	CALL check_tb_tmp('nis_snp', @cont_flag_1);
		IF 
		@cont_flag_1 = 0
	THEN
		SELECT 'No changes to vehicles_not_in_service suggested in this session';
		LEAVE sp; 
	END IF;
	
	SET @cf2 = CONCAT(
		'CALL check_diff_nis(
			\'', in_nis_mod, '\', \'nis_snp\', @cont_flag_2
		 );'
	);
	PREPARE cf2 FROM @cf2;
	EXECUTE cf2;
	DEALLOCATE PREPARE cf2;
	SET @cf2 = 0;
	
	IF 
		@cont_flag_2 = 1
	THEN
		SELECT CONCAT(
			  'No changes to vehicles_not_in_service suggested by '
			, in_nis_mod
		);
		LEAVE sp; 
	END IF;
	
	CALL check_diff_nis('vehicles_not_in_service', 'nis_snp', @cont_flag);
	
	IF @cont_flag = 0 THEN 
		SELECT 'Data in vehicles_not_in_service has been changed by another user';
		LEAVE sp; 
	END IF;
	
	
	/* If the previous test passed successfully, make the changes */
	
	START TRANSACTION;
		
		/* 
			Delete from vehicles_not_in_service and nis_snp
			rows not contained in in_nis_mod 
		*/
		SET @del_nis_snp_nis = CONCAT(
			'DELETE nis_snp, nis FROM nis_snp 
			 INNER JOIN vehicles_not_in_service AS nis
			 ON 
				 nis_snp.vehicle_id = nis.vehicle_id
				 AND 
				 nis_snp.nis_beginning = nis.nis_beginning
				 AND 
				 nis_snp.nis_end = nis.nis_end
			 LEFT JOIN ', in_nis_mod, '
			 ON
				 nis.vehicle_id = ', in_nis_mod,'.vehicle_id
				 AND 
				 nis.nis_beginning = ', in_nis_mod, '.nis_beginning
				 AND 
				 nis.nis_end = ', in_nis_mod, '.nis_end
			 WHERE ', in_nis_mod, '.vehicle_id IS NULL
			 ;'
		);
		
		/* 
			Delete from in_nis_mod the rows not contained 
			in vehicles_not_in_service/nis_snp
		*/
		SET @del_nis_mod = CONCAT(
			'DELETE ', in_nis_mod, ' FROM vehicles_not_in_service AS nis 
			 LEFT JOIN ', in_nis_mod, '
			 ON 
				 nis.vehicle_id = ', in_nis_mod,'.vehicle_id
				 AND 
				 nis.nis_beginning = ', in_nis_mod, '.nis_beginning
				 AND 
				 nis.nis_end = ', in_nis_mod, '.nis_end
			 ;'
		);
		
		SET @ins_1 = 'INSERT IGNORE INTO ';
		SET @ins_2 = '  (
				  vehicle_id
				, nis_beginning
				, nis_end
			 ) 
			 SELECT  
				  vehicle_id
				, nis_beginning
				, nis_end
			 FROM ';
			 
		/* 
			Insert into vehicles_not_in_service
			the rest of the rows of in_nis_mod 
		*/
		SET @ins_nis = CONCAT(
				@ins_1
				, 'vehicles_not_in_service'
				, @ins_2
				, in_nis_mod
				, ';'
		);
		
		/* 
			Insert into nis_snp
			the rest of the rows of in_nis_mod 
		*/
		SET @ins_nis_snp = CONCAT(
				@ins_1
				, 'nis_snp'
				, @ins_2
				, in_nis_mod
				, ';'
		);

		SET @d_nis_mod = CONCAT(
			'DROP TEMPORARY TABLE ', in_nis_mod, ';'
		);

		PREPARE del_nis_snp_nis FROM @del_nis_snp_nis;
		EXECUTE del_nis_snp_nis;
		DEALLOCATE PREPARE del_nis_snp_nis;
		SET @del_nis_snp_nis = NULL;
		
		PREPARE del_nis_mod FROM @del_nis_mod;
		EXECUTE del_nis_mod;
		DEALLOCATE PREPARE del_nis_mod;
		SET @del_nis_mod = NULL;
		
		PREPARE ins_nis FROM @ins_nis;
		EXECUTE ins_nis;
		DEALLOCATE PREPARE ins_nis;
		SET @ins_nis = NULL;
		
		PREPARE ins_nis_snp FROM @ins_nis_snp;
		EXECUTE ins_nis_snp;
		DEALLOCATE PREPARE ins_nis_snp;
		SET @ins_nis_snp = NULL;
		
		SET @ins_1 = NULL;
		SET @ins_2 = NULL;
		
		PREPARE d_nis_mod FROM @d_nis_mod;
		EXECUTE d_nis_mod;
		DEALLOCATE PREPARE d_nis_mod;
		SET @d_nis_mod = NULL;
		
	COMMIT;

END$$
DELIMITER ;