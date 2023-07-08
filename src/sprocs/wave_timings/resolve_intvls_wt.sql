/*

Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-09-29

Description:
 
The procedure resolves overlapping sets of  
intervals related in a variant of wave_timings. 

The name of the variant is passed through the procedure parameter
in_wt_mod. 
 
*/

DROP PROCEDURE IF EXISTS resolve_intvls_wt;
DELIMITER $$
CREATE PROCEDURE resolve_intvls_wt(
		IN in_wt_mod VARCHAR(64)
)
	SQL SECURITY INVOKER
	MODIFIES SQL DATA
	COMMENT 'Resolves sets of intervals in a wave_timings variant'

sp: BEGIN

	/*
		Verify whether the snapshot table wt_snp 
		is up-to-date with the data in in_wt_mod 
		(in case the data has been modified by another user).
	*/		
	SET @ps1 = 
		'CALL check_diff_wt(\'wave_timings\', \'wt_snp\', @cont_flag);';	
	CALL exec_ps(@ps1);
			
	IF @cont_flag = 0 THEN 
		SELECT 'Data in wave_timings has been changed by another user.' msg;
		LEAVE sp; 
	END IF;
	
	
	SET @ps1 = CONCAT(
		'ALTER TABLE ', in_wt_mod, '
		 ADD COLUMN wvdt DATE;'
	);
	CALL exec_ps(@ps1);
	
	SET @ps1 = CONCAT(
		'UPDATE ', in_wt_mod, '
		 SET wvdt = date(wave_beginning);'
	);
	CALL exec_ps(@ps1);
	
	
	/*
		In in_wt_mod, find id
		for which modifications manually made by the user
		could yield an unresolved sets of wave timings.
	*/
	DROP TEMPORARY TABLE IF EXISTS unres;
	SET @ps1 = CONCAT(
	   'CREATE TEMPORARY TABLE unres AS
		SELECT DISTINCT wvdt
		FROM ', in_wt_mod, ' im
		WHERE NOT EXISTS (
			SELECT * FROM wt_snp snp
			WHERE 
				snp.wave_beginning = im.wave_beginning
				AND 
				snp.wave_cutoff = im.wave_cutoff
		);'
	);
	CALL exec_ps(@ps1);


	/*
		Select from in_wt_mod all row groups 
		corresponding to possibly unresolved 
		sets of wave timings.
	*/
	DROP TEMPORARY TABLE IF EXISTS unres_rows;
	SET @ps1 = CONCAT(
		'CREATE TEMPORARY TABLE unres_rows AS 
		 SELECT wvdt, wave_beginning, wave_cutoff FROM unres
		 INNER JOIN ', in_wt_mod,
		 ' USING (wvdt);'
	);
	CALL exec_ps(@ps1);
	

	CALL copy_tb_tmp('unres_rows', 1, 'unres_rows_1');
	
	
	/* 
		Build a resolving set of intervals 
		for each of the selected row groups.
	*/
	/* 
		Calculate the left ends of the intervals
		comprising the resolving sets.
	*/	
	DROP TEMPORARY TABLE IF EXISTS r_intvls_begs;
	CREATE TEMPORARY TABLE r_intvls_begs AS
	SELECT DISTINCT 
		  wvdt
		, wave_beginning 
	FROM unres_rows AS ur
	WHERE NOT EXISTS (
		SELECT * FROM unres_rows_1 AS ur1
		WHERE 
			ur.wave_beginning > ur1.wave_beginning
			AND 
			ur.wave_beginning <= ur1.wave_cutoff
			AND 
			ur.wvdt = ur1.wvdt
	)
	ORDER BY 
		  wvdt
		, wave_beginning
	;
	ALTER TABLE r_intvls_begs
	ADD COLUMN i_id INT UNIQUE AUTO_INCREMENT;

	
	/* 
		Calculate the right ends of the intervals
		comprising the resolving sets.
	*/
	DROP TEMPORARY TABLE IF EXISTS r_intvls_ends;
	CREATE TEMPORARY TABLE r_intvls_ends AS
	SELECT DISTINCT 
		  wvdt
		, wave_cutoff 
	FROM unres_rows AS ur
	WHERE NOT EXISTS (
		SELECT * FROM unres_rows_1 AS ur1
		WHERE 
			ur.wave_cutoff >= ur1.wave_beginning
			AND 
			ur.wave_cutoff < ur1.wave_cutoff
			AND 
			ur.wvdt = ur1.wvdt
	)
	ORDER BY 
		  wvdt
		, wave_cutoff
	;
	ALTER TABLE r_intvls_ends
	ADD COLUMN i_id INT UNIQUE AUTO_INCREMENT;
	

	/*
		Build the resolving systems
		by coupling the left and right ends calculated
		previously.
	*/
	DROP TEMPORARY TABLE IF EXISTS r_intvls;
	CREATE TEMPORARY TABLE r_intvls AS
	SELECT i_id, wvdt, wave_beginning, wave_cutoff FROM
	r_intvls_begs JOIN r_intvls_ends
	USING (i_id, wvdt);

	
	/*
		Delete from in_wt_mod all rows that were
		rejected during the resolving process.
	*/
	SET @ps1 = CONCAT(	
		'DELETE im FROM ',  in_wt_mod, ' im
		LEFT JOIN r_intvls ri
		USING (wvdt, wave_beginning, wave_cutoff) 
		LEFT JOIN unres ur
		USING (wvdt) 
		WHERE 
			ri.i_id IS NULL
			AND
			ur.wvdt IS NOT NULL			
		;'
	);
	CALL exec_ps(@ps1);


	/*
		Delete from the resolving systems r_intvls all rows
		that are already contained in in_wt_mod.
	*/
	SET @ps1 = CONCAT(
		'DELETE ri FROM r_intvls ri
		 LEFT JOIN ', in_wt_mod, ' im
		 USING (wvdt, wave_beginning, wave_cutoff) 
		 WHERE
			im.wvdt is NOT NULL
		;'
	);
	CALL exec_ps(@ps1);

	
	/*
		Insert into in_wt_mod the rest of r_intvls
	*/
	SET @ps1 = CONCAT(
    	'INSERT IGNORE INTO ', in_wt_mod, 
		' (wvdt, wave_beginning, wave_cutoff)
		SELECT wvdt, wave_beginning, wave_cutoff 
		FROM r_intvls
		;'
    );
    CALL exec_ps(@ps1);
	

	SET @ps1 = CONCAT(
		'ALTER TABLE ', in_wt_mod, '
		 DROP COLUMN wvdt;'
	);
	CALL exec_ps(@ps1);
	
 
END$$
DELIMITER ;	

