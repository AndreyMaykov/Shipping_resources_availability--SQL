/*

Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-09-27

Description:
 
Creates a copy of an original table (e.g. staff_regular_availability,
blocked_periods, etc.) for subsequent modification to obtain 
a variant of the the table. 

The procedure can be used to obtain multiple variants for comparison
purposes. 

The names of the variants that have been created and
not deleted are held in the table with the name corresponding to
the original table (e.g. sra_mod_vs for staff_regular_availability, 
bp_mod_vs for blocked_periods, etc) defined by the mapping table
created by the stored procedure set_sfx().

The parameters of the procedure are:
	a.	in_orig -- the name of the original table, 
		e.g. staff_regular_availability or blocked_periods;
	b.  in_mod -- the name of the variant created; 
		can be any string permitted in the used SQL version
		(not necesserely connected to in_orig).
*/

DROP PROCEDURE IF EXISTS create_mod;
DELIMITER $$
CREATE PROCEDURE create_mod(
	  IN in_orig VARCHAR(64) 
	, IN in_mod VARCHAR(64) 
)
	SQL SECURITY INVOKER
	READS SQL DATA
	COMMENT 'Creats a variant of an original table for modification'
	
sp: BEGIN
	
		DECLARE errno INT;
		DECLARE msg VARCHAR(255);
		DECLARE EXIT HANDLER FOR SQLEXCEPTION
		BEGIN
			GET CURRENT DIAGNOSTICS CONDITION 1
			errno = MYSQL_ERRNO, msg = MESSAGE_TEXT;
			SELECT CONCAT(
				  'Error executing create_mod: '
				, errno
				, " - "
				, msg
			) AS "Error message";
		ROLLBACK;
		END;
		
		
		/*
			Verify whether the name of the variant passed 
			through in_mod is already in use.
		*/
		SET @chmod = CONCAT(
			'CALL check_tb_tmp(\'', in_mod, '\', @cont_flag);'
		);
		CALL exec_ps(@chmod);
		
		IF 
			@cont_flag = 1
		THEN
			SELECT CONCAT(
				 'Table '
				, in_mod
				, ' already exists. Choose another table name.'
			) msg;
			LEAVE sp;
		END IF;
		
		/* 
			Find the suffix used in the name of the snapshot table
			corresponding to the original table in_orig.
		*/
		CALL set_sfx();
	
		SET @ps1 = CONCAT(
			'SELECT sfx FROM sfx_tb WHERE tb_name = \'', in_orig, '\' INTO @in_sfx;'
		);
		CALL exec_ps(@ps1);
		
		
		/*
			Verify whether the snapshot table has been created
			for in_orig in this session. 
			If does not exist, create one;
			if exists, check whether it is up-to-date with the data
			in in_orig (in case the data was modified by another user).
		*/
		SET @ps1 = CONCAT(
			'CALL check_tb_tmp(\'', @in_sfx, '_snp\', @cont_flag_1);'
		);
		CALL exec_ps(@ps1);
		
		
		IF 
		@cont_flag_1 = 0
		THEN
			SET @ps1 = CONCAT(
				'CREATE TEMPORARY TABLE ', @in_sfx, '_snp LIKE ', in_orig, ';' 
			);
			CALL exec_ps(@ps1);
			SET @ps1 = CONCAT(
				'INSERT INTO ', @in_sfx, '_snp SELECT * FROM ', in_orig, ';'
			);
			CALL exec_ps(@ps1);
			SET @ps1 = CONCAT(
				'ALTER TABLE ', @in_sfx, '_snp
				 ADD CONSTRAINT id_key UNIQUE (id),
				 DROP PRIMARY KEY;'
			);
			CALL exec_ps(@ps1);
		ELSE 
			SET @ps1 = CONCAT(
				'CALL check_diff_', @in_sfx, '(\'', in_orig, '\', \'', @in_sfx, '_snp\', @cont_flag_2);'
			);
			
			CALL exec_ps(@ps1);
			
			IF @cont_flag_2 = 0 THEN 
				SELECT CONCAT('Data in ', in_orig, ' has been changed by another user.') msg;
				LEAVE sp; 
			END IF;
		END IF;
		
	
		/*
			Provided all the previous tests passed successfully,
			create a copy of in_orig for subsequent modification.
		*/
		SET @ps1 = CONCAT(
			'CREATE TEMPORARY TABLE ', in_mod, ' LIKE ', in_orig, ';' 
		);
		CALL exec_ps(@ps1);
		SET @ps1 = CONCAT(
			'INSERT INTO ', in_mod, ' SELECT * FROM ', in_orig, ';'
		);
		CALL exec_ps(@ps1);
		SET @ps1 = CONCAT(
			'ALTER TABLE ', in_mod, '
			 ADD CONSTRAINT id_key UNIQUE (id),
			 DROP PRIMARY KEY;'
		);
		CALL exec_ps(@ps1);
		
		
		/*
			If the table for the names of the
			variants of in_mod being used
			has not been created yet, create it.
		*/
		SET @ps1 = CONCAT(
			'CREATE TEMPORARY TABLE IF NOT EXISTS ', @in_sfx, '_mod_vs (
				id INT AUTO_INCREMENT UNIQUE
				, table_name VARCHAR(64)
			 );'
		);
		CALL exec_ps(@ps1);
		
		
		/*
			Insert the name of newly created variant
			into the above table.
		*/
		SET @insmodvs = CONCAT(
			'INSERT INTO ', @in_sfx, '_mod_vs (table_name)
			 VALUES (\'', in_mod, '\');'
		);
		CALL exec_ps(@insmodvs);

END$$
DELIMITER ;