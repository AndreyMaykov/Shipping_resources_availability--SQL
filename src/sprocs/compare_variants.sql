/*

Object: stored procedure 

MySQL version: 8.0

Author: Andrey Maykov

Script Date: 2022-09-30

Description:
 
For data contained in identicaly structured tables t_k (k = 1, ... , kmax)
with columns id_i (i = 1. ... , imax) 
and columns dat_d (d = 1, ... , dmax), 
this procedure creates a comparison table -- 
one that could be created using the FULL OUTER JOIN operation
in the DBMSs that support this operation. 

Note: the actual names of the tables and columns here are passed 
to the procedure and thus can be any valid table/column names.

For each k, all the data originating in the same row of t_k
are inserted in a single row of the comparison table.

In the comparison table, the data retrieved from id and dat columns 
are organized differently:
- the values retrieved from all t_k.id_i columns (k = 1, ..., kmax)
are gathered in the comparison table's column with the same name id_i
(as in a result of the UNION operation);
- the values retrieved from t_k.dat_d columns are inserted 
in separate columns t_k_dat_d of the comparison table.

*/


DROP PROCEDURE IF EXISTS compare_variants;
DELIMITER $$
CREATE PROCEDURE compare_variants(
-- Each of parameters 1 - 3 is used to pass the name of a table 
-- containing the actual names of:
	  IN in_tbs_to_join VARCHAR(64) -- the tables to be compared
	, IN in_id_cols VARCHAR(64) -- the id columns 
	, IN in_dat_cols VARCHAR(64) -- the dat columns 
-- The name of the resulting comparison table:
	, IN cmpr_result VARCHAR(64)
)
	SQL SECURITY INVOKER
	READS SQL DATA
	COMMENT 'Emulates FULL OUTER JOIN'

BEGIN
	
	DECLARE m INT;
	DECLARE k INT;
	DECLARE kmax INT;
	DECLARE imax INT;
	DECLARE dmax INT;
	DECLARE tb_name VARCHAR(64);
	DECLARE cl_name VARCHAR(64);
	DECLARE id_cols_str TEXT;
	DECLARE dat_cols_str TEXT;
	DECLARE dat_tb_cols_str TEXT;
	DECLARE cols_str TEXT;
	DECLARE tb_cols_str TEXT;

	DECLARE errno INT;
	DECLARE msg VARCHAR(255);
	DECLARE EXIT HANDLER FOR SQLEXCEPTION
	BEGIN
		GET CURRENT DIAGNOSTICS CONDITION 1
	    errno = MYSQL_ERRNO , msg = MESSAGE_TEXT;
	    SELECT CONCAT(
	    	  'Error executing compare_variants: '
			, errno
	    	, " - "
	    	, msg
	    ) AS "Error message";
	END;

	/* 
	Create temporary tables -- copies
	of the tables with the names passed 
	through parameters 1 - 3
	*/
	CALL copy_tb_tmp(in_tbs_to_join, 1, 'tbs'); 
	CALL copy_tb_tmp(in_id_cols, 1, 'id_cols');
	CALL copy_tb_tmp(in_dat_cols, 1, 'dat_cols');
	

	/* 
		Return the number of the tables being compared 
		(corresponds to kmax in the Description)
	*/
	SELECT COUNT(*) FROM tbs INTO kmax;

	/* 
	Create string by the template 
	id_1, id_2, ... , id_imax 
	*/
	SET id_cols_str = '';
	SET m = 0;
	SELECT COUNT(*) FROM id_cols INTO imax;
	WHILE m < imax DO
		SET m = m + 1;

		SELECT col_name FROM id_cols WHERE id = m INTO cl_name;

		SET id_cols_str = CONCAT(id_cols_str
			, IF(m = 1, '', ', ')
			, cl_name
		);

	END WHILE;


	/* 
	Create string by the template 
	dat_1, ... , dat_dmax 
	*/
	SET dat_cols_str = '';
	SET m = 0;
	SELECT COUNT(*) FROM dat_cols INTO dmax;
	WHILE m < dmax DO
		SET m = m + 1;
		SELECT col_name FROM dat_cols WHERE id = m INTO cl_name;
		SET dat_cols_str = CONCAT(dat_cols_str  
			, IF(m = 1, '', ', ')	
			, cl_name
		);
	END WHILE;


	/* 
	Create string by the template 
	id_1, ... , id_imax, dat_1, ... , dat_dmax
	*/
	SET cols_str = CONCAT(id_cols_str, ', ', dat_cols_str);
	
	
	/* 
	Create string by the template 
	t_1.dat_1 t_1_dat_1, ... , t_1.dat_dmax t_1_dat_dmax,
	... ,
	t_kmax.dat_1 t_kmax_dat_1, ... , t_kmax.dat_dmax t_kmax_dat_dmax,
	*/
	SET dat_tb_cols_str = '';
	SET k = 0;
	WHILE k < kmax DO 
		SET k = k + 1;
		SELECT table_name FROM tbs WHERE id = k INTO tb_name;
	
	
		SET m = 0;
		-- SELECT COUNT(*) FROM dat_cols INTO mmax;
		WHILE m < dmax DO
			SET m = m + 1;
			SELECT col_name FROM dat_cols WHERE id = m INTO cl_name;
			SET dat_tb_cols_str = CONCAT(dat_tb_cols_str
				, IF(m = 1, '', ', ')
				, tb_name
				, '.'
				, cl_name
				, ' '
				, tb_name
				, '_'
				, cl_name
			);
		END WHILE;
		IF k < kmax THEN
			SET dat_tb_cols_str = CONCAT(dat_tb_cols_str, ', ');
		END IF;
	END WHILE;
	
	/* 
	Create string by the template
	dat_1, ... , dat_dmax,
	t_1.dat_1 t_1_dat_1, ... , t_1.dat_dmax t_1_dat_dmax,
	... ,
	t_kmax.dat_1 t_kmax_dat_1, ... , t_kmax.dat_dmax t_kmax_dat_dmax
	*/
	SET tb_cols_str = CONCAT(
		  id_cols_str
		, ', '
		, dat_tb_cols_str
	);
	

	/* 
	By using prepared statements,
	perform the LEFT JOIN operation on the set of tables 
	{t_1, t_2, ... t_kmax} and all the sets 
	obtained from it by cyclic permutation.
	
	Below LJ_k (k = 1, ... kmax) is the result 
	of the LEFT JOIN operation on these sets of tables
	*/
	SET k = 0;
	WHILE k < kmax DO
	
		SET k = k + 1;
		
		/* 
		For k = 2, ... , kmax,
		performs the (k - 1)-th cyclic permutation 
		of the names of the tables t_k
		(with respect to their original order)
		*/
		IF k > 1 THEN
			UPDATE tbs 
			SET id = IF(id > 1, id - 1, kmax);
		END IF;

		CALL drop_tb_tmp(
			CONCAT('LJ_', k)
		);
		
		SELECT table_name FROM tbs WHERE id = 1 INTO tb_name;
		SET @lj = CONCAT(
			 'CREATE TEMPORARY TABLE LJ_', k
			, ' AS 
				SELECT ', tb_cols_str, ' FROM ', tb_name
		);
		
	
		SET m = 1;
		WHILE m < kmax DO
			SET m = m + 1;
			SELECT table_name FROM tbs WHERE id = m INTO tb_name;
			SET @lj = CONCAT(@lj,
					  ' LEFT JOIN ', tb_name
					, ' USING ('
					, cols_str
					, ')'
					, IF(m <  kmax, '', ';')
			);
		END WHILE;	
		
		PREPARE lj FROM @lj;
		EXECUTE lj;
		DEALLOCATE PREPARE lj;
	
	END WHILE;

	/* 
	By using prepared statements,
	perform the UNION operation on the set of left joins 
	{LJ_1, LJ_2, ... LJ_kmax}.
	*/
	SET @foj = CONCAT(
		  'CREATE TEMPORARY TABLE '
		, cmpr_result 
		, ' AS'
	);

	SET k = 0;
	WHILE k < kmax DO
		SET k = k + 1;
		SET @foj = CONCAT(@foj
			, ' SELECT * FROM LJ_'
			, k 
			, IF(k < kmax, ' UNION ', '')
		);
	END WHILE;
	SET @foj = CONCAT(@foj
		, ' ORDER BY '
		, id_cols_str
	);

	PREPARE foj FROM @foj;

	CALL drop_tb_tmp(cmpr_result);
	EXECUTE foj;
	DEALLOCATE PREPARE foj;
	
	SET k = 0;
	WHILE k < kmax DO
		SET k = k + 1;
		CALL drop_tb_tmp(
			CONCAT('LJ_', k)
		);
	END WHILE;

END$$
DELIMITER ;