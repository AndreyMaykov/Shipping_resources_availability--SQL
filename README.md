# Shipping Resources Availability Project

The main goal of this project is to provide a database-level solution to 
<a href="https://github.com/AndreyMaykov/Online_marketplace_shipping__SQL/blob/main/Readme.md/#Calculating_intervals">the resources availability problem</a> related to the OM shipping database 
(see <a href="https://github.com/AndreyMaykov/Online_marketplace_shipping__SQL/blob/main/Readme.md">Online Marketplace Shipping Schema Project</a>). However, some of the stored procedures created for this purpose can be helpful for handling a much more complex problem &mdash; 
<a href="https://github.com/AndreyMaykov/Online_marketplace_shipping__SQL/blob/main/Readme.md/#Stage_B">dispatching orders and vehicles for a wave</a> 
in the OM shipping management system.

## Contents
[Introduction](#introduction) <br />
[Technologies](#technologies) <br />
[Major problems and their solutions](#major-problems-and-their-solutions) <br />
  [Multi-user functionality. Concurrency and isolation levels](#multi-user-functionality-concurrency-and-isolation-levels) <br />
  [Handling overlapping sets of intervals](#handling-overlapping-sets-of-intervals) <br />
      [Example](#example) <br />
      [Mathematical preliminaries](#mathematical-preliminaries) <br />
      [Algorithm](#algorithm) <br />
      [Implementation](#implementation) <br />
  [Comparing OM Shipping datasets. Stored procedure compare_variants()](#comparing-om-shipping-datasets-stored-procedure-compare_variants) <br />
      [Example](#example-1) <br />
      [The general case](#the-general-case) <br />
      [Implementation](#implementation-1) <br />
[Shipping resources management process outline](#shipping-resources-management-process-outline) <br />
  [Stage 1](#stage-1) <br />
  [Stage 2](#stage-2) <br />
  [Stage 3](#stage-3) <br />
[Further development](#further-development)  <br />
[Acknowledgements](#acknowledgements)  <br />

  
## Introduction

The following aspects of  the OM shipping management system are essential for this project.<br> 
1. It is required that <br>
    1. multiple users can <a name="Multi-session_req_i"></a>access the system at the same time (each one in a separate session) with permission to modify data in the database; <br>
    1. <a name="Multi-session_req_ii">each user can create several variants of the modification (independently from other users), compare them and choose the variant the user considers the most suitable. <br>
2. <a name="various_applications"></a>Various applications can be used to access the database;</a>
3. <a name="connection_stability"></a>During a session, the connection between the user's application and the DBMS is fairly stable.

As mentioned in <a href="https://github.com/AndreyMaykov/Online_marketplace_shipping__SQL/blob/main/Readme.md/#Calculating_intervals">the discussion</a> of the OM Shipping Schema project, determining resources availability requires some calculations with the data the OM database contains, and such calculations can be carried out either by the database management system or an accessing application. 

A significant advantage of the database-level approach is that it makes developing involved applications easier and helps ensure consistent access across all of them. For the OM shipping system, this is an important argument in favour of utilizing the database level (see <a href="#various_applications">2</a> above).

At the same time, one of the most significant drawbacks of this approach is the system's poor performance when the calculations involve iterating through table rows. Fortunately, it is possible to organize our calculations without such iterations at all.

These are the main reasons why for this project, the database-level approach was chosen over its application-level alternative.

## Technologies

- MySQL 8.0.27 / DBeaver 21.3
- AWS RDS

## Major problems and their solutions

### Multi-user functionality. Concurrency and isolation levels

For a session user, the process of modifying data in the OM database can include creating modification variants for multiple DB tables (see&nbsp;<a href="Multi-session_req_ii">1.ii</a> above) and evaluating these variants against OM shipping needs and policies. The user may add variants in several cycles before a proper combination of variants is obtained. 

There is a possibility that another user is working with the same tables at the same time and have changed the table data, which may result in inconsistency of the data the first user retrieves in different cycles.

One way to resolve this problem is that the tables being modified in one session are locked for other sessions/users — either implicitly (by implementing the process as an SQL transaction with a proper isolation level), or explicitly (by using the LOCK TABLE statement).

In our case, however, this can cause another issue: if the user has to create and review multiple variants for several tables, it may take a quarter of an hour or even longer&nbsp;&mdash; too long for other users to wait for access to the locked tables.

Therefore in this project, the problem is dealt with in a different way:

1. Before the user starts creating variants of a table, two identical copies of its data are generated, and only this user has access to them. One copy is modified by the user (which results in creating table modification variant #1). 
The other copy, further referred to as the <a name="snapshot_definition"></a>**snapshot**, is used to:
	- check whether the data in the original table has been changed since the copy was created (checks can be done by the user at any time and are done automatically right before the user starts <a href="#replicating_modifications">replicating the modifications</a> to the original table, and
	- generate more copies (also accessible to this user only) if additional modification variants are needed.

2. If any changes to the original table's data are detected through such checks, the session user can evaluate whether the changes are compatible with the intended modifications, and either continue with the created modification variants or restart the process by creating the two copies of the current table data.

3. <a name="replicating_modifications"></a>Once the session user has decided on the final version of the table data modification, the modification is replicated to the original DB table</a>.

This general scheme was implemented using SQL temporary tables for all the data copies the user creates or modifies, as well as for any supplementary datasets the user may need for manipulating the copies. This guarantees that no other users' actions can interfere with such manipulations. <a href="#connection_stability">The connection stability</a> minimizes the risk of loosing the temp tables' data due to an accidental session termination. 

**Note.**&nbsp;
Most of the procedures in this implementation only involve temp tables; therefore, DB permanent tables mostly remain unlocked during the session. However, a small number of procedures include series of reading, data manipulation and writing operations performed on the permanent tables' data, which requires locking the tables for a short (sub-second on a typical server) time. The necessary locks are acquired and released by SQL transactions included in stored procedures (for example, see <a href="/src/sprocs/staff_regular_availability/change_sra.sql">`change_sra.sql`</a>). For all the transactions, the isolation level is REPEATABLE READ.

### Handling overlapping sets of intervals

The following example is only meant to outline the problem of overlapping time intervals in OM Shipping datasets; for a more rigorous discussion of the problem, see <a href = "#mathematical-preliminaries">below</a>.

#### Example

Suppose the availability of an employee on Monday is presented in `staff_regular_availability` <a name = "five_rows"></a>like this:  

| `user_id`  | `wday`  | `interval_beginning`  | `interval_end`  |
| ---------- | ------- | --------------------- | --------------- |
|  1         | 2       | 09:00                 | 12:00           |
|  1         | 2       | 11:00                 | 14:00           |
|  1         | 2       | 15:00                 | 16:00           |
|  1         | 2       | 16:00                 | 18:00           |
|  1         | 2       | 16:15                 | 17:45           |

(the `id` column is omitted).

The intervals [09:00, 12:00] and [11:00, 14:00] overlap (both contain [11:00, 12:00]), so in fact, the employee is available from 09:00 to 14:00, and the two intervals can be replaced by just one interval [09:00, 14:00].

Likewise, the intervals [15:00, 16:00], [16:00, 18:00] and [16:15, 17:45] can be replaced by the interval [14:00, 18:00] (because the end of the first of these intervals is the beginning of the second one and the third interval is contained in the second).

Thus the  <a name = "two_rows"></a>two rows

| `user_id`  | `wday`  | `interval_beginning`  | `interval_end`  |
| ---------- | ------- | --------------------- | --------------- |
|  1         | 2       | 09:00                 | 14:00           |
|  1         | 2       | 15:00                 | 18:00           |

describe the same availability as the original five rows and do not include overlapping time intervals.

Overlapping sets of intervals can be replaced by their non-overlapping equivalents in any table containing time intervals: `staff_regular_availability`, `blocked_periods`, etc. For a human, it makes the information presented in such tables easier to comprehend; for the system, it allows for processing this information more efficiently. 

In a table that did not include overlapping intervals initially, an overlapping set can emerge due to normal modification of the data by an administrator who has inserted a new row or changed the beginning/ending time of an existing row. For example, if the interval beginning time in the second row of <a href = "#two_rows">the last table</a> has been changed from 15:00 to 14:00, we get two overlapping intervals that should be replaced by the single interval [09:00, 18:00]. 

Maintaining non-overlapping (i.e. making appropriate replacements) manually after data modifications can be tedious; it also entails a risk of errors. A more useful alternative is to have such replacements performed by the system automatically. An algorithm for that and its implementation are discussed in the next three subsections.

#### Mathematical preliminaries

We use the term **interval** as a shorthand for a
<a href=https://en.wikipedia.org/wiki/Interval_(mathematics)> bounded closed interval</a> 
(e.g. a set 
$${X = [\\,x',\\, x''] : = \\{x \mid  x' \leq x \leq x''\\}}$$ 
where 
${x' > - \infty}$, 
${x'' < + \infty}$). 
By a **set of intervals** we  mean a finite set (i.e. one comprised of a finite number of intervals).

Consider <a name="def_x_prime_etc"></a>two sets of intervals:
	
$$
	\{{\\{X\_n\\}\_{n=1}^N}\} \qquad \mbox{\sf{where}} 
	\quad 
	\{{X_n = [\\,x'\_n,\\, x''\_n\\,]\\,\\,\\,(n = 1, ... ,\\,N)}} 
$$
	
and

$$
	\quad
	\\{Y\_m\\}\_{m=1}^M \qquad \mbox{\sf{where}} 
	\quad 
	Y_m = [\\,y'\_m,\\, y''\_m\\,]\\,\\,\\,(m = 1, ... ,\\,M)\\,.
$$

**Definition.**&nbsp;&nbsp;_We say that_ $\\{Y\_m\\}\_{m=1}^N$ _is a **resolving set** for_ $\\{X\_n\\}\_{n=1}^N\\:$, _or that_ $\\{X\_n\\}\_{n=1}^N$ _is **resolved** into_ $\\{Y\_m\\}\_{m=1}^N\\:$,  _if_
<a name="resolving_set_definition"></a>

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;**(1)**&nbsp;
$\\:\\:\\:\displaystyle{y''\_m < y'\_{m+1}} \\:$ _for any_ $m = 1, ... , M - 1\\:$, _and_

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;**(2)**&nbsp;
$\\:\displaystyle{\bigcup_{m = 1}^M Y_m = \bigcup_{n = 1}^N X_n}\\:$.

The two tables we dealt with in <a href="#example">the previous subsection</a> provide an illustration to the above definition: for the five time intervals from <a href="#five_rows">the first table</a>, the two intervals from <a href="#two_rows">the second one</a> is exactly what we call a resolving set.

**Note.**&nbsp;
Any resolving set is non-overlapping by definition as it follows from (1) that $\displaystyle{Y\_{m\_1}}\bigcap Y\_{m\_2} = \varnothing\\:$ for any $m_1 \neq m_2\\:$. On the other hand, any non-overlapping set of intervals can be converted into a non-overlapping set satisfying (1) by just renumbering its intervals in the ascending order of their left or right ends. Therefore, seeking any non-overlapping equivalent of $\{{\\{X\_n\\}\_{n=1}^N}\}$ is the same task as seeking its resolving set.

The next three statements are essential for resolving overlapping sets of intervals.

**S1.**&nbsp; $\\!$ _For any set of intervals, there exists a unique resolving set._  <a name="stmt_1"></a>


**S2.**&nbsp;&nbsp;_Suppose_ $\\{Y\_m\\}\_{m=1}^N$ _is a resolving set for_ $\\{X\_n\\}\_{n=1}^N\\:$, _and_ $\\:x'\_n\\:$, $\\:x''\_n\\:$, $\\:y'\_m\\:$, $\\:y''\_m\\:$ _are the same as_ <a href="#def_x_prime_etc">_above_</a>. _Then_ <a name="stmt_2"></a>

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;**(a)**&nbsp;
$\\:\displaystyle{\\{y'\_m\\}\_{m = 1}^{M}} \subseteq \displaystyle{\\{x'\_n\\}\_{n = 1}^{N}}\\;$, $\displaystyle{\\{y''\_m\\}\_{m = 1}^{M}} \subseteq \displaystyle{\\{x''\_n\\}\_{n = 1}^{N}}\\;$ ;

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;**(b)**&nbsp;
$\\,\displaystyle{x'\_{n\_0} \in \\{y'\_m\\}\_{m = 1}^{M}}$ _if and only if the inequality_ $x'\_n < x'\_{n\_0} \leq x''\_{n}$ _holds for no_ $X\_n\\:$ , _and_

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
$\\:\displaystyle{x''\_{n\_0} \in \\{y''\_m\\}\_{m = 1}^{M}}$ _if and only if the inequality_ $x'\_n \leq x''\_{n\_0} < x''\_{n}$ _holds for no_ $X\_n\\:$.

**S3.**&nbsp; $\\!$ _Any subset of a non-overlapping set of intervals is non-overlapping._   <a name="stmt_3"></a>

These statements are easy to prove, so the proofs are omitted here.

**Note.**&nbsp;
It is readily seen that parts (a) and (b) of statement S2 can be reformulated as follows:<br>
&nbsp;&nbsp; $\\,$ **(a\*)**&nbsp;  $\\!$
the left (right) end of any $Y\_m$ is at the same time the left (right) end of some $X\_n$; <br>
&nbsp;&nbsp; $\\,$ **(b\*)** $\\,$
the left end $x'\_{n\_0}$ (right end $x''\_{n\_0}$) of any $X\_{n\_0}$ is at the same time the left (right) end of some $Y\_m$ if and only if<br>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; $\\,$
$x'\_{n\_0}$ $(x''\_{n\_0})$ is neither an interior point nor the right (left) end of some $X\_n\\:$.

#### Algorithm

Statements <a href="#stmt_1">S1</a> and <a href="#stmt_2">S2</a> lead to the following simple algorithm for resolving a set of intervals $\\{X_n\\}\_{n = 1}^{N}\\,.$

1. Exclude from $\\{x’\_n\\}\_{n = 1}^{N}$ any point $x’\_{n\_0}$ if there is an interval $X\_n$ such that $$x'\_n < x'\_{n\_0} \leq x''\_{n}\\:.$$
2. Arrange the rest of $x’\_n$ in ascending order; this gives $\\{y’\_m\\}\_{m=1}^M$ with some $M\\:.$
3. Repeat steps 1 and 2 for $\\{x’'\_n\\}\_{n = 1}^{N}$ and the inequality $$x'\_n \leq x''\_{n\_0} < x''\_{n}\\:.$$ This gives $\\{y’'\_m\\}\_{m=1}^M$ with the same $M$ as in step 2.
4. Set $$Y_m := [y’\_m, \\, y’’\_m] \qquad \mbox{\sf{for any}} \quad m = 1, ... , M\\,.$$ This yields $\\{Y_m\\}\_{m = 1}^{M}$ that resolves the original set of intervals $\\{X_n\\}\_{n = 1}^{N}\\,.$

#### Implementation

This algorithm is implemented in four stored procedures: <a href="/src/sprocs/staff_regular_availability/resolve_intvls_sra.sql">**`resolve_intvls_sra()`**</a>, <a href="/src/sprocs/blocked_periods/resolve_intvls_bp.sql">**`resolve_intvls_bp()`**</a>, <a href="/src/sprocs/vehicles_not_in_service/resolve_intvls_nis.sql">**`resolve_intvls_nis()`**</a> and <a href="/src/sprocs/wave_timings/resolve_intvls_wt.sql">**`resolve_intvls_wt()`**</a>. Each of them deals with variants of only one table: `staff_regular_availability`, `blocked_periods`, `vehicles_not_in_service` and `wave_timings` respectively. 

**Note.** Both `resolve_intvls_sra()` and `resolve_intvls_wt()` require that any time interval in `staff_regular_availability` and `wave_timings`  ends on the same day of the week that the interval begins. However, if this is not the case, both procedures can be easily adapted.

The procedure `resolve_intvls_sra()` works basically as follows:

- First, it compares the current <a href="#snapshot_definition">snapshot</a> of `regular_staff_availability` with its modification variant to identify each pair `(user_id, wday)` for which the modification of the corresponding rows includes either changing some original pair `(interval_beginning, interval_end)` or adding a row with a new `(interval_beginning, interval_end)`.
- Second, <a href="#algorithm">the algorithm</a> constructs the resolving sets of time intervals for each set of time intervals related to `(user_id, wday)` identified in the first step.
- Third, the procedure replaces the rows containing the pairs (user_id, wday) identified in the first step with the constructed resolving sets.

As it follows from <a href="#stmt_3">S3</a>, there is no need for any additional actions if some rows have been deleted from the variant, so the third step completes the resolution process.

The data transformation processes carried out by `resolve_intvls_bp()`, `resolve_intvls_nis()` and `resolve_intvls_wt()`  are similar to what `resolve_intvls_sra()` does. For detail, see comments in <a href="/src/sprocs/staff_regular_availability/resolve_intvls_sra.sql">`resolve_intvls_sra.sql`</a> <a href="/src/sprocs/blocked_periods/resolve_intvls_bp.sql">`resolve_intvls_bp.sql`</a>, <a href="/src/sprocs/vehicles_not_in_service/resolve_intvls_nis.sql">`resolve_intvls_nis.sql`</a> and <a href="/src/sprocs/wave_timings/resolve_intvls_wt.sql">`resolve_intvls_wt.sql`</a>


### Comparing OM shipping datasets. Stored procedure compare_variants()

Sometimes managing shipping resources may need us to compare datasets contained in identically structured tables, and it would be helpful to have a tool making such comparisons easier. To illustrate this, consider an extremely simple example.

#### Example

Suppose that on Tuesdays the employee with `user_id = 1` is available throughout two intervals:



| `user_id`  | `wday`  | `interval_beginning`  | `interval_end`  |
| ---------- | ------- | --------------------- | --------------- |
|  1         | 3       | 09:00                 | 12:00           |
|  1         | 3       | 15:00                 | 17:00           |

and we have two options for adding a new availability interval: either


<table>
  <tr>
    	<td>1&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td>
    	<td>3&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td>
    	<td>13:30&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td>
	<td>14:30&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td>
  </tr>
</table>

or

<table>
  <tr>
    	<td>1&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td>
    	<td>3&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td>
    	<td>14:00&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td>
	<td>15:00&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td>
  </tr>
</table>

After inserting and resolving the obtained set of intervals (see <a href="#resolving_set_definition">above</a>), we get in each case respectively the tables `t_1`

| `user_id`  | `wday`  | `interval_beginning`  | `interval_end`  |
| ---------- | ------- | --------------------- | --------------- |
| 1          | 3       | 09:00                 | 12:00           |
| 1          | 3       | 13:30                 | 14:30           |
| 1          | 3       | 15:00                 | 17:00           |

and `t_2` 

| `user_id`  | `wday`  | `interval_beginning`  | `interval_end`  |
| ---------- | ------- | --------------------- | --------------- |
| 1          | 3       | 09:00                 | 12:00           |
| 1          | 3       | 14:00                 | 17:00           |

These are the two datasets &mdash; or two dataset variants &mdash; we need to compare to make our choice.

To make the difference between the variants `t_1` and `t_2` more apparent, we could use a **comparison table** <a name = "cmpr_simple"></a>`cmpr_simple` that presents the data in immediate juxtaposition:


| `user_id`  | `wday`  | `t_1_interval_beginning`             | `t_1_interval_end`                 | `t_2_interval_beginning`           | `t_2_interval_end`                 |
| ---------- | ------- | ------------------------------------ | ---------------------------------- | ---------------------------------- | ---------------------------------- |
| 1          | 3       | 09:00                                | 12:00                              | 09:00                              | 12:00                              |
| 1          | 3       | 13:30                                | 14:30                              | $\textcolor{blue}{\textsf{NULL}}$  | $\textcolor{blue}{\textsf{NULL}}$    |
| 1          | 3       | $\textcolor{blue}{\textsf{NULL}}$    | $\textcolor{blue}{\textsf{NULL}}$  | 14:00                              | 17:00                              |
| 1          | 3       | 15:00                                | 17:00                              | $\textcolor{blue}{\textsf{NULL}}$  | $\textcolor{blue}{\textsf{NULL}}$    |


In MySQL, which ***doesn't support the full outer join operation***, this can be done in two steps.

**Step 1.** Create two tables `LJ_1` and `LJ_2`: `LJ_1` as
```sql
SELECT 
	  user_id, wday
	, t_1.interval_beginning t_1_interval_beginning
	, t_1.end t_2_interval_end
	, t_2.interval_beginning t_2_interval_beginning
	, t_2.interval_end t_2_end
FROM t_1
LEFT JOIN t_2
USING (user_id, wday, interval_beginning, interval_end)
```
and `LJ_2` as
```sql
SELECT 
	  user_id, wday
	, t_1.interval_beginning t_1_interval_beginning
	, t_1.end t_2_interval_end
	, t_2.interval_beginning t_2_interval_beginning
	, t_2.interval_end t_2_end
FROM t_2
LEFT JOIN t_1
USING (user_id, wday, interval_beginning, interval_end)
```

**Step 2.** Perform the UNION operation
```sql
SELECT * FROM LJ_1
UNION
SELECT * FROM LJ_2
ORDER BY user_id, wday
```
The output is <a href = "#cmpr_simple">`cmpr_simple`</a>.
	
#### The general case
	
When we need to compare larger and more complex datasets (e.g. a `staff_regular_availability` with numerous users and multiple days of the week) as well as three or more dataset variants, employing the comparison table approach can be considerably more effective than in the above simplistic example. The following explains how this approach can be generalized for the case of an arbitrary table and any number of dataset variants. 
	
As a generalization of the `staff_regular_availability` table, consider a table (denote it by `tb`) that has the structure 
	
| `id_1` | ... | `id_imax` | `dat_1` | ... | `dat_dmax` |
| ------ | ----| --------- | ------- | --- | ---------- |
	
with 
- columns `id_i` (`i = 1, ... , imax`) instead of `user_id` and `wday`,
- columns `dat_d` (`d = 1, ... , dmax`) instead of `interval_beginning` and `interval_end`, 

where the numbers `imax` and `dmax` are arbitrary. 

Suppose we need to compare a number of `tb` dataset versions `t_k` (`k = 1, ... , kmax`). Our goal is to create an analogue of <a href = "#cmpr_simple">`cmpr_simple`</a> &mdash; a comparison table <a name="cmpr"></a>**`cmpr`** with columns
	
| `id_1` | ... | `id_imax` | `t_1_dat_1` | ... | `t_1_dat_dmax` | ... ... | `t_kmax_dat_1` | ... | `t_kmax_dat_dmax` |
| ------ | ----| --------- | ----------- | --- | -------------- | --------| -------------- | --- | ----------------- |

and, like in the case of `cmpr_simple`, we can achieve this in two steps.

**Step 1.** Create tables `LJ_k` (`k = 1, ... , kmax`) as
```sql
SELECT 
	  id_1, ... , id_imax
	, t_1.dat_1 t_1_dat_1
	...
	, t_1.dat_dmax t_1_dat_dmax
	...
	...
	, t_kmax.dat_1 t_kmax_dat_1
	...
	, t_kmax.dat_dmax t_kmax_dat_dmax
FROM <LJ_string_k>
USING (id_1, ... , id_imax, dat_1, ... dat_dmax)
```
where

```sql
<LJ_string_1> = t_1 LEFT JOIN t_2 ... ... LEFT JOIN t_(kmax - 1) LEFT JOIN t_kmax,
<LJ_string_2> = t_2 LEFT JOIN t_3 ... ... LEFT JOIN t_kmax, LEFT JOIN t_1,
... ,
... ,
<LJ_string_kmax> = t_kmax LEFT JOIN t_1 ... ... LEFT JOIN t_kmax, LEFT JOIN t_(kmax - 1).
```
or, more formally, `t_k` (`k = 1, ... , kmax`) in `LJ_string_1` are arranged in ascending order, and `LJ_string_k` is obtained from `LJ_string_1` by the
`(k - 1)`-th <a href="https://en.wikipedia.org/wiki/Cyclic_permutation">cyclic permutation</a> of `t_k`.


**Step 2.** Perform the UNION operation
```sql
SELECT * FROM LJ_1
UNION
SELECT * FROM LJ_2
...
...
SELECT * FROM LJ_kmax
ORDER BY id_1, ... , id_imax
```
that will deliver to us the coveted comparison table <a href="#cmpr">`cmpr`</a>.

#### Implementation

This general-case plan is implemented in the stored procedure <a href="/src/sprocs/compare_variants.sql">`compare_variants()`</a>. 

The procedure has four IN parameters `in_tbs_to_join`, `in_id_cols`, `in_dat_cols`, `cmpr_result` that are table names, which lets us work around the fact that table-valued parameters are not supported in MySQL and pass array data to the procedure.

- `in_tbs_to_join` used to pass `compare_variants()` the name of the table that, in its turn, holds the names of the tables containing the datasets we are going to compare like `t_1`, ... , `t_kmax` above, e.g., referring back to <a href="#example-1">the example above</a>,

	| `id`|              `table_name`  		  | 
	| --- | ----------------------------------------- | 
	| `1` |                 `t_1`   		  | 
	| `2` |                 `t_2`                     | 

- The table passed through `in_id_cols` holds the column names that we use as `id_1`, ... , `id_imax`, e.g.

	| `id`|               `col_name`  		| 
	| --- | --------------------------------------- | 
	| `1` |                `user_id` 	        | 
	| `2` | 		`wday` 			|
- The table passed through `in_dat_cols` holds the column names that we use as `dat_1`, ... , `dat_dmax`, e.g.
	
	| `id`|               `col_name`  		| 
	| --- | --------------------------------------- | 
	| `1` |          `interval_beginning`   	| 
	| `2` | 	    `interval_end` 	        |

	
- And finally, `cmpr_result` is the name of the resulting comparison table, e.g. `cmpr_result` = <a href="#cmpr">`cmpr`</a>.

For more detail, see <a href="/src/sprocs/compare_variants.sql">`compare_variants.sql`</a>.

**Note.** The stored procedure `compare variants()` is essential for the functionality of many other procedures used in the project &mdash; 
for example, those employed to compare datasets in a specific type of table (like <a href="/src/sprocs/blocked_periods/cmpr_variants_bp.sql">`cmpr_variants_bp()`</a> that compares variants of `blocked_periods`) or 
verify whether the current snapshot of an original table is still relevant (like <a href="/src/sprocs/wave_timings/check_diff_wt.sql">`check_diff_wt()`</a> doing this job for blocked_periods).

## Shipping resources management process outline

At the most general level, the management process in the OM shipping system comprises sessions in which individual users can read and modify data in the database.  The organization of the process at this level was discussed <a href="#multi-user-functionality-concurrency-and-isolation-levels">above</a>. 

The following flowchart gives an overall view of the process at its next, single-session level.

![ ](/img/overall_process_outline.svg)
 

### Stage 1

In this stage, the user can modify data in any of the tables `staff_regular_availability`, `blocked_periods`, `vehicles_not_in_service` and `wave_timings`, create (and modify if required) the tables’ variants, or both.
The process separates into independent subprocesses – each subprocess for one of the four tables.

The flowchart below provides details about the subprocess for `staff_regular_availability`.


![ ](/img/process_1a.svg)

**Note.** This scheme doesn’t show most of the operations related to the table’s <a href="#snapshot_definition">snapshot</a>. On this matter, see the code and comments in <a href="/src/sprocs/create_mod.sql">`create_mod.sql`</a>, <a href="/src/sprocs/staff_regular_availability/check_diff_sra.sql">`check_diff_sra.sql`</a> and <a href="/src/sprocs/staff_regular_availability/change_sra.sql">`change_sra.sql`</a>). 

The other three subprocesses follow the same pattern (see the code and comments in <a href="/src/sprocs/blocked_periods">`blocked_periods`</a>, <a href="/src/sprocs/vehicles_not_in_service">`vehicles_not_in_service`</a> and <a href="/src/sprocs/wave_timings">`wave_timings`</a>). 


### Stage 2

The user applies the stored procedures <a href="/src/sprocs/wave_available_staff/get_ws.sql">`get_ws()`</a> and <a href="/src/sprocs/wave_available_vehicles/get_wv.sql">`get_wv()`</a> to all or some selected combinations of the original tables `staff_regular_availability`, `blocked_periods`, `vehicles_not_in_service`, `wave_timings`, and their variants created in Stage 1, which results in creating variants of `wave_staff_availability` and `wave_vehicle_availability`.


### Stage 3

The user reviews the `wave_staff_availability` and `wave_vehicle_availability` variants to decide on the choice of variants of `staff_regular_availability`, `blocked_periods`, `vehicles_not_in_service`, `wave_timings`. If the user needs to compare variants of `wave_staff_availability` and/or `wave_vehicle_availability`, the stored procedures <a href="/src/sprocs/wave_available_staff/cmpr_variants_ws.sql">`cmpr_variants_ws()`</a> and <a href="/src/sprocs/wave_available_staff/cmpr_variants_wv.sql">`cmpr_variants_wv()`</a> can be utilized for that.

If for any of the four tables, none of the variants is adequate, the user returns to Stage 1 and creates new variants of this table, then proceeds to Stages 2 and 3.

Otherwise, the user selects the optimal variant for each of the tables `staff_regular_availability`, `blocked_periods`, `vehicles_not_in_service` and `wave_timings` and converts the selected variant into the corresponding table; <a href="/src/sprocs/staff_regular_availability/change_sra.sql">`change_sra()`</a>, <a href="/src/sprocs/blocked_periods/change_bp.sql">`change_bp()`</a>, <a href="/src/sprocs/vehicles_not_in_service/change_nis.sql">`change_nis()`</a> and <a href="/src/sprocs/wave_timings/change_wt.sql">`change_wt()`</a> are used for such conversions.


## Further development

- In this project, there are data flows that are very much alike, but each of them is run by a stored procedure specific to this data flow –  for example, <a href="/src/sprocs/staff_regular_availability/change_sra.sql">`change_sra()`</a>, <a href="/src/sprocs/blocked_periods/change_bp.sql">`change_bp()`</a>, <a href="/src/sprocs/vehicles_not_in_service/change_nis.sql">`change_nis()`</a> and <a href="/src/sprocs/wave_timings/change_wt.sql">`change_wt()`</a> make changes in `staff_regular_availability`, `blocked_periods`,  `vehicles_not_in_service` and `wave_timings` respectively. With more extensive use of dynamic SQL (similar to that in <a href="/src/sprocs/create_mod.sql">`create_mod()`</a>), such a set of specific stored procedures can be replaced by a single procedure.
- Currently, every OM shipping system user has the same data access privileges as those granted to the user on the entire OM database. If the shipping system privileges need another configuration, this can be done either through using MySQL row-level security solutions, or via adjusting the SQL SECURITY clause values in the project’s stored procedures, or by a combination of both means.


## Acknowledgements

I would like to thank Alek Mlynek for the idea of this project. Also, I am deeply grateful to Tue Hoang for his invaluable guidance that helped me better understand the SQL concepts and tools I used in the project. 


