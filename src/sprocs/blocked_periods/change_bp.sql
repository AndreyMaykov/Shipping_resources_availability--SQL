


/*
Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-09-29

Description:

Based on the table with the name passed through
the parameter in_bp_mod, this procedure changes both 
blocked_periods and bp_snp so that the datasets 
of (user_id, period_beginning, period_end)
contained in the three tables become identical.

Note. The procedure does not save the dataset contained 
in blocked_periods/bp_snp; to save, 
use a separate procedure (e.g. copy_tb_tmp) 
before change_bp.
		
*/

DROP PROCEDURE IF EXISTS change_bp;
DELIMITER $$
CREATE PROCEDURE change_bp(
	IN in_bp_mod VARCHAR(64)
)
sp: BEGIN
	
		DECLARE errno INT;
		DECLARE msg VARCHAR(255);
		DECLARE EXIT HANDLER FOR SQLEXCEPTION
		BEGIN
			GET CURRENT DIAGNOSTICS CONDITION 1
			errno = MYSQL_ERRNO, msg = MESSAGE_TEXT;
			SELECT CONCAT(
				  'Error executing change_bp: '
				, errno
				, " - "
				, msg
			) AS "Error message";
		ROLLBACK;
		END;

	/*
		Verify whether changes based on in_bp_mod 
		can be made to blocked_periods; 
		if not, explain the reasons to the user
	*/
	
	CALL check_tb_tmp('bp_snp', @cont_flag_1);
		IF 
		@cont_flag_1 = 0
	THEN
		SELECT 'No changes to blocked_periods suggested in this session';
		LEAVE sp; 
	END IF;
	
	SET @cf2 = CONCAT(
		'CALL check_diff_bp(
			\'', in_bp_mod, '\', \'bp_snp\', @cont_flag_2
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
			  'No changes to blocked_periods suggested by '
			, in_bp_mod
		);
		LEAVE sp; 
	END IF;
	
	CALL check_diff_bp('blocked_periods', 'bp_snp', @cont_flag);
	
	IF @cont_flag = 0 THEN 
		SELECT 'Data in blocked_periods has been changed by another user';
		LEAVE sp; 
	END IF;
	
	
	/* If the previous test passed successfully, make the changes */
	
	START TRANSACTION;
		
		/* 
			Delete from blocked_periods and bp_snp
			the rows not contained in in_bp_mod 
		*/
		SET @del_bp_snp_bp = CONCAT(
			'DELETE bp_snp, bp FROM bp_snp 
			 INNER JOIN blocked_periods AS bp
			 ON 
				 bp_snp.user_id = bp.user_id
				 AND 
				 bp_snp.period_beginning = bp.period_beginning
				 AND 
				 bp_snp.period_end = bp.period_end
			 LEFT JOIN ', in_bp_mod, '
			 ON
				 bp.user_id = ', in_bp_mod,'.user_id
				 AND 
				 bp.period_beginning = ', in_bp_mod, '.period_beginning
				 AND 
				 bp.period_end = ', in_bp_mod, '.period_end
			 WHERE ', in_bp_mod, '.user_id IS NULL
			 ;'
		);
		
		/* 
			Delete from in_bp_mod the rows not contained 
			in blocked_periods/bp_snp
		*/
		SET @del_bp_mod = CONCAT(
			'DELETE ', in_bp_mod, ' FROM blocked_periods AS bp 
			 LEFT JOIN ', in_bp_mod, '
			 ON 
				 bp.user_id = ', in_bp_mod,'.user_id
				 AND 
				 bp.period_beginning = ', in_bp_mod, '.period_beginning
				 AND 
				 bp.period_end = ', in_bp_mod, '.period_end
			 ;'
		);
		
		SET @ins_1 = 'INSERT IGNORE INTO ';
		SET @ins_2 = '  (
				  user_id
				, period_beginning
				, period_end
			 ) 
			 SELECT  
				  user_id
				, period_beginning
				, period_end
			 FROM ';
			 
		/* 
			Insert into blocked_periods
			the rest of the rows of in_bp_mod 
		*/
		SET @ins_bp = CONCAT(
				@ins_1
				, 'blocked_periods'
				, @ins_2
				, in_bp_mod
				, ';'
		);
		
		/* 
			Insert into bp_snp
			the rest of the rows of in_bp_mod 
		*/
		SET @ins_bp_snp = CONCAT(
				@ins_1
				, 'bp_snp'
				, @ins_2
				, in_bp_mod
				, ';'
		);

		SET @d_bp_mod = CONCAT(
			'DROP TEMPORARY TABLE ', in_bp_mod, ';'
		);

		PREPARE del_bp_snp_bp FROM @del_bp_snp_bp;
		EXECUTE del_bp_snp_bp;
		DEALLOCATE PREPARE del_bp_snp_bp;
		SET @del_bp_snp_bp = NULL;
		
		PREPARE del_bp_mod FROM @del_bp_mod;
		EXECUTE del_bp_mod;
		DEALLOCATE PREPARE del_bp_mod;
		SET @del_bp_mod = NULL;
		
		PREPARE ins_bp FROM @ins_bp;
		EXECUTE ins_bp;
		DEALLOCATE PREPARE ins_bp;
		SET @ins_bp = NULL;
		
		PREPARE ins_bp_snp FROM @ins_bp_snp;
		EXECUTE ins_bp_snp;
		DEALLOCATE PREPARE ins_bp_snp;
		SET @ins_bp_snp = NULL;
		
		SET @ins_1 = NULL;
		SET @ins_2 = NULL;
		
		PREPARE d_bp_mod FROM @d_bp_mod;
		EXECUTE d_bp_mod;
		DEALLOCATE PREPARE d_bp_mod;
		SET @d_bp_mod = NULL;
		
	COMMIT;

END$$
DELIMITER ;