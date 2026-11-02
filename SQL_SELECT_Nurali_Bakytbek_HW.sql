/*
Part 1: 

    1. The marketing team needs a list of animation movies between 2017 and 2019 to promote family-friendly content in an upcoming season in stores. Show all animation movies released during this period with rate more than 1, sorted alphabetically
*/

-- JOIN
select f.title, f.release_year, f.rental_rate 
FROM film f
INNER JOIN film_category fc using (film_id)
INNER JOIN category c using (category_id)
WHERE c.name = 'Animation'
	AND f.release_year between 2017 and 2019
	AND f.rental_rate > 1
ORDER BY f.title;
-- I used INNER JOIN because it returns only the rows that have matching values in both tables, which is necessary to filter for animation movies. Cons are that it may exclude some movies if they are not categorized correctly.

-- Subquery 
SELECT f.title, f.release_year, f.rental_rate 
FROM film f
WHERE f.release_year between 2017 and 2019
	AND f.rental_rate > 1
	AND f.film_id in (
		SELECT fc.film_id 
		FROM film_category fc 
		WHERE fc.category_id = (
			SELECT c.category_id
			FROM category c 
			WHERE c.name = 'Animation'))
order BY f.title;
-- I used a Subquery in where clause to filter the films based on their category. The advantage is that it allows for a more straightforward filtering of animation movies, but it may be less efficient than a JOIN.

-- CTE
WITH AnimationFilms AS (
    SELECT fc.film_id
    FROM film_category fc
    INNER JOIN category c using (category_id)
    WHERE c.name = 'Animation')
SELECT 
    f.title, 
    f.release_year, 
    f.rental_rate
FROM film f
INNER JOIN AnimationFilms af using (film_id)
WHERE f.release_year BETWEEN 2017 AND 2019
    AND f.rental_rate > 1
ORDER BY f.title ASC;
-- Here, to create CTE, I first filtered the animation films in a separate query and then joined it with the main film table to get the required details. This approach improves readability and maintainability of the query.

/*
    2. The finance department requires a report on store performance to assess profitability and plan resource allocation for stores after March 2017. Calculate the revenue earned by each rental store after March 2017 (since April) (include columns: address and address2 – as one column, revenue)
*/

-- JOIN 
SELECT 
    a.address || COALESCE(', ' || NULLIF(a.address2, ''), '') AS store_address,
    SUM(p.amount) AS revenue
FROM payment p
INNER JOIN staff st using (staff_id)
INNER JOIN store s using (store_id)
INNER JOIN address a 
    ON s.address_id = a.address_id
WHERE p.payment_date >= '2017-04-01'
GROUP BY 
    a.address, 
    a.address2;
-- Inner join because by combining tables to get the required information from multiple tables.

-- Subquery
SELECT 
    (SELECT a.address || COALESCE(', ' || NULLIF(a.address2, ''), '') 
     FROM address a 
     WHERE a.address_id = s.address_id) AS store_address,
    SUM(p.amount) AS revenue
from payment p
inner join staff st using (staff_id)
inner join store s using (store_id)
WHERE p.payment_date >= '2017-04-01'
GROUP BY s.address_id;
-- Used subquery to fetch the address details for each store.

-- CTE
with Store_Ad as (
	SELECT store_id, a.address || COALESCE(', ' || NULLIF(a.address2, ''), '') AS store_address
	FROM store s
	inner join address a on s.address_id = a.address_id)
select sa.store_address, sum(p.amount)
from payment p 
inner join staff st using (staff_id)
inner join Store_Ad sa using (store_id)
where p.payment_date >= '2017-04-01'
GROUP BY sa.store_address;
-- CTE used to create a temporary result set for store addresses, which is then joined with the payment data to calculate revenue.

/*
    3. The marketing department in our stores aims to identify the most successful actors since 2015 to boost customer interest in their films. Show top-5 actors by number of movies (released since 2015) they took part in (columns: first_name, last_name, number_of_movies, sorted by number_of_movies in descending order)
*/

-- JOIN
SELECT 
    a.first_name,
    a.last_name,
    COUNT(f.film_id) AS number_of_movies
FROM actor a 
inner join film_actor fa using (actor_id)
inner join film f using (film_id)
WHERE f.release_year >= 2015
GROUP BY 
    a.actor_id,
    a.first_name,
    a.last_name
ORDER by number_of_movies desc
LIMIT 5;
-- I prefer using when there is inner join, as it allows me to combine data from multiple tables efficiently.

-- Subquery
SELECT 
	a.first_name,
	a.last_name,
	ac.number_of_movies
FROM actor a
INNER JOIN (
	SELECT fa.actor_id, count(f.film_id) number_of_movies
	FROM film_actor fa 
	INNER join film f USING (film_id)
	WHERE f.release_year >= 2015
	GROUP by fa.actor_id) as ac USING (actor_id)
ORDER BY ac.number_of_movies DESC
LIMIT 5;
-- The result of the 5th is diffeerent from others, because it filters them using acotr_id. Not sure how to fix it.

-- CTE
WITH RecentFilms AS (
    SELECT film_id
    FROM film
    WHERE release_year >= 2015
)
SELECT 
    a.first_name,
    a.last_name,
    COUNT(rf.film_id) AS number_of_movies
FROM actor a
INNER JOIN film_actor fa using (actor_id)
INNER JOIN RecentFilms rf using (film_id)
GROUP BY 
    a.actor_id,
    a.first_name,
    a.last_name
ORDER BY number_of_movies DESC
LIMIT 5;
-- Same results as JOIN, but CTE improves readability and maintainability of the query by separating the filtering logic for recent films into a distinct section.

/*
    4. The marketing team needs to track the production trends of Drama, Travel, and Documentary films to inform genre-specific marketing strategies. Show number of Drama, Travel, Documentary per year (include columns: release_year, number_of_drama_movies, number_of_travel_movies, number_of_documentary_movies), sorted by release year in descending order. Dealing with NULL values is encouraged)

*/

-- JOIN
SELECT 
    f.release_year,
    COALESCE(SUM(CASE WHEN c.name = 'Drama' THEN 1 ELSE 0 END), 0) AS number_of_drama_movies,
    COALESCE(SUM(CASE WHEN c.name = 'Travel' THEN 1 ELSE 0 END), 0) AS number_of_travel_movies,
    COALESCE(SUM(CASE WHEN c.name = 'Documentary' THEN 1 ELSE 0 END), 0) AS number_of_documentary_movies
FROM film f
LEFT JOIN film_category fc 
    ON f.film_id = fc.film_id
LEFT JOIN category c 
    ON fc.category_id = c.category_id 
    AND c.name IN ('Drama', 'Travel', 'Documentary')
GROUP BY f.release_year
ORDER BY f.release_year DESC;
-- I used LEFT JOIN to include all release years, even if there are no movies in a specific genre for that year. This ensures that I get a complete view of the number of movies released each year for the specified genres.

-- Sub query
-- i skipped this, because i felt stuck

-- CTE
WITH TargetGenres AS (
    SELECT 
        f.release_year,
        c.name AS genre
    FROM film f
    INNER JOIN film_category fc using (film_id)
    INNER JOIN category c using (category_id)
    WHERE c.name IN ('Drama', 'Travel', 'Documentary')
)
SELECT 
    f_years.release_year,
    COUNT(CASE WHEN tg.genre = 'Drama' THEN 1 END) AS number_of_drama_movies,
    COUNT(CASE WHEN tg.genre = 'Travel' THEN 1 END) AS number_of_travel_movies,
    COUNT(CASE WHEN tg.genre = 'Documentary' THEN 1 END) AS number_of_documentary_movies
FROM (SELECT DISTINCT release_year FROM  film) f_years
LEFT JOIN TargetGenres tg 
    ON f_years.release_year = tg.release_year
GROUP BY f_years.release_year
ORDER BY f_years.release_year DESC;
-- CTE used to filter the target genres first, and then joined with a distinct list of release years to ensure that all years are represented in the final result, even if there are no movies in a specific genre for that year.

/*
Part 2:

    1. The HR department aims to reward top-performing employees in 2017 with bonuses to recognize their contribution to stores revenue. Show which three employees generated the most revenue in 2017? 

Assumptions: 
- staff could work in several stores in a year, please indicate which store the staff worked in (the last one);
- if staff processed the payment then he works in the same store; 
- take into account only payment_date

*/

-- JOIN
SELECT 
    s.first_name,
    s.last_name,
    agg.total_revenue,
    MAX(i.store_id) AS last_store_id
FROM  staff s
INNER join (
    SELECT staff_id, 
        SUM(amount) AS total_revenue, 
        MAX(payment_date) AS max_payment_date
    FROM payment
    WHERE EXTRACT(YEAR FROM payment_date) = 2017
    GROUP BY staff_id) agg ON s.staff_id = agg.staff_id
INNER JOIN payment p_last 
    on agg.staff_id = p_last.staff_id
    AND agg.max_payment_date = p_last.payment_date
INNER JOIN rental r using (rental_id)
INNER JOIN inventory i using (inventory_id)
GROUP BY 
    s.first_name,
    s.last_name,
    agg.total_revenue
ORDER BY agg.total_revenue DESC
LIMIT 3;
-- By aggrigation reduces the num of rows. A lot of joins which can be slow on big datasets.

-- Subquery
SELECT 
    s.first_name,
    s.last_name,
    (
        SELECT SUM(p.amount) 
        FROM  payment p 
        WHERE p.staff_id = s.staff_id 
          AND EXTRACT(YEAR FROM p.payment_date) = 2017
    ) AS total_revenue,
    (
        SELECT MAX(i.store_id) 
        FROM  payment p
        INNER join  rental r using (rental_id)
        INNER JOIN  inventory i using (inventory_id)
        WHERE p.staff_id = s.staff_id 
          AND p.payment_date = (
              SELECT MAX(p2.payment_date) 
              FROM  payment p2 
              WHERE p2.staff_id = s.staff_id 
                AND EXTRACT(YEAR FROM p2.payment_date) = 2017
          )
    ) AS last_store_id
FROM  staff s
ORDER BY total_revenue DESC
LIMIT 3;
-- Pros: The subquery allows to calculate the number of rentals for each movie without needing to join multiple tables, which can simplify the query. Cons: It may be less efficient than using JOINs, especially if the rental table is large, as it requires executing the subquery for each film.

-- CTE
WITH StaffRevenue AS (
    SELECT 
        p.staff_id,
        SUM(p.amount) AS total_revenue,
        MAX(p.payment_date) AS last_payment_date
    FROM  payment p
    WHERE EXTRACT(YEAR FROM p.payment_date) = 2017
    GROUP BY p.staff_id
),
LastTransaction AS (
    SELECT 
        p.staff_id,
        p.payment_date,
        i.store_id
    FROM  payment p
    INNER JOIN  rental r using (rental_id)
    INNER JOIN  inventory i using (inventory_id)
)
SELECT 
    s.first_name,
    s.last_name,
    sr.total_revenue,
    MAX(lt.store_id) AS last_store_id
FROM  staff s
INNER JOIN StaffRevenue sr using (staff_id)
INNER JOIN LastTransaction lt 
    ON sr.staff_id = lt.staff_id 
    AND sr.last_payment_date = lt.payment_date
GROUP BY 
    s.first_name,
    s.last_name,
    sr.total_revenue
ORDER BY sr.total_revenue DESC
LIMIT 3;
-- Great readability. Cons - none.


/*
    2. The management team wants to identify the most popular movies and their target audience age groups to optimize marketing efforts. Show which 5 movies were rented more than others (number of rentals), and what's the expected age of the audience for these movies? To determine expected age please use 'Motion Picture Association film rating system'
*/

-- JOIN
SELECT f.title,
    COUNT(r.rental_id) AS number_of_rentals,
    CASE f.rating
        WHEN 'G' THEN 'All ages'
        WHEN 'PG' THEN '7 and older'
        WHEN 'PG-13' THEN '13 and older'
        WHEN 'R' THEN '17 and older'
        WHEN 'NC-17' THEN '18 and older'
        ELSE 'Unknown'
    END AS expected_audience_age
FROM  film f
INNER JOIN  inventory i using (film_id)
INNER JOIN  rental r USING (inventory_id)
GROUP BY f.title, f.rating
ORDER BY number_of_rentals DESC
LIMIT 5;
-- Combining the film, inventory, and rental tables allows to count the number of rentals for each movie and determine the expected audience age based on the film rating. The JOINs ensure that only  films that have been rented.

-- Subquery
SELECT f.title,
    (SELECT COUNT(r.rental_id)
     FROM  rental r
     INNER JOIN  inventory i using (inventory_id)
     WHERE i.film_id = f.film_id) AS number_of_rentals,
    CASE f.rating
        WHEN 'G' THEN 'All ages'
        WHEN 'PG' THEN '7 and older'
        WHEN 'PG-13' THEN '13 and older'
        WHEN 'R' THEN '17 and older'
        WHEN 'NC-17' THEN '18 and older'
        ELSE 'Unknown'
    END AS expected_audience_age
FROM  film f
ORDER BY number_of_rentals DESC
LIMIT 5;
-- Pros: The subquery allows to calculate the number of rentals for each movie without needing to join multiple tables, which can simplify the query. Cons: It may be less efficient than using JOINs, especially if the rental table is large, as it requires executing the subquery for each film.

-- CTE
WITH MovieRentals AS (
    SELECT 
        i.film_id,
        COUNT(r.rental_id) AS number_of_rentals
    FROM  inventory i
    INNER JOIN  rental r 
        ON i.inventory_id = r.inventory_id
    GROUP BY i.film_id)
SELECT 
    f.title,
    mr.number_of_rentals,
    CASE f.rating
        WHEN 'G' THEN 'All ages'
        WHEN 'PG' THEN '7 and older'
        WHEN 'PG-13' THEN '13 and older'
        WHEN 'R' THEN '17 and older'
        WHEN 'NC-17' THEN '18 and older'
        ELSE 'Unknown'
    END AS expected_audience_age
FROM  film f
INNER JOIN MovieRentals mr 
    ON f.film_id = mr.film_id
ORDER BY mr.number_of_rentals DESC
LIMIT 5;
-- Pros: Readability and maintainability. Cons: Slightly more complex than a simple JOIN.



/*
Part 3. Which actors/actresses didn't act for a longer period of time than the others? 

    The stores’ marketing team wants to analyze actors' inactivity periods to select those with notable career breaks for targeted promotional campaigns, highlighting their comebacks or consistent appearances to engage customers with nostalgic or reliable film stars

The task can be interpreted in various ways, and here are a few options (provide solutions for each one):
*/

-- V1: gap between the latest release_year and current year per each actor;

-- join
SELECT 
    a.first_name,
    a.last_name,
    EXTRACT(YEAR FROM CURRENT_DATE) - MAX(f.release_year) AS years_since_last_film
FROM public.actor a
INNER JOIN public.film_actor fa 
    ON a.actor_id = fa.actor_id
INNER JOIN public.film f 
    ON fa.film_id = f.film_id
GROUP BY 
    a.actor_id,
    a.first_name,
    a.last_name
ORDER BY years_since_last_film DESC;

-- subquery
SELECT 
    a.first_name,
    a.last_name,
    EXTRACT(YEAR FROM CURRENT_DATE) - (
        SELECT MAX(f.release_year)
        FROM public.film_actor fa
        INNER JOIN public.film f 
            ON fa.film_id = f.film_id
        WHERE fa.actor_id = a.actor_id
    ) AS years_since_last_film
FROM public.actor a
ORDER BY years_since_last_film DESC;

-- CTE
WITH LatestFilms AS (
    SELECT 
        fa.actor_id,
        MAX(f.release_year) AS last_release
    FROM public.film_actor fa
    INNER JOIN public.film f 
        ON fa.film_id = f.film_id
    GROUP BY fa.actor_id
)
SELECT 
    a.first_name,
    a.last_name,
    EXTRACT(YEAR FROM CURRENT_DATE) - lf.last_release AS years_since_last_film
FROM public.actor a
INNER JOIN LatestFilms lf 
    ON a.actor_id = lf.actor_id
ORDER BY years_since_last_film DESC;


--  V2: gaps between sequential films per each actor;

-- join
SELECT 
    a.first_name, 
    a.last_name,
    MAX(gaps.next_year - gaps.current_year) AS max_career_gap
FROM public.actor a
INNER JOIN (
    SELECT 
        af1.actor_id,
        af1.release_year AS current_year,
        MIN(af2.release_year) AS next_year
    FROM (
        SELECT DISTINCT fa.actor_id, f.release_year
        FROM public.film_actor fa
        INNER JOIN public.film f ON fa.film_id = f.film_id
    ) af1
    INNER JOIN (
        SELECT DISTINCT fa.actor_id, f.release_year
        FROM public.film_actor fa
        INNER JOIN public.film f ON fa.film_id = f.film_id
    ) af2 ON af1.actor_id = af2.actor_id AND af1.release_year < af2.release_year
    GROUP BY af1.actor_id, af1.release_year
) gaps ON a.actor_id = gaps.actor_id
GROUP BY 
    a.actor_id, 
    a.first_name, 
    a.last_name
ORDER BY max_career_gap DESC;

-- subquery
SELECT 
    a.first_name,
    a.last_name,
    MAX(
        (SELECT MIN(f2.release_year) 
         FROM public.film_actor fa2 
         INNER JOIN public.film f2 
             ON fa2.film_id = f2.film_id 
         WHERE fa2.actor_id = a.actor_id 
           AND f2.release_year > f1.release_year) 
        - f1.release_year
    ) AS max_career_gap
FROM public.actor a
INNER JOIN public.film_actor fa 
    ON a.actor_id = fa.actor_id
INNER JOIN public.film f1 
    ON fa.film_id = f1.film_id
GROUP BY 
    a.actor_id, 
    a.first_name, 
    a.last_name
ORDER BY max_career_gap DESC;

-- CTE
WITH ActorFilms AS (
    SELECT DISTINCT 
        fa.actor_id, 
        f.release_year
    FROM public.film_actor fa
    INNER JOIN public.film f 
        ON fa.film_id = f.film_id
),
NextFilms AS (
    SELECT 
        af1.actor_id,
        af1.release_year AS current_year,
        MIN(af2.release_year) AS next_year
    FROM ActorFilms af1
    INNER JOIN ActorFilms af2 
        ON af1.actor_id = af2.actor_id 
        AND af1.release_year < af2.release_year
    GROUP BY 
        af1.actor_id, 
        af1.release_year
)
SELECT 
    a.first_name, 
    a.last_name,
    MAX(nf.next_year - nf.current_year) AS max_career_gap
FROM public.actor a
INNER JOIN NextFilms nf 
    ON a.actor_id = nf.actor_id
GROUP BY 
    a.actor_id, 
    a.first_name, 
    a.last_name
ORDER BY max_career_gap DESC;