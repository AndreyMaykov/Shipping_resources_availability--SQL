
/*
Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-09-29

Description:

Based on the table with the name passed through
the parameter in_sra_mod, this procedure changes both 
staff_regular_availability and sra_snp so that the datasets 
of (user_id, wday, interval_beginning, interval_end)
contained in the three tables become identical.

Note. The procedure does not save the dataset contained 
in staff_regular availability/sra_snp; to save, 
use a separate procedure (e.g. copy_tb_tmp) 
before change_sra.
		
*/

DROP PROCEDURE IF EXISTS change_sra;
DELIMITER $$
CREATE PROCEDURE change_sra(
	IN in_sra_mod VARCHAR(64)
)
sp: BEGIN
	
		DECLARE errno INT;
		DECLARE msg VARCHAR(255);
		DECLARE EXIT HANDLER FOR SQLEXCEPTION
		BEGIN
			GET CURRENT DIAGNOSTICS CONDITION 1
			errno = MYSQL_ERRNO, msg = MESSAGE_TEXT;
			SELECT CONCAT(
				  'Error executing change_sra: '
				, errno
				, " - "
				, msg
			) AS "Error message";
		ROLLBACK;
		END;

	/*
		Verify whether changes based on in_sra_mod 
		can be made to staff_regular_availability; 
		if not, explain the reasons to the user
	*/
	
	CALL check_tb_tmp('sra_snp', @cont_flag_1);
		IF 
		@cont_flag_1 = 0
	THEN
		SELECT 'No changes to staff_regular_availability suggested in this session';
		LEAVE sp; 
	END IF;
	
	SET @cf2 = CONCAT(
		'CALL check_diff_sra(
			\'', in_sra_mod, '\', \'sra_snp\', @cont_flag_2
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
			  'No changes to staff_regular_availability suggested by '
			, in_sra_mod
		);
		LEAVE sp; 
	END IF;
	
	CALL check_diff_sra('staff_regular_availability', 'sra_snp', @cont_flag);
	
	IF @cont_flag = 0 THEN 
		SELECT 'Data in staff_regular_availability has been changed by another user';
		LEAVE sp; 
	END IF;
	
	
	/* If the previous test passed successfully, make the changes */
	
	START TRANSACTION;
		
		/* 
			Delete from staff_regular_availability and sra_snp
			rows not contained in in_sra_mod 
		*/
		SET @del_sra_snp_sra = CONCAT(
			'DELETE sra_snp, sra FROM sra_snp 
			 INNER JOIN staff_regular_availability AS sra
			 ON 
				 sra_snp.user_id = sra.user_id
				 AND 
				 sra_snp.wday = sra.wday
				 AND 
				 sra_snp.interval_beginning = sra.interval_beginning
				 AND 
				 sra_snp.interval_end = sra.interval_end
			 LEFT JOIN ', in_sra_mod, '
			 ON
				 sra.user_id = ', in_sra_mod,'.user_id
				 AND 
				 sra.wday = ', in_sra_mod,'.wday
				 AND 
				 sra.interval_beginning = ', in_sra_mod, '.interval_beginning
				 AND 
				 sra.interval_end = ', in_sra_mod, '.interval_end
			 WHERE ', in_sra_mod, '.user_id IS NULL
			 ;'
		);
		
		/* 
			Delete from in_sra_mod the rows not contained 
			in staff_regular_availability/sra_snp
		*/
		SET @del_sra_mod = CONCAT(
			'DELETE ', in_sra_mod, ' FROM staff_regular_availability AS sra 
			 LEFT JOIN ', in_sra_mod, '
			 ON 
				 sra.user_id = ', in_sra_mod,'.user_id
				 AND 
				 sra.wday = ', in_sra_mod,'.wday
				 AND 
				 sra.interval_beginning = ', in_sra_mod, '.interval_beginning
				 AND 
				 sra.interval_end = ', in_sra_mod, '.interval_end
			 ;'
		);
		
		SET @ins_1 = 'INSERT IGNORE INTO ';
		SET @ins_2 = '  (
				  user_id
				, wday
				, interval_beginning
				, interval_end
			 ) 
			 SELECT  
				  user_id
				, wday
				, interval_beginning
				, interval_end
			 FROM ';
			 
		/* 
			Insert into staff_regular_availability
			the rest of the rows of in_sra_mod 
		*/
		SET @ins_sra = CONCAT(
				@ins_1
				, 'staff_regular_availability'
				, @ins_2
				, in_sra_mod
				, ';'
		);
		
		/* 
			Insert into sra_snp
			the rest of the rows of in_sra_mod 
		*/
		SET @ins_sra_snp = CONCAT(
				@ins_1
				, 'sra_snp'
				, @ins_2
				, in_sra_mod
				, ';'
		);

		SET @d_sra_mod = CONCAT(
			'DROP TEMPORARY TABLE ', in_sra_mod, ';'
		);

		PREPARE del_sra_snp_sra FROM @del_sra_snp_sra;
		EXECUTE del_sra_snp_sra;
		DEALLOCATE PREPARE del_sra_snp_sra;
		SET @del_sra_snp_sra = NULL;
		
		PREPARE del_sra_mod FROM @del_sra_mod;
		EXECUTE del_sra_mod;
		DEALLOCATE PREPARE del_sra_mod;
		SET @del_sra_mod = NULL;
		
		PREPARE ins_sra FROM @ins_sra;
		EXECUTE ins_sra;
		DEALLOCATE PREPARE ins_sra;
		SET @ins_sra = NULL;
		
		PREPARE ins_sra_snp FROM @ins_sra_snp;
		EXECUTE ins_sra_snp;
		DEALLOCATE PREPARE ins_sra_snp;
		SET @ins_sra_snp = NULL;
		
		SET @ins_1 = NULL;
		SET @ins_2 = NULL;
		
		PREPARE d_sra_mod FROM @d_sra_mod;
		EXECUTE d_sra_mod;
		DEALLOCATE PREPARE d_sra_mod;
		SET @d_sra_mod = NULL;
		
	COMMIT;

END$$
DELIMITER ;