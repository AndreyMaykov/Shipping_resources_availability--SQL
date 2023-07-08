/*

Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-10-02

Description:

For staff_regular_availability, blocked_pereiods,
wave_timings or their variants, the procedure creates
a table with the structure identical to that of 
wave_available_staff.  

Such tables can be compared to each other to decide
which variants are most proper.


*/

DROP PROCEDURE IF EXISTS get_ws;
DELIMITER $$
CREATE PROCEDURE get_ws(
	-- staff_regular_availability table or its variant
	  IN in_sra VARCHAR(64)
	-- blocked_periods table or its variant
	, IN in_bp VARCHAR(64)
	-- wave_timings table or its variant
	, IN in_wt VARCHAR(64)
	-- the staff availability for each wave
	-- corresponding to the the other parameters
	, IN wsv_result VARCHAR(64)
)
BEGIN
	/* create snapshots of the tables 
	specified by the first three procedure parameters
	if the snapshots have not been created */
	SET @wtsnp = CONCAT(
		  'CALL copy_tb_tmp(\''
		, in_wt
		, '\', 0, \'wt_snp\');'
	);
	SET @srasnp = CONCAT(
		  'CALL copy_tb_tmp(\''
		, in_sra
		, '\', 0, \'sra_snp\');'
	);
	SET @bpsnp = CONCAT(
		  'CALL copy_tb_tmp(\''
		, in_bp
		, '\', 0, \'bp_snp\');'
	);
	
	SET @wtv = CONCAT(
		  'CALL copy_tb_tmp(\''
		, in_wt
		, '\', 1, \'wt_v\');'
	);
	
	SET @srav = CONCAT(
		  'CALL copy_tb_tmp(\''
		, in_sra
		, '\', 1, \'sra_v\');'
	);
	SET @bpv = CONCAT(
		  'CALL copy_tb_tmp(\''
		, in_bp
		, '\', 1, \'bp_v\');'
	);
	
	CALL exec_ps(@wtsnp);
	CALL exec_ps(@srasnp);
	CALL exec_ps(@bpsnp);
	CALL exec_ps(@wtv);
	CALL exec_ps(@srav);
	CALL exec_ps(@bpv);
	
	
	/*
	PREPARE wtsnp FROM @wtsnp;
  	EXECUTE wtsnp;
	DEALLOCATE PREPARE wtsnp;
	
	PREPARE srasnp FROM @srasnp;
  	EXECUTE srasnp;
	DEALLOCATE PREPARE srasnp;
	
	PREPARE bpsnp FROM @bpsnp;
  	EXECUTE bpsnp;
	DEALLOCATE PREPARE bpsnp;
	
	PREPARE wtv FROM @wtv;
  	EXECUTE wtv;
	DEALLOCATE PREPARE wtv;
	
	PREPARE srav FROM @srav;
  	EXECUTE srav;
	DEALLOCATE PREPARE srav;
	
	PREPARE bpv FROM @bpv;
  	EXECUTE bpv;
	DEALLOCATE PREPARE bpv;
	*/
	
	
	SET @drop_wsv = CONCAT(
		'DROP TEMPORARY TABLE IF EXISTS ', wsv_result, ';' 
	);
	/* Determine which employees are available for each wave 
	and generate a table presenting the result */
	SET @wsv = CONCAT(
		'CREATE TEMPORARY TABLE ', wsv_result, ' AS
		 SELECT 
			  wt_v.id wave_id
			, user_id 
	     FROM wt_v
		 INNER JOIN sra_v 
		 ON dayofweek(wt_v.wave_beginning) = sra_v.wday
		 WHERE 
			  sra_v.interval_beginning <= TIME(wt_v.wave_beginning)
			  AND 
			  sra_v.interval_end >= TIME(wt_v.wave_cutoff)
			  AND 
			  NOT EXISTS (
				SELECT 1 FROM bp_v
				WHERE 
					bp_v.period_beginning < wt_v.wave_cutoff
					AND
					bp_v.period_end > wt_v.wave_beginning
					AND
					bp_v.user_id = sra_v.user_id
			  );'
	);
	
	CALL exec_ps(@drop_wsv);
	CALL exec_ps(@wsv);
	
	/*
	PREPARE drop_wsv FROM @drop_wsv;
  	EXECUTE drop_wsv;
	DEALLOCATE PREPARE drop_wsv;
	
	PREPARE wsv FROM @wsv;
  	EXECUTE wsv;
	DEALLOCATE PREPARE wsv;
	*/
	
END$$
DELIMITER ;