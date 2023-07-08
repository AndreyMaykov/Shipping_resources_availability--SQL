/*

Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-10-02

Description:

For vehicles_not_in_service, wave_timings or their variants, 
the procedure creates a table with the structure identical 
to that of wave_available_staff.  

Such tables can be compared to each other to decide
which variants are most proper.


*/

DROP PROCEDURE IF EXISTS get_wv;
DELIMITER $$
CREATE PROCEDURE get_wv(
	-- vehicle_not_in_service table or its variant
	  IN in_nis VARCHAR(64)
	-- wave_timings table or its variant
	, IN in_wt VARCHAR(64)
	-- the vehicle availability for each wave
	-- corresponding to the the other parameters
	, IN wvv_result VARCHAR(64)
)
BEGIN
	/* create snapshots of the tables 
	specified by the first two procedure parameters
	if the snapshots have not been created */
	SET @wtsnp = CONCAT(
		  'CALL copy_tb_tmp(\''
		, in_wt
		, '\', 0, \'wt_snp\');'
	);
	SET @nissnp = CONCAT(
		  'CALL copy_tb_tmp(\''
		, in_nis
		, '\', 0, \'nis_snp\');'
	);

	SET @wtv = CONCAT(
		  'CALL copy_tb_tmp(\''
		, in_wt
		, '\', 1, \'wt_v\');'
	);
	SET @nisv = CONCAT(
		  'CALL copy_tb_tmp(\''
		, in_nis
		, '\', 1, \'nis_v\');'
	);
	
	CALL exec_ps(@wtsnp);
	CALL exec_ps(@nissnp);
	CALL exec_ps(@wtv);
	CALL exec_ps(@nisv);
	
	/*
	PREPARE wtsnp FROM @wtsnp;
  	EXECUTE wtsnp;
	DEALLOCATE PREPARE wtsnp;
	
	PREPARE nissnp FROM @nissnp;
  	EXECUTE nissnp;
	DEALLOCATE PREPARE nissnp;
	
	PREPARE wtv FROM @wtv;
  	EXECUTE wtv;
	DEALLOCATE PREPARE wtv;
	
	PREPARE nisv FROM @nisv;
  	EXECUTE nisv;
	DEALLOCATE PREPARE nisv;
	*/
	
	SET @drop_wvv = CONCAT(
		'DROP TEMPORARY TABLE IF EXISTS ', wvv_result, ';' 
	);
	/* Determine which vehicles are available for each wave 
	and generate a table presenting the result */
	SET @wvv = CONCAT(
	   'CREATE TEMPORARY TABLE ', wvv_result, ' AS
		SELECT 
			  wt_v.id wave_id
			, vehicles.id vehicle_id
		FROM wt_v
		INNER JOIN vehicles 
		WHERE 
			NOT EXISTS (
				SELECT 1 FROM nis_v
				WHERE 
					nis_v.nis_beginning < wt_v.wave_cutoff
					AND
					nis_v.nis_end > wt_v.wave_beginning
					AND
					nis_v.vehicle_id = vehicles.id
			);'
	);

	
	CALL exec_ps(@drop_wvv);
	CALL exec_ps(@wvv);
	
	/*
	PREPARE drop_wvv FROM @drop_wvv;
  	EXECUTE drop_wvv;
	DEALLOCATE PREPARE drop_wvv;
	
	PREPARE wvv FROM @wvv;
  	EXECUTE wvv;
	DEALLOCATE PREPARE wvv;
	*/
	
END$$
DELIMITER ;

