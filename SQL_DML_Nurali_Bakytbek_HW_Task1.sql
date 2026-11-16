/*
each subtask is in a separate transaction, so if one fails only that part is rolled back
and the parts that were already committed stay. before COMMIT i can do ROLLBACK and nothing
from that part is saved; after COMMIT rollback is not possible.
i use INSERT INTO ... SELECT instead of VALUES so ids are not hardcoded: they are taken from
the parent tables by name, so foreign keys always point to existing rows (referential integrity)
and i can add WHERE NOT EXISTS to avoid duplicates when the script is run again.
*/

/*
1. Favorite Films
uniqueness: film is not inserted if the same title and release year already exist
relationships: language_id is taken from language by name, category_id from category by name
*/
BEGIN;

INSERT into public.film (title, description, release_year, language_id, rental_duration,
                         rental_rate, length, replacement_cost, rating, last_update)
SELECt v.title, v.description, v.release_year, l.language_id, v.rental_duration,
       v.rental_rate, v.length, v.replacement_cost, v.rating::public.mpaa_rating, current_date
FROM (VALUES ('YOUR NAME', 'Two teenagers who have never met start to swap bodies',
              2016, 'Japanese', 7, 4.99, 106, 19.99, 'PG'),
             ('SHERLOCK HOLMES', 'Holmes and Watson stop a lord who uses dark magic in London',
              2009, 'English', 14, 9.99, 128, 24.99, 'PG-13'),
             ('INTERSTELLAR', 'Astronauts travel through a wormhole to find a new home for humanity',
              2014, 'English', 21, 19.99, 169, 29.99, 'PG-13')
     ) AS v(title, description, release_year, lang, rental_duration, rental_rate, length, replacement_cost, rating)
JOIN public.language l on TRIM(l.name) = v.lang
WHERE NOT EXISTS (SELECT 1 FROM public.film f
                  WHERE UPPER(f.title) = v.title and f.release_year = v.release_year)
RETURNING film_id, title, release_year, rental_rate, rental_duration;

INSERT INTO public.film_category (film_id, category_id, last_update)
SELECT f.film_id, c.category_id, current_date
FROM (VALUES ('YOUR NAME', 'Animation'),
             ('SHERLOCK HOLMES', 'Action'),
             ('INTERSTELLAR', 'Sci-Fi')) AS v(title, category)
JOIN public.film f on f.title = v.title
JOIN public.category c ON c.name = v.category
ON CONFLICT (film_id, category_id) DO NOTHING
RETURNING film_id, category_id;

SELECT f.film_id, f.title, f.release_year, f.rental_rate, f.rental_duration, c.name
FROM public.film f
JOIN public.film_category fc ON fc.film_id = f.film_id
JOIN public.category c on c.category_id = fc.category_id
WHERE f.title in ('YOUR NAME', 'SHERLOCK HOLMES', 'INTERSTELLAR');

COMMIT;


/*
2. Actors
uniqueness: actor has no unique key, so i check first_name + last_name (upper case);
if the actor already exists he is not inserted again and the existing actor_id is used
relationships: film_actor gets actor_id from actor and film_id from film by name,
primary key (actor_id, film_id) + ON CONFLICT DO NOTHING prevents duplicate links
*/
BEGIN;

INSERT into public.actor (first_name, last_name, last_update)
SELECT v.first_name, v.last_name, current_date
FROM (VALUES ('RYUNOSUKE', 'KAMIKI'),
             ('MONE', 'KAMISHIRAISHI'),
             ('ROBERT', 'DOWNEY JR.'),
             ('JUDE', 'LAW'),
             ('RACHEL', 'MCADAMS'),
             ('MATTHEW', 'MCCONAUGHEY'),
             ('ANNE', 'HATHAWAY'),
             ('JESSICA', 'CHASTAIN')) AS v(first_name, last_name)
WHERE not exists (SELECT 1 FROM public.actor a
                  WHERE UPPER(a.first_name) = v.first_name AND UPPER(a.last_name) = v.last_name)
RETURNING actor_id, first_name, last_name;

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id, f.film_id, current_date
FROM (VALUES ('RYUNOSUKE', 'KAMIKI', 'YOUR NAME'),
             ('MONE', 'KAMISHIRAISHI', 'YOUR NAME'),
             ('ROBERT', 'DOWNEY JR.', 'SHERLOCK HOLMES'),
             ('JUDE', 'LAW', 'SHERLOCK HOLMES'),
             ('RACHEL', 'MCADAMS', 'SHERLOCK HOLMES'),
             ('MATTHEW', 'MCCONAUGHEY', 'INTERSTELLAR'),
             ('ANNE', 'HATHAWAY', 'INTERSTELLAR'),
             ('JESSICA', 'CHASTAIN', 'INTERSTELLAR')) AS v(first_name, last_name, title)
JOIN public.actor a ON UPPER(a.first_name) = v.first_name AND UPPER(a.last_name) = v.last_name
JOIN public.film f ON f.title = v.title
ON CONFLICT (actor_id, film_id) DO NOTHING
RETURNING actor_id, film_id;

SELECT f.title, a.first_name, a.last_name
FROM public.film_actor fa
JOIN public.actor a on a.actor_id = fa.actor_id
JOIN public.film f ON f.film_id = fa.film_id
WHERE f.title IN ('YOUR NAME', 'SHERLOCK HOLMES', 'INTERSTELLAR');

COMMIT;


/*
3. Inventory
uniqueness: one copy of each film in the store, NOT EXISTS checks film_id + store_id
relationships: film_id from film, store_id from store (found by city Lethbridge)
*/
BEGIN;

INSERT INTO public.inventory (film_id, store_id, last_update)
SELECT f.film_id, s.store_id, current_date
FROM public.film f
CROSS JOIN (SELECT st.store_id
            FROM public.store st
            JOIN public.address ad ON ad.address_id = st.address_id
            JOIN public.city ci ON ci.city_id = ad.city_id
            WHERE ci.city = 'Lethbridge') s
WHERE f.title IN ('YOUR NAME', 'SHERLOCK HOLMES', 'INTERSTELLAR')
  AND NOT EXISTS (SELECT 1 FROM public.inventory i
                  WHERE i.film_id = f.film_id and i.store_id = s.store_id)
RETURNING inventory_id, film_id, store_id;

SELECT i.inventory_id, f.title, i.store_id
FROM public.inventory i
JOIN public.film f ON f.film_id = i.film_id
WHERE f.title IN ('YOUR NAME', 'SHERLOCK HOLMES', 'INTERSTELLAR');

COMMIT;


/*
4. Update customer
the update runs only if there is no customer with my name yet, so after rerun
another customer is not changed. address table is not updated, only address_id.
*/
BEGIN;

SELECT c.customer_id, c.first_name, c.last_name
FROM public.customer c
WHERE (SELECT COUNT(*) FROM public.rental r WHERE r.customer_id = c.customer_id) >= 43
  AND (SELECT COUNT(*) FROM public.payment p WHERE p.customer_id = c.customer_id) >= 43
ORDER BY c.customer_id
LIMIT 1;

UPDATE public.customer
SET first_name = 'NURALI',
    last_name = 'BAKYTBEK UULU',
    email = 'NURALI.BAKYTBEKUULU@sakilacustomer.org',
    address_id = (SELECT address_id FROM public.address WHERE address = '270 Toulon Boulevard'),
    last_update = current_date
WHERE customer_id = (SELECT c.customer_id
                     FROM public.customer c
                     WHERE (SELECT COUNT(*) FROM public.rental r WHERE r.customer_id = c.customer_id) >= 43
                       AND (SELECT COUNT(*) FROM public.payment p WHERE p.customer_id = c.customer_id) >= 43
                     ORDER BY c.customer_id
                     LIMIT 1)
  AND NOT EXISTS (SELECT 1 FROM public.customer
                  WHERE first_name = 'NURALI' AND last_name = 'BAKYTBEK UULU')
RETURNING customer_id, first_name, last_name, email, address_id;

SELECT customer_id, first_name, last_name, email, address_id
FROM public.customer
WHERE first_name = 'NURALI' AND last_name = 'BAKYTBEK UULU';

COMMIT;


/*
5. Delete my records
rows are deleted only by my customer_id, other customers are not touched.
payment is deleted first because it references rental. nothing else references
these rows. customer and inventory are not deleted.
i check the count with SELECT before delete and compare with RETURNING,
if something is wrong i do ROLLBACK instead of COMMIT
*/
BEGIN;

SELECT (SELECT COUNT(*) FROM public.payment p WHERE p.customer_id = c.customer_id) AS payments,
       (SELECT COUNT(*) FROM public.rental r WHERE r.customer_id = c.customer_id) AS rentals
FROM public.customer c
WHERE c.first_name = 'NURALI' AND c.last_name = 'BAKYTBEK UULU';

DELETE FROM public.payment
WHERE customer_id = (SELECT customer_id FROM public.customer
                     WHERE first_name = 'NURALI' AND last_name = 'BAKYTBEK UULU')
RETURNING payment_id, rental_id, amount;

DELETE FROM public.rental
WHERE customer_id = (SELECT customer_id FROM public.customer
                     WHERE first_name = 'NURALI' AND last_name = 'BAKYTBEK UULU')
RETURNING rental_id, inventory_id;

SELECT (SELECT COUNT(*) FROM public.payment p WHERE p.customer_id = c.customer_id) AS payments,
       (SELECT COUNT(*) FROM public.rental r WHERE r.customer_id = c.customer_id) AS rentals
FROM public.customer c
WHERE c.first_name = 'NURALI' AND c.last_name = 'BAKYTBEK UULU';

COMMIT;


/*
6. Rent and pay
dates are in the first half of 2017 because payment has partitions only for this period
uniqueness: rental has unique index (rental_date, inventory_id, customer_id) -> ON CONFLICT DO NOTHING,
payment is inserted only if this rental has no payment yet (NOT EXISTS)
relationships: inventory_id from inventory, customer_id from customer, staff_id from staff
of the same store, rental_id in payment from the new rental
*/
BEGIN;

INSERT into public.rental (rental_date, inventory_id, customer_id, return_date, staff_id, last_update)
SELECT TIMESTAMPTZ '2017-05-20 12:00:00+06',
       i.inventory_id,
       c.customer_id,
       TIMESTAMPTZ '2017-05-20 12:00:00+06' + f.rental_duration * INTERVAL '1 day',
       (SELECT MIN(st.staff_id) FROM public.staff st WHERE st.store_id = i.store_id),
       current_date
FROM public.film f
JOIN public.inventory i ON i.film_id = f.film_id
CROSS JOIN public.customer c
WHERE f.title IN ('YOUR NAME', 'SHERLOCK HOLMES', 'INTERSTELLAR')
  AND c.first_name = 'NURALI' AND c.last_name = 'BAKYTBEK UULU'
ON CONFLICT (rental_date, inventory_id, customer_id) DO NOTHING
RETURNING rental_id, rental_date, inventory_id, return_date, staff_id;

INSERT INTO public.payment (customer_id, staff_id, rental_id, amount, payment_date)
SELECT r.customer_id, r.staff_id, r.rental_id, f.rental_rate, r.rental_date
FROM public.rental r
JOIN public.inventory i ON i.inventory_id = r.inventory_id
JOIN public.film f ON f.film_id = i.film_id
JOIN public.customer c ON c.customer_id = r.customer_id
WHERE c.first_name = 'NURALI' AND c.last_name = 'BAKYTBEK UULU'
  AND f.title IN ('YOUR NAME', 'SHERLOCK HOLMES', 'INTERSTELLAR')
  AND NOT EXISTS (SELECT 1 FROM public.payment p WHERE p.rental_id = r.rental_id)
RETURNING payment_id, rental_id, amount, payment_date;

SELECT f.title, r.rental_date, r.return_date, p.amount, p.payment_date
FROM public.rental r
JOIN public.inventory i ON i.inventory_id = r.inventory_id
JOIN public.film f ON f.film_id = i.film_id
JOIN public.payment p ON p.rental_id = r.rental_id
JOIN public.customer c ON c.customer_id = r.customer_id
WHERE c.first_name = 'NURALI' AND c.last_name = 'BAKYTBEK UULU';

COMMIT;