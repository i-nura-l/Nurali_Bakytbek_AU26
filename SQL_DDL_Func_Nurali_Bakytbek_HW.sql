-- all objects are in schema core

CREATE SCHEMA IF NOT EXISTS core;


/* Task 1
View shows category and total revenue for current quarter and year. Quarter and year are taken with
EXTRACT from CURRENT_DATE, so it is calculated every time you select and when new quarter starts
view moves to it by itself. Revenue is SUM of payment.amount, I go payment -> rental -> inventory ->
film_category -> category with inner joins, so category without payments in this quarter just dont
get any rows and is not shown. HAVING SUM > 0 also removes categories with 0 sum.

DB has payments only for 2017 so now view returns 0 rows, it is ok. I checked the logic with function
from task 2 (same query but with date param), for '2017-04-15' it gives 16 categories with revenue.

Should NOT appear: payments from other quarter (Q1 when now is Q2), same quarter but other year
(Q2 2016), category that had no sales this quarter.
*/
CREATE OR REPLACE VIEW core.sales_revenue_by_category_qtr AS
SELECT c.name        AS category,
       SUM(p.amount) AS total_sales_revenue
FROM payment p
JOIN rental r         ON r.rental_id = p.rental_id
JOIN inventory i      ON i.inventory_id = r.inventory_id
JOIN film_category fc ON fc.film_id = i.film_id
JOIN category c       ON c.category_id = fc.category_id
WHERE EXTRACT(QUARTER FROM p.payment_date) = EXTRACT(QUARTER FROM CURRENT_DATE)
  AND EXTRACT(YEAR FROM p.payment_date)    = EXTRACT(YEAR FROM CURRENT_DATE)
GROUP BY c.name
HAVING SUM(p.amount) > 0;

-- test: works, 0 rows now because no 2026 data. no input here so no invalid case
SELECT * FROM core.sales_revenue_by_category_qtr ORDER BY total_sales_revenue DESC;


/* Task 2
Same as view but quarter and year come from parameter. Param is needed because view shows only
current quarter and we have no data now, with param I can check any quarter like Q2 2017.
Param is a date, quarter and year are taken from it. Default is CURRENT_DATE, NULL also becomes CURRENT_DATE.

1) invalid quarter - you cant pass quarter 5 because it comes from date, and wrong date like '2017-13-01'
gives postgres error on cast before function even starts
2) no data - just 0 rows, no error
It is sql function so no RAISE here, sql functions cant do it.
*/
CREATE OR REPLACE FUNCTION core.get_sales_revenue_by_category_qtr(p_date DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (category TEXT, total_sales_revenue NUMERIC)
LANGUAGE sql
AS $$
    SELECT c.name, SUM(p.amount)
    FROM payment p
    JOIN rental r         ON r.rental_id = p.rental_id
    JOIN inventory i      ON i.inventory_id = r.inventory_id
    JOIN film_category fc ON fc.film_id = i.film_id
    JOIN category c       ON c.category_id = fc.category_id
    WHERE EXTRACT(QUARTER FROM p.payment_date) = EXTRACT(QUARTER FROM COALESCE(p_date, CURRENT_DATE))
      AND EXTRACT(YEAR FROM p.payment_date)    = EXTRACT(YEAR FROM COALESCE(p_date, CURRENT_DATE))
    GROUP BY c.name
    HAVING SUM(p.amount) > 0;
$$;

-- valid, Q2 2017
SELECT * FROM core.get_sales_revenue_by_category_qtr('2017-04-15') ORDER BY 2 DESC;
-- no param, same as view
SELECT * FROM core.get_sales_revenue_by_category_qtr();
-- year without data, 0 rows
SELECT * FROM core.get_sales_revenue_by_category_qtr('1999-01-01');
-- wrong date, error date/time field value out of range
-- SELECT * FROM core.get_sales_revenue_by_category_qtr('2017-13-01');


/* Task 3
Most popular film = film with most rentals by customers from that country (customer -> address ->
city -> country). For ties I use RANK so all films with max count are returned, Afghanistan has few
rentals so it gives many films. Country name is not case sensitive and spaces are trimmed.
If country not in country table -> exception. If country exists but no rentals -> notice and no rows
for it, other countries still work. Empty or NULL array -> exception.
*/
CREATE OR REPLACE FUNCTION core.most_popular_films_by_countries(p_countries TEXT[])
RETURNS TABLE ("Country" TEXT, "Film" TEXT, "Rating" TEXT, "Language" TEXT, "Length" INT, "Release year" INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_country TEXT;
BEGIN
    IF p_countries IS NULL OR cardinality(p_countries) = 0 THEN
        RAISE EXCEPTION 'country list is empty, pass at least one country';
    END IF;

    FOREACH v_country IN ARRAY p_countries LOOP
        IF NOT EXISTS (SELECT 1 FROM country co WHERE LOWER(co.country) = LOWER(TRIM(v_country))) THEN
            RAISE EXCEPTION 'country "%" not found', v_country;
        END IF;

        RETURN QUERY
        WITH cnt AS (
            SELECT co.country, i.film_id,
                   RANK() OVER (ORDER BY COUNT(r.rental_id) DESC) AS rnk
            FROM rental r
            JOIN customer cu  ON cu.customer_id = r.customer_id
            JOIN address a    ON a.address_id = cu.address_id
            JOIN city ci      ON ci.city_id = a.city_id
            JOIN country co   ON co.country_id = ci.country_id
            JOIN inventory i  ON i.inventory_id = r.inventory_id
            WHERE LOWER(co.country) = LOWER(TRIM(v_country))
            GROUP BY co.country, i.film_id
        )
        SELECT cnt.country, f.title, f.rating::TEXT, TRIM(l.name), f.length::INT, f.release_year::INT
        FROM cnt
        JOIN film f     ON f.film_id = cnt.film_id
        JOIN language l ON l.language_id = f.language_id
        WHERE cnt.rnk = 1
        ORDER BY f.title;

        IF NOT FOUND THEN
            RAISE NOTICE 'no rentals for country "%"', v_country;
        END IF;
    END LOOP;
END;
$$;

-- valid
SELECT * FROM core.most_popular_films_by_countries(ARRAY['Afghanistan','Brazil','United States']);
-- lower case and spaces still ok
SELECT * FROM core.most_popular_films_by_countries(ARRAY['  brazil']);
-- error country "Narnia" not found
-- SELECT * FROM core.most_popular_films_by_countries(ARRAY['Narnia']);
-- error country list is empty
-- SELECT * FROM core.most_popular_films_by_countries(ARRAY[]::TEXT[]);


/* Task 4
Films that have at least 1 copy in stock and title matches pattern. In stock means copy has no rental
with return_date IS NULL. Customer and rental date are from the last rental of this film. Row_num is
just counter in loop from 1.

I use ILIKE so it is not case sensitive, '%love%' finds LOVELY and love. % means any chars, so love
can be anywhere. If there is no % in input I add it on both sides.

Performance: ILIKE with % at start cant use normal index so it scans all titles, and rental is the
biggest table. So first I filter films by title and only then check inventory and rental for these
films, not for all. NOT EXISTS stops on first open rental, I dont call inventory_in_stock because it
does 2 counts for every copy. On big data pg_trgm index on title would help.

Many matches -> all rows with numbers 1,2,3... No matches -> notice and one row with message
'not found in stock'. Empty or NULL pattern -> exception.
*/
CREATE OR REPLACE FUNCTION core.films_in_stock_by_title(p_title TEXT)
RETURNS TABLE ("Row_num" BIGINT, "Film title" TEXT, "Language" TEXT, "Customer name" TEXT, "Rental date" TIMESTAMPTZ)
LANGUAGE plpgsql
AS $$
DECLARE
    v_pattern TEXT;
    v_row     BIGINT := 0;
    rec       RECORD;
BEGIN
    IF p_title IS NULL OR TRIM(p_title) = '' THEN
        RAISE EXCEPTION 'title pattern can not be empty';
    END IF;

    v_pattern := TRIM(p_title);
    IF POSITION('%' IN v_pattern) = 0 THEN
        v_pattern := '%' || v_pattern || '%';
    END IF;

    FOR rec IN
        WITH f AS (
            SELECT film_id, title, language_id
            FROM film
            WHERE title ILIKE v_pattern
        ),
        in_stock AS (
            SELECT DISTINCT i.film_id
            FROM inventory i
            JOIN f ON f.film_id = i.film_id
            WHERE NOT EXISTS (SELECT 1 FROM rental r
                              WHERE r.inventory_id = i.inventory_id
                                AND r.return_date IS NULL)
        ),
        last_rent AS (
            SELECT DISTINCT ON (i.film_id) i.film_id, r.customer_id, r.rental_date
            FROM rental r
            JOIN inventory i ON i.inventory_id = r.inventory_id
            WHERE i.film_id IN (SELECT film_id FROM in_stock)
            ORDER BY i.film_id, r.rental_date DESC
        )
        SELECT f.title, TRIM(l.name) AS lang,
               cu.first_name || ' ' || cu.last_name AS cust,
               lr.rental_date
        FROM f
        JOIN in_stock s       ON s.film_id = f.film_id
        JOIN language l       ON l.language_id = f.language_id
        LEFT JOIN last_rent lr ON lr.film_id = f.film_id
        LEFT JOIN customer cu  ON cu.customer_id = lr.customer_id
        ORDER BY f.title
    LOOP
        v_row := v_row + 1;
        "Row_num"       := v_row;
        "Film title"    := rec.title;
        "Language"      := rec.lang;
        "Customer name" := rec.cust;
        "Rental date"   := rec.rental_date;
        RETURN NEXT;
    END LOOP;

    IF v_row = 0 THEN
        RAISE NOTICE 'movie with title % not found in stock', p_title;
        "Row_num"       := NULL;
        "Film title"    := 'movie with title ' || p_title || ' not found in stock';
        "Language"      := NULL;
        "Customer name" := NULL;
        "Rental date"   := NULL;
        RETURN NEXT;
    END IF;
END;
$$;

-- valid, many films
SELECT * FROM core.films_in_stock_by_title('%love%');
-- no % and upper case, same result
SELECT * FROM core.films_in_stock_by_title('LOVE');
-- nothing found, one row with message
SELECT * FROM core.films_in_stock_by_title('%qwertyzzz%');
-- error title pattern can not be empty
-- SELECT * FROM core.films_in_stock_by_title('');


/* Task 5
Inserts new film with rental_rate 4.99, duration 3, replacement_cost 19.99. Year default is current
year, language default Klingon. Klingon is not in language table so I add it first, only if not exists
so script can run again.

1) id - film_id has default nextval of film_film_id_seq, I dont pass it, sequence gives next one.
it is safer than MAX+1 when 2 inserts happen at same time
2) duplicates - before insert I check same title with UPPER and TRIM, if exists -> exception and
nothing inserted
3) language - find language_id by name (TRIM because name is char(20)), not found -> exception
4) also checks empty title and year 1901-2155 because film.release_year domain allows only this
If insert fails the whole function is rolled back, so no half data, maybe only a gap in ids.
fulltext is filled by trigger that already exists. Returns new film_id.
*/
INSERT INTO language (name)
SELECT 'Klingon'
WHERE NOT EXISTS (SELECT 1 FROM language WHERE UPPER(TRIM(name)) = 'KLINGON');

CREATE OR REPLACE FUNCTION core.new_movie(
    p_title        TEXT,
    p_release_year INT  DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INT,
    p_language     TEXT DEFAULT 'Klingon'
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_lang_id INT;
    v_film_id INT;
BEGIN
    IF p_title IS NULL OR TRIM(p_title) = '' THEN
        RAISE EXCEPTION 'movie title can not be empty';
    END IF;

    IF p_release_year IS NULL OR p_release_year NOT BETWEEN 1901 AND 2155 THEN
        RAISE EXCEPTION 'wrong release year: %, must be 1901-2155', p_release_year;
    END IF;

    SELECT language_id INTO v_lang_id
    FROM language
    WHERE UPPER(TRIM(name)) = UPPER(TRIM(COALESCE(p_language, 'Klingon')));

    IF v_lang_id IS NULL THEN
        RAISE EXCEPTION 'language "%" does not exist in language table', p_language;
    END IF;

    IF EXISTS (SELECT 1 FROM film WHERE UPPER(TRIM(title)) = UPPER(TRIM(p_title))) THEN
        RAISE EXCEPTION 'movie "%" already exists', p_title;
    END IF;

    INSERT INTO film (title, release_year, language_id, rental_duration, rental_rate, replacement_cost)
    VALUES (UPPER(TRIM(p_title)), p_release_year, v_lang_id, 3, 4.99, 19.99)
    RETURNING film_id INTO v_film_id;

    RETURN v_film_id;
END;
$$;

/* tests are commented because insert works only once, second run gives duplicate error

-- valid, default year and Klingon
SELECT core.new_movie('My Homework Movie');
SELECT * FROM film WHERE title = 'MY HOMEWORK MOVIE';
-- valid with all params
SELECT core.new_movie('Another Movie', 2020, 'English');
-- error movie already exists
SELECT core.new_movie('my homework movie');
-- error language "Elvish" does not exist
SELECT core.new_movie('Elf Movie', 2020, 'Elvish');
-- error wrong release year
SELECT core.new_movie('Old Movie', 1800);
*/