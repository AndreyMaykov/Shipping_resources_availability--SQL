/*

Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-09-29

Description:
 
The procedure resolves all unresolved sets of intervals
in a variant of vehicles_not_in_service. 

The name of the variant is passed through the procedure parameter
in_nis_mod. 
 
*/

DROP PROCEDURE IF EXISTS resolve_intvls_nis;
DELIMITER $$
CREATE PROCEDURE resolve_intvls_nis(
		IN in_nis_mod VARCHAR(64)
)
	SQL SECURITY INVOKER
	MODIFIES SQL DATA
	COMMENT 'Resolves sets of intervals in a vehicles_not_in_service variant'

sp: BEGIN

	/*
		Verify whether the snapshot table nis_snp 
		is up-to-date with the data in in_nis_mod 
		(in case the data has been modified by another vehicle).
	*/		
	SET @ps1 = 
		'CALL check_diff_nis(\'vehicles_not_in_service\', \'nis_snp\', @cont_flag);';	
	CALL exec_ps(@ps1);
			
	IF @cont_flag = 0 THEN 
		SELECT 'Data in vehicles_not_in_service has been changed by another user.' msg;
		LEAVE sp; 
	END IF;
	
	
	/*
		In in_nis_mod, find vehicle_id
		for which modifications manually made by the system user
		could yield an unresolved sets of not-in-service periods.
	*/
	DROP TEMPORARY TABLE IF EXISTS unres;
	SET @ps1 = CONCAT(
	   'CREATE TEMPORARY TABLE unres AS
		SELECT DISTINCT vehicle_id
		FROM ', in_nis_mod, ' im
		WHERE NOT EXISTS (
			SELECT * FROM nis_snp snp
			WHERE 
				snp.vehicle_id = im.vehicle_id
				AND 
				snp.nis_beginning = im.nis_beginning
				AND 
				snp.nis_end = im.nis_end
		);'
	);
	CALL exec_ps(@ps1);


	/*
		Select from in_nis_mod all row groups 
		corresponding to possibly unresolved 
		sets of not-in-service periods.
	*/
	DROP TEMPORARY TABLE IF EXISTS unres_rows;
	SET @ps1 = CONCAT(
		'CREATE TEMPORARY TABLE unres_rows AS 
		 SELECT vehicle_id, nis_beginning, nis_end FROM unres
		 INNER JOIN ', in_nis_mod,
		 ' USING (vehicle_id);'
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
		  vehicle_id
		, nis_beginning 
	FROM unres_rows AS ur
	WHERE NOT EXISTS (
		SELECT * FROM unres_rows_1 AS ur1
		WHERE 
			ur.nis_beginning > ur1.nis_beginning
			AND 
			ur.nis_beginning <= ur1.nis_end
			AND 
			ur.vehicle_id = ur1.vehicle_id
	)
	ORDER BY 
		  vehicle_id
		, nis_beginning
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
		  vehicle_id
		, nis_end 
	FROM unres_rows AS ur
	WHERE NOT EXISTS (
		SELECT * FROM unres_rows_1 AS ur1
		WHERE 
			ur.nis_end >= ur1.nis_beginning
			AND 
			ur.nis_end < ur1.nis_end
			AND 
			ur.vehicle_id = ur1.vehicle_id
	)
	ORDER BY 
		  vehicle_id
		, nis_end
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
	SELECT id, vehicle_id, nis_beginning, nis_end FROM
	r_intvls_begs JOIN r_intvls_ends
	USING (id, vehicle_id);

	
	/*
		Delete from in_nis_mod all rows that were
		rejected during the resolving process.
	*/
	SET @ps1 = CONCAT(	
		'DELETE im FROM ',  in_nis_mod, ' im
		LEFT JOIN r_intvls ri
		USING (vehicle_id, nis_beginning, nis_end) 
		LEFT JOIN unres ur
		USING (vehicle_id) 
		WHERE 
			ri.id IS NULL
			AND
			ur.vehicle_id IS NOT NULL			
		;'
	);
	CALL exec_ps(@ps1);
	
	
	/*
		Delete from the resolving systems r_intvls all rows
		that are already contained in in_nis_mod.
	*/
	SET @ps1 = CONCAT(
		'DELETE ri FROM r_intvls ri
		 LEFT JOIN ', in_nis_mod, ' im
		 USING (vehicle_id, nis_beginning, nis_end) 
		 WHERE
			im.vehicle_id is NOT NULL
		;'
	);
	CALL exec_ps(@ps1);

	
	/*
		Insert into in_nis_mod the rest of r_intvls
	*/
	SET @ps1 = CONCAT(
    	'INSERT IGNORE INTO ', in_nis_mod, 
		' (vehicle_id, nis_beginning, nis_end)
		SELECT vehicle_id, nis_beginning, nis_end 
		FROM r_intvls
		;'
    );
    CALL exec_ps(@ps1);
 
END$$
DELIMITER ;	
