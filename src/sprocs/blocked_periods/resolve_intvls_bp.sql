/*

Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-09-29

Description:
 
The procedure resolves all unresolved sets of intervals
in a variant of blocked_periods. 

The name of the variant is passed through the procedure parameter
in_bp_mod. 
 
*/

DROP PROCEDURE IF EXISTS resolve_intvls_bp;
DELIMITER $$
CREATE PROCEDURE resolve_intvls_bp(
		IN in_bp_mod VARCHAR(64)
)
	SQL SECURITY INVOKER
	MODIFIES SQL DATA
	COMMENT 'Resolves sets of intervals in a blocked_periods variant'

sp: BEGIN

	/*
		Verify whether the snapshot table bp_snp 
		is up-to-date with the data in in_bp_mod 
		(in case the data has been modified by another user).
	*/		
	SET @ps1 = 
		'CALL check_diff_bp(\'blocked_periods\', \'bp_snp\', @cont_flag);';	
	CALL exec_ps(@ps1);
			
	IF @cont_flag = 0 THEN 
		SELECT 'Data in blocked_periods has been changed by another user.' msg;
		LEAVE sp; 
	END IF;
	
	
	/*
		In in_bp_mod, find user_id
		for which modifications manually made by the user
		could yield an unresolved sets of blocked periods.
	*/
	DROP TEMPORARY TABLE IF EXISTS unres;
	SET @ps1 = CONCAT(
	   'CREATE TEMPORARY TABLE unres AS
		SELECT DISTINCT user_id
		FROM ', in_bp_mod, ' im
		WHERE NOT EXISTS (
			SELECT * FROM bp_snp snp
			WHERE 
				snp.user_id = im.user_id
				AND 
				snp.period_beginning = im.period_beginning
				AND 
				snp.period_end = im.period_end
		);'
	);
	CALL exec_ps(@ps1);


	/*
		Select from in_bp_mod all row groups 
		corresponding to possibly unresolved 
		sets of blocked periods.
	*/
	DROP TEMPORARY TABLE IF EXISTS unres_rows;
	SET @ps1 = CONCAT(
		'CREATE TEMPORARY TABLE unres_rows AS 
		 SELECT user_id, period_beginning, period_end FROM unres
		 INNER JOIN ', in_bp_mod,
		 ' USING (user_id);'
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
		, period_beginning 
	FROM unres_rows AS ur
	WHERE NOT EXISTS (
		SELECT * FROM unres_rows_1 AS ur1
		WHERE 
			ur.period_beginning > ur1.period_beginning
			AND 
			ur.period_beginning <= ur1.period_end
			AND 
			ur.user_id = ur1.user_id
	)
	ORDER BY 
		  user_id
		, period_beginning
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
		, period_end 
	FROM unres_rows AS ur
	WHERE NOT EXISTS (
		SELECT * FROM unres_rows_1 AS ur1
		WHERE 
			ur.period_end >= ur1.period_beginning
			AND 
			ur.period_end < ur1.period_end
			AND 
			ur.user_id = ur1.user_id
	)
	ORDER BY 
		  user_id
		, period_end
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
	SELECT id, user_id, period_beginning, period_end FROM
	r_intvls_begs JOIN r_intvls_ends
	USING (id, user_id);

	
	/*
		Delete from in_bp_mod all rows that were
		rejected during the resolving process.
	*/
	SET @ps1 = CONCAT(	
		'DELETE im FROM ',  in_bp_mod, ' im
		LEFT JOIN r_intvls ri
		USING (user_id, period_beginning, period_end) 
		LEFT JOIN unres ur
		USING (user_id) 
		WHERE 
			ri.id IS NULL
			AND
			ur.user_id IS NOT NULL			
		;'
	);
	CALL exec_ps(@ps1);
	
	
	/*
		Delete from the resolving systems r_intvls all rows
		that are already contained in in_bp_mod.
	*/
	SET @ps1 = CONCAT(
		'DELETE ri FROM r_intvls ri
		 LEFT JOIN ', in_bp_mod, ' im
		 USING (user_id, period_beginning, period_end) 
		 WHERE
			im.user_id is NOT NULL
		;'
	);
	CALL exec_ps(@ps1);

	
	/*
		Insert into in_bp_mod the rest of r_intvls
	*/
	SET @ps1 = CONCAT(
    	'INSERT IGNORE INTO ', in_bp_mod, 
		' (user_id, period_beginning, period_end)
		SELECT user_id, period_beginning, period_end 
		FROM r_intvls
		;'
    );
    CALL exec_ps(@ps1);
 
END$$
DELIMITER ;	
