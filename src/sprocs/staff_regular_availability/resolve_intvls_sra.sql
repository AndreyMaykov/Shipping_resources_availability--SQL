/*

Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-09-29

Description:
 
The procedure resolves all unresolved sets of intervals
in a variant of staff_regular_availability. 

The name of the variant is passed through the procedure parameter
in_sra_mod. 
 
*/

DROP PROCEDURE IF EXISTS resolve_intvls_sra;
DELIMITER $$
CREATE PROCEDURE resolve_intvls_sra(
		IN in_sra_mod VARCHAR(64)
)
	SQL SECURITY INVOKER
	MODIFIES SQL DATA
	COMMENT 'Resolves sets of intervals in a staff_regular_availability variant'

sp: BEGIN

	/*
		Verify whether the snapshot table sra_snp 
		is up-to-date with the data in in_sra_mod 
		(in case the data has been modified by another user).
	*/		
	SET @ps1 = 
		'CALL check_diff_sra(\'staff_regular_availability\', \'sra_snp\', @cont_flag);';	
	CALL exec_ps(@ps1);
			
	IF @cont_flag = 0 THEN 
		SELECT 'Data in staff_regular_availability has been changed by another user.' msg;
		LEAVE sp; 
	END IF;
	
	
	/*
		In in_sra_mod, find all pairs (user_id, wday)
		for which modifications manually made by the user
		could yield an unresolved sets of availability intervals.
	*/
	DROP TEMPORARY TABLE IF EXISTS unres;
	SET @ps1 = CONCAT(
	   'CREATE TEMPORARY TABLE unres AS
		SELECT DISTINCT user_id, wday 
		FROM ', in_sra_mod, ' im
		WHERE NOT EXISTS (
			SELECT * FROM sra_snp snp
			WHERE 
				snp.user_id = im.user_id
				AND
				snp.wday = im.wday
				AND 
				snp.interval_beginning = im.interval_beginning
				AND 
				snp.interval_end = im.interval_end
		);'
	);
	CALL exec_ps(@ps1);


	/*
		Select from in_sra_mod all row groups 
		corresponding to possibly unresolved 
		sets of availability intervals.
	*/
	DROP TEMPORARY TABLE IF EXISTS unres_rows;
	SET @ps1 = CONCAT(
		'CREATE TEMPORARY TABLE unres_rows AS 
		 SELECT user_id, wday, interval_beginning, interval_end FROM unres
		 INNER JOIN ', in_sra_mod,
		 ' USING (user_id, wday);'
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
		  user_id
		, wday
		, interval_beginning 
	FROM unres_rows AS ur
	WHERE NOT EXISTS (
		SELECT * FROM unres_rows_1 AS ur1
		WHERE 
			ur.interval_beginning > ur1.interval_beginning
			AND 
			ur.interval_beginning <= ur1.interval_end
			AND 
			ur.user_id = ur1.user_id
			AND 
			ur.wday = ur1.wday
	)
	ORDER BY 
		  user_id
		, wday
		, interval_beginning
	;
	ALTER TABLE r_intvls_begs
	ADD COLUMN id INT UNIQUE AUTO_INCREMENT;
	
	/* 
		Calculate the right ends of the intervals
		comprising the resolving sets.
	*/
	DROP TEMPORARY TABLE IF EXISTS r_intvls_ends;
	CREATE TEMPORARY TABLE r_intvls_ends AS
	SELECT DISTINCT 
		  user_id
		, wday
		, interval_end 
	FROM unres_rows AS ur
	WHERE NOT EXISTS (
		SELECT * FROM unres_rows_1 AS ur1
		WHERE 
			ur.interval_end >= ur1.interval_beginning
			AND 
			ur.interval_end < ur1.interval_end
			AND 
			ur.user_id = ur1.user_id
			AND 
			ur.wday = ur1.wday
	)
	ORDER BY 
		  user_id
		, wday
		, interval_end
	;
	ALTER TABLE r_intvls_ends
	ADD COLUMN id INT UNIQUE AUTO_INCREMENT;

	/*
		Build the resolving systems
		by coupling the left and right ends calculated
		previously.
	*/
	DROP TEMPORARY TABLE IF EXISTS r_intvls;
	CREATE TEMPORARY TABLE r_intvls AS
	SELECT id, user_id, wday, interval_beginning, interval_end FROM
	r_intvls_begs JOIN r_intvls_ends
	USING (id, user_id, wday);

	
	/*
		Delete from in_sra_mod all rows that were
		rejected during the resolving process.
	*/
	SET @ps1 = CONCAT(	
		'DELETE im FROM ',  in_sra_mod, ' im
		LEFT JOIN r_intvls ri
		USING (user_id, wday, interval_beginning, interval_end) 
		LEFT JOIN unres ur
		USING (user_id, wday) 
		WHERE 
			ri.id IS NULL
			AND
			ur.user_id IS NOT NULL			
		;'
	);
	CALL exec_ps(@ps1);
	
	
	/*
		Delete from the resolving systems r_intvls all rows
		that are already contained in in_sra_mod.
	*/
	SET @ps1 = CONCAT(
		'DELETE ri FROM r_intvls ri
		 LEFT JOIN ', in_sra_mod, ' im
		 USING (user_id, wday, interval_beginning, interval_end) 
		 WHERE
			im.user_id is NOT NULL
		;'
	);
	CALL exec_ps(@ps1);

	
	/*
		Insert into in_sra_mod the rest of r_intvls
	*/
	SET @ps1 = CONCAT(
    	'INSERT IGNORE INTO ', in_sra_mod, 
		' (user_id, wday, interval_beginning, interval_end)
		SELECT user_id, wday, interval_beginning, interval_end 
		FROM r_intvls
		;'
    );
    CALL exec_ps(@ps1);
 
END$$
DELIMITER ;	