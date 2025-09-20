/* Анализ данных для агентства недвижимости
 * 
 * Автор: Забродская Е.А.
 * Дата: 10.03.2025
*/

-- Фильтрация данных от аномальных значений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдем id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    )
-- Выведем объявления без выбросов:
SELECT *
FROM real_estate.flats
WHERE id IN (SELECT * FROM filtered_id);


-- 1. Время активности объявлений
-- Результат запроса отвечает на такие вопросы:
-- 1. Какие сегменты рынка недвижимости Санкт-Петербурга и городов Ленинградской области 
--    имеют наиболее короткие или длинные сроки активности объявлений?
-- 2. Какие характеристики недвижимости, включая площадь недвижимости, среднюю стоимость квадратного метра, 
--    количество комнат и балконов и другие параметры, влияют на время активности объявлений? 
--    Как эти зависимости варьируют между регионами?
-- 3. Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?

WITH perc_99_1 AS (
	SELECT 
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY total_area) AS perc99_total_area,
		PERCENTILE_CONT(0.01) WITHIN GROUP(ORDER BY total_area) AS perc1_total_area,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY balcony) AS perc99_balcony,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY ceiling_height) AS perc99_ceiling_height,
		PERCENTILE_CONT(0.01) WITHIN GROUP(ORDER BY ceiling_height) AS perc1_ceiling_height,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY rooms) AS perc99_rooms,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY kitchen_area) AS perc99_kitchen_area,
		PERCENTILE_CONT(0.01) WITHIN GROUP(ORDER BY kitchen_area) AS perc1_kitchen_area,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY living_area) AS perc99_living_area,
		PERCENTILE_CONT(0.01) WITHIN GROUP(ORDER BY living_area) AS perc1_living_area
	FROM real_estate.flats
),
filtered_id AS (
	SELECT id
	FROM real_estate.flats
	WHERE total_area < (SELECT perc99_total_area FROM perc_99_1)
		AND total_area > (SELECT perc1_total_area FROM perc_99_1)
		AND (balcony < (SELECT perc99_balcony FROM perc_99_1) OR balcony IS NULL)
		AND ((ceiling_height < (SELECT perc99_ceiling_height FROM perc_99_1)
			AND ceiling_height > (SELECT perc1_ceiling_height FROM perc_99_1))
			OR ceiling_height IS NULL)
		AND (rooms < (SELECT perc99_rooms FROM perc_99_1) OR rooms IS NULL)
		AND (kitchen_area < (SELECT perc99_kitchen_area FROM perc_99_1)
			AND kitchen_area > (SELECT perc1_kitchen_area FROM perc_99_1)
			OR kitchen_area IS NULL)
		AND (living_area < (SELECT perc99_living_area FROM perc_99_1)
			AND living_area > (SELECT perc1_living_area FROM perc_99_1)
			OR living_area IS NULL)
		AND rooms > 0
	),
activity_group_div AS (
	SELECT 
		id,
		days_exposition,
		CASE
			WHEN days_exposition <= 30
				THEN 'До 30 дней'
			WHEN days_exposition <= 90
				THEN 'До 90 дней'
			WHEN days_exposition <= 180
				THEN 'До 180 дней'
			WHEN days_exposition > 180
				THEN 'Более 180 дней'
		END AS activity_group,
		last_price/total_area AS price_m2,
		total_area,
		rooms,
		balcony,
		ceiling_height,
		living_area,
		kitchen_area,
		floor,
		CASE
			WHEN city = 'Санкт-Петербург'
				THEN 'Санкт-Петербург'
			ELSE 'Ленинградская область'
		END AS region
	FROM real_estate.flats AS f
	LEFT JOIN real_estate.advertisement AS a using(id)
	LEFT JOIN real_estate.city AS c USING(city_id)
	LEFT JOIN real_estate.TYPE AS t using(type_id)
	WHERE id IN (SELECT * FROM filtered_id) AND days_exposition IS NOT NULL AND type = 'город'
	)
SELECT 
	region,
	activity_group,
	COUNT(id) AS adv_per_group_nmb,
	ROUND(COUNT(id)::NUMERIC/SUM(COUNT(id)) OVER(PARTITION BY region),2) AS adv_per_group_share,
	ROUND(AVG(price_m2)::NUMERIC,2) AS avg_price_m2,
	ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_m2)::NUMERIC,2) AS mediana_price_m2,
	ROUND(AVG(total_area)::NUMERIC,2) AS avg_total_area,
	ROUND(AVG(ceiling_height)::NUMERIC,2) AS avg_ceiling_height,
	ROUND(AVG(living_area)::NUMERIC,2) AS avg_living_area,
	ROUND(AVG(kitchen_area)::NUMERIC,2) AS avg_kitchen_area,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rooms) AS mediana_rooms,
	ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY balcony)::NUMERIC,2) AS mediana_balcony,
	ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY floor)::NUMERIC,2) AS mediana_floor,
	ROUND(COUNT(id) FILTER(WHERE rooms = 1)::NUMERIC/count(id),2) AS one_room_share,
	ROUND(COUNT(id) FILTER(WHERE rooms = 2)::NUMERIC/count(id),2) AS two_rooms_share,
	ROUND(COUNT(id) FILTER(WHERE rooms = 3)::NUMERIC/count(id),2) AS three_rooms_share,
	ROUND(COUNT(id) FILTER(WHERE rooms > 3)::NUMERIC/count(id),2) AS more_three_rooms_share
FROM activity_group_div
GROUP BY region, activity_group
ORDER BY region DESC, AVG(days_exposition);


-- 2. Сезонность объявлений
-- Результат запроса отвечает на такие вопросы:
-- 1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? Это показывает динамику активности покупателей.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)?
-- 3. Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
--    Что можно сказать о зависимости этих параметров от месяца?
WITH perc_99_1 AS (
	SELECT 
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY total_area) AS perc99_total_area,
		PERCENTILE_CONT(0.01) WITHIN GROUP(ORDER BY total_area) AS perc1_total_area,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY balcony) AS perc99_balcony,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY ceiling_height) AS perc99_ceiling_height,
		PERCENTILE_CONT(0.01) WITHIN GROUP(ORDER BY ceiling_height) AS perc1_ceiling_height,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY rooms) AS perc99_rooms,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY kitchen_area) AS perc99_kitchen_area,
		PERCENTILE_CONT(0.01) WITHIN GROUP(ORDER BY kitchen_area) AS perc1_kitchen_area,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY living_area) AS perc99_living_area,
		PERCENTILE_CONT(0.01) WITHIN GROUP(ORDER BY living_area) AS perc1_living_area
	FROM real_estate.flats
),
filtered_id AS (
	SELECT id
	FROM real_estate.flats
	WHERE total_area < (SELECT perc99_total_area FROM perc_99_1)
		AND total_area > (SELECT perc1_total_area FROM perc_99_1)
		AND (balcony < (SELECT perc99_balcony FROM perc_99_1) OR balcony IS NULL)
		AND ((ceiling_height < (SELECT perc99_ceiling_height FROM perc_99_1)
			AND ceiling_height > (SELECT perc1_ceiling_height FROM perc_99_1))
			OR ceiling_height IS NULL)
		AND (rooms < (SELECT perc99_rooms FROM perc_99_1) OR rooms IS NULL)
		AND (kitchen_area < (SELECT perc99_kitchen_area FROM perc_99_1)
			AND kitchen_area > (SELECT perc1_kitchen_area FROM perc_99_1)
			OR kitchen_area IS NULL)
		AND (living_area < (SELECT perc99_living_area FROM perc_99_1)
			AND living_area > (SELECT perc1_living_area FROM perc_99_1)
			OR living_area IS NULL)
		AND rooms > 0
	),
date_publ AS (
	SELECT
		COUNT(id) AS month_publ_flats_nmb,
		ROUND(AVG(last_price/total_area)::NUMERIC,2) AS avg_price_m2_publ,
		ROUND(AVG(total_area)::NUMERIC,2) AS avg_total_area_publ,
		EXTRACT(MONTH FROM first_day_exposition) AS publ_month
	FROM real_estate.advertisement
	LEFT JOIN real_estate.flats USING(id)
	LEFT JOIN real_estate.TYPE USING(type_id)
	WHERE id IN (SELECT * FROM filtered_id) AND first_day_exposition < '2019-01-01'
		AND first_day_exposition >= '2015-01-01' AND type = 'город'
	GROUP BY EXTRACT(MONTH FROM first_day_exposition)
),
date_sell AS (
	SELECT
		COUNT(id) AS month_sell_flats_nmb,
		ROUND(AVG(last_price/total_area)::NUMERIC,2) AS avg_price_m2_sell,
		ROUND(AVG(total_area)::NUMERIC,2) AS avg_total_area_sell,
		EXTRACT(MONTH FROM first_day_exposition + days_exposition::int) AS sell_month
		FROM real_estate.advertisement
		LEFT JOIN real_estate.flats USING(id)
		LEFT JOIN real_estate.TYPE USING(type_id)
	WHERE id IN (SELECT * FROM filtered_id) AND first_day_exposition + days_exposition::int < '2019-01-01'
		AND first_day_exposition + days_exposition::int >= '2015-01-01' AND days_exposition IS NOT NULL
		AND type = 'город'
	GROUP BY EXTRACT(MONTH FROM first_day_exposition + days_exposition::int)
),
publication_rank AS (
	SELECT 
		month_publ_flats_nmb,
		SUM(month_publ_flats_nmb) over() AS total_publ_flats_nmb,
		avg_price_m2_publ,
		avg_total_area_publ,
		publ_month,
		DENSE_RANK() OVER(ORDER BY month_publ_flats_nmb DESC) AS publ_rank
		FROM date_publ
),
sell_rank AS (
	SELECT
		month_sell_flats_nmb,
		SUM(month_sell_flats_nmb) over() AS total_sell_flats_nmb,
		avg_price_m2_sell,
		avg_total_area_sell,
		sell_month,
		DENSE_RANK() OVER(ORDER BY month_sell_flats_nmb DESC) AS sell_rank
		FROM date_sell
)
SELECT
	publ_rank,
	TO_CHAR(TO_DATE (publ_month::text, 'MM'), 'Month') AS month,
	month_publ_flats_nmb,
	ROUND(month_publ_flats_nmb/total_publ_flats_nmb::NUMERIC,2) AS month_publ_flats_share,
	avg_price_m2_publ,
	avg_total_area_publ,
	sell_rank,
	month_sell_flats_nmb,
	ROUND(month_sell_flats_nmb/total_sell_flats_nmb::NUMERIC,2) AS month_sell_flats_share,
	avg_price_m2_sell,
	avg_total_area_sell
FROM publication_rank AS pr
LEFT JOIN sell_rank AS sr ON pr.publ_month = sr.sell_month
ORDER BY publ_rank;
-- 3. Анализ рынка недвижимости Ленобласти
-- Результат запроса отвечает на такие вопросы:
-- 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
-- 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
--    Это может указывать на высокую долю продажи недвижимости.
-- 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир в различных населённых пунктах? 
--    Есть ли вариация значений по этим метрикам?
-- 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
--    То есть где недвижимость продаётся быстрее, а где — медленнее.

WITH perc_99_1 AS (
	SELECT 
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY total_area) AS perc99_total_area,
		PERCENTILE_CONT(0.01) WITHIN GROUP(ORDER BY total_area) AS perc1_total_area,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY balcony) AS perc99_balcony,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY ceiling_height) AS perc99_ceiling_height,
		PERCENTILE_CONT(0.01) WITHIN GROUP(ORDER BY ceiling_height) AS perc1_ceiling_height,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY rooms) AS perc99_rooms,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY kitchen_area) AS perc99_kitchen_area,
		PERCENTILE_CONT(0.01) WITHIN GROUP(ORDER BY kitchen_area) AS perc1_kitchen_area,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY living_area) AS perc99_living_area,
		PERCENTILE_CONT(0.01) WITHIN GROUP(ORDER BY living_area) AS perc1_living_area
	FROM real_estate.flats
),
filtered_id AS (
	SELECT id
	FROM real_estate.flats
	WHERE total_area < (SELECT perc99_total_area FROM perc_99_1)
		AND total_area > (SELECT perc1_total_area FROM perc_99_1)
		AND (balcony < (SELECT perc99_balcony FROM perc_99_1) OR balcony IS NULL)
		AND ((ceiling_height < (SELECT perc99_ceiling_height FROM perc_99_1)
			AND ceiling_height > (SELECT perc1_ceiling_height FROM perc_99_1))
			OR ceiling_height IS NULL)
		AND (rooms < (SELECT perc99_rooms FROM perc_99_1) OR rooms IS NULL)
		AND (kitchen_area < (SELECT perc99_kitchen_area FROM perc_99_1)
			AND kitchen_area > (SELECT perc1_kitchen_area FROM perc_99_1)
			OR kitchen_area IS NULL)
		AND (living_area < (SELECT perc99_living_area FROM perc_99_1)
			AND living_area > (SELECT perc1_living_area FROM perc_99_1)
			OR living_area IS NULL)
		AND rooms > 0
	),
lenobl_data AS (
	SELECT
		id,
		city,
		total_area,
		last_price/total_area AS price_m2,
		days_exposition
	FROM real_estate.advertisement AS a
	LEFT JOIN real_estate.flats AS f USING(id)
	LEFT JOIN real_estate.city AS c USING(city_id)
	WHERE id IN (SELECT * FROM filtered_id) AND city != 'Санкт-Петербург'
),
city_data AS (
	SELECT
		city,
		COUNT(id) AS adv_nmb,
		ROUND(COUNT(id) FILTER (WHERE days_exposition IS NOT NULL)/COUNT(id)::NUMERIC,2) AS sell_flats_share,
		ROUND(AVG(total_area)::NUMERIC,2) AS avg_total_area,
		ROUND(AVG(price_m2)::NUMERIC,2) AS avg_price_m2,
		ROUND(AVG(days_exposition)::NUMERIC,2) AS avg_days_exposition
	FROM lenobl_data
	GROUP BY city
)
--Подсчет персентелей для определения количества населенных пунктов в топе
/*SELECT
 	ROUND(AVG(adv_nmb)) AS avg_adv_nmb,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY adv_nmb) AS mediana_adv_nmb,
	PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY adv_nmb) AS perc75_adv_nmb,
	count(city) FILTER (WHERE adv_nmb <=3) AS city_nmb_less3,
	count(city) FILTER (WHERE adv_nmb <=11) AS city_nmb_less11,
	count(city) FILTER (WHERE adv_nmb <=50) AS city_nmb_less50,
	count(city) FILTER (WHERE adv_nmb >=50) AS city_nmb_more50,
	count(city) AS city_nmb
FROM city_data*/
SELECT 
	city,
	adv_nmb,
	sell_flats_share,
	avg_total_area,
	avg_price_m2,
	avg_days_exposition
FROM city_data
WHERE adv_nmb > 50
ORDER BY sell_flats_share desc;
--Вариант с ранжированием с помощью NTILE
WITH perc_99_1 AS (
	SELECT 
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY total_area) AS perc99_total_area,
		PERCENTILE_CONT(0.01) WITHIN GROUP(ORDER BY total_area) AS perc1_total_area,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY balcony) AS perc99_balcony,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY ceiling_height) AS perc99_ceiling_height,
		PERCENTILE_CONT(0.01) WITHIN GROUP(ORDER BY ceiling_height) AS perc1_ceiling_height,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY rooms) AS perc99_rooms,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY kitchen_area) AS perc99_kitchen_area,
		PERCENTILE_CONT(0.01) WITHIN GROUP(ORDER BY kitchen_area) AS perc1_kitchen_area,
		PERCENTILE_CONT(0.99) WITHIN GROUP(ORDER BY living_area) AS perc99_living_area,
		PERCENTILE_CONT(0.01) WITHIN GROUP(ORDER BY living_area) AS perc1_living_area
	FROM real_estate.flats
),
filtered_id AS (
	SELECT id
	FROM real_estate.flats
	WHERE total_area < (SELECT perc99_total_area FROM perc_99_1)
		AND total_area > (SELECT perc1_total_area FROM perc_99_1)
		AND (balcony < (SELECT perc99_balcony FROM perc_99_1) OR balcony IS NULL)
		AND ((ceiling_height < (SELECT perc99_ceiling_height FROM perc_99_1)
			AND ceiling_height > (SELECT perc1_ceiling_height FROM perc_99_1))
			OR ceiling_height IS NULL)
		AND (rooms < (SELECT perc99_rooms FROM perc_99_1) OR rooms IS NULL)
		AND (kitchen_area < (SELECT perc99_kitchen_area FROM perc_99_1)
			AND kitchen_area > (SELECT perc1_kitchen_area FROM perc_99_1)
			OR kitchen_area IS NULL)
		AND (living_area < (SELECT perc99_living_area FROM perc_99_1)
			AND living_area > (SELECT perc1_living_area FROM perc_99_1)
			OR living_area IS NULL)
		AND rooms > 0
	),
lenobl_data AS (
	SELECT
		id,
		city,
		total_area,
		last_price/total_area AS price_m2,
		days_exposition
	FROM real_estate.advertisement AS a
	LEFT JOIN real_estate.flats AS f USING(id)
	LEFT JOIN real_estate.city AS c USING(city_id)
	WHERE id IN (SELECT * FROM filtered_id) AND city != 'Санкт-Петербург'
),
city_data AS (
	SELECT
		city,
		COUNT(id) AS adv_nmb,
		ROUND(COUNT(id) FILTER (WHERE days_exposition IS NOT NULL)/COUNT(id)::NUMERIC,2) AS sell_flats_share,
		ROUND(AVG(total_area)::NUMERIC,2) AS avg_total_area,
		ROUND(AVG(price_m2)::NUMERIC,2) AS avg_price_m2,
		ROUND(AVG(days_exposition)::NUMERIC,2) AS avg_days_exposition,
		NTILE(10) OVER(ORDER BY count(id) DESC) AS group_nmb
	FROM lenobl_data
	GROUP BY city
)
SELECT 
	city,
	adv_nmb,
	sell_flats_share,
	avg_total_area,
	avg_price_m2,
	avg_days_exposition
FROM city_data
WHERE group_nmb = 1
ORDER BY sell_flats_share desc;
