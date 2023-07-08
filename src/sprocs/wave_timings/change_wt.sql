
/*
Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-09-29

Description:

Based on the table with the name passed through
the parameter in_wt_mod, this procedure changes both 
wave_timings and wt_snp so that the datasets 
of (wave_beginning, wave_cutoff)
contained in the three tables become identical.

Note. The procedure does not save the dataset contained 
in wave_timings/wt_snp; to save, 
use a separate procedure (e.g. copy_tb_tmp) 
before change_wt.
		
*/

DROP PROCEDURE IF EXISTS change_wt;
DELIMITER $$
CREATE PROCEDURE change_wt(
	IN in_wt_mod VARCHAR(64)
)
sp: BEGIN
	
		DECLARE errno INT;
		DECLARE msg VARCHAR(255);
		DECLARE EXIT HANDLER FOR SQLEXCEPTION
		BEGIN
			GET CURRENT DIAGNOSTICS CONDITION 1
			errno = MYSQL_ERRNO, msg = MESSAGE_TEXT;
			SELECT CONCAT(
				  'Error executing change_wt: '
				, errno
				, " - "
				, msg
			) AS "Error message";
		ROLLBACK;
		END;

	/*
		Verify whether changes based on in_wt_mod 
		can be made to wave_timings; 
		if not, explain the reasons to the user
	*/
	
	CALL check_tb_tmp('wt_snp', @cont_flag_1);
		IF 
		@cont_flag_1 = 0
	THEN
		SELECT 'No changes to wave_timings suggested in this session';
		LEAVE sp; 
	END IF;
	
	SET @cf2 = CONCAT(
		'CALL check_diff_wt(
			\'', in_wt_mod, '\', \'wt_snp\', @cont_flag_2
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
			  'No changes to wave_timings suggested by '
			, in_wt_mod
		);
		LEAVE sp; 
	END IF;
	
	CALL check_diff_wt('wave_timings', 'wt_snp', @cont_flag);
	
	IF @cont_flag = 0 THEN 
		SELECT 'Data in wave_timings has been changed by another user';
		LEAVE sp; 
	END IF;
	
	
	/* If previous test passed successfully, make the changes */
	
	START TRANSACTION;
		
		/* 
			Delete from wave_timings and wt_snp
			the rows not contained in in_wt_mod 
		*/
		SET @del_wt_snp_wt = CONCAT(
			'DELETE wt_snp, wt FROM wt_snp 
			 INNER JOIN wave_timings AS wt
			 ON 
				 wt_snp.wave_beginning = wt.wave_beginning
				 AND 
				 wt_snp.wave_cutoff = wt.wave_cutoff
			 LEFT JOIN ', in_wt_mod, '
			 ON
				 wt.wave_beginning = ', in_wt_mod, '.wave_beginning
				 AND 
				 wt.wave_cutoff = ', in_wt_mod, '.wave_cutoff
			 WHERE ', in_wt_mod, '.wave_beginning IS NULL
			 ;'
		);
		
		/* 
			Delete from in_wt_mod the rows not contained 
			in wave_timings/wt_snp
		*/
		SET @del_wt_mod = CONCAT(
			'DELETE ', in_wt_mod, ' FROM wave_timings AS wt 
			 LEFT JOIN ', in_wt_mod, '
			 ON 
				 wt.wave_beginning = ', in_wt_mod, '.wave_beginning
				 AND 
				 wt.wave_cutoff = ', in_wt_mod, '.wave_cutoff
			 ;'
		);
		
		SET @ins_1 = 'INSERT IGNORE INTO ';
		SET @ins_2 = '  (
				  wave_beginning
				, wave_cutoff
			 ) 
			 SELECT  
				  wave_beginning
				, wave_cutoff
			 FROM ';
			 
		/* 
			Insert into wave_timings
			the rest of the rows of in_wt_mod 
		*/
		SET @ins_wt = CONCAT(
				@ins_1
				, 'wave_timings'
				, @ins_2
				, in_wt_mod
				, ';'
		);
		
		/* 
			Insert into wt_snp
			the rest of the rows of in_wt_mod 
		*/
		SET @ins_wt_snp = CONCAT(
				@ins_1
				, 'wt_snp'
				, @ins_2
				, in_wt_mod
				, ';'
		);

		SET @d_wt_mod = CONCAT(
			'DROP TEMPORARY TABLE ', in_wt_mod, ';'
		);

		PREPARE del_wt_snp_wt FROM @del_wt_snp_wt;
		EXECUTE del_wt_snp_wt;
		DEALLOCATE PREPARE del_wt_snp_wt;
		SET @del_wt_snp_wt = NULL;
		
		PREPARE del_wt_mod FROM @del_wt_mod;
		EXECUTE del_wt_mod;
		DEALLOCATE PREPARE del_wt_mod;
		SET @del_wt_mod = NULL;
		
		PREPARE ins_wt FROM @ins_wt;
		EXECUTE ins_wt;
		DEALLOCATE PREPARE ins_wt;
		SET @ins_wt = NULL;
		
		PREPARE ins_wt_snp FROM @ins_wt_snp;
		EXECUTE ins_wt_snp;
		DEALLOCATE PREPARE ins_wt_snp;
		SET @ins_wt_snp = NULL;
		
		SET @ins_1 = NULL;
		SET @ins_2 = NULL;
		
		PREPARE d_wt_mod FROM @d_wt_mod;
		EXECUTE d_wt_mod;
		DEALLOCATE PREPARE d_wt_mod;
		SET @d_wt_mod = NULL;
		
	COMMIT;

END$$
DELIMITER ;
