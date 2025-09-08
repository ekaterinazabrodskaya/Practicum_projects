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

/*Анализ рынка недвижимости Санкт-Петербурга и Ленинградской области для агентства недвижимости.
Автор:  Забродская Е.А.
Дата: 08.03.2025

1. Время активности объявлений
1.1 Сегменты рынка недвижимости Санкт-Петербурга и городов Ленинградской области, имеющие наиболее короткие или длинные сроки активности объявлений?
В Санкт-Петербурге наиболее короткие сроки активности у объявлений с наименьшей средней стоимостью за квадратный метр (109760,57 руб/м2). У объявлений с наибольшей средней стоимостью за квадратный метр сроки активности также наибольшие.
 В Ленинградской области у объявлений с наиболее короткими сроками активности средняя стоимость квадратного метра наибольшая. У объявлений с самыми большими сроками активности стоимость меньше, чем у объявлений с самыми короткими сроками активности, но больше, чем у всех остальных категорий по активности объявлений. 
1.2. Характеристики недвижимости, влияющие на время активности объявлений.
В Санкт-Петербурге:
квартиры, имеющие наименьшие сроки активности объявлений (до 30 дней), характеризуются:
наименьшей средней стоимостью квадратного метра (109760,57 руб/м2),
наименьшей средней общей площадью (55,2м2) ,
наименьшей средней высотой потолков 2,76 м (хотя отличия от других категорий не очень значительны),
наименьшей средней жилой площадью (30,96м2) и средней площадью кухни (10,12 м2).
Количество комнат также влияет на срок публикации объявления:
Доля однокомнатных квартир (0,39) наибольшая для объявлений категории «до 30 дней» и наименьшая для объявлений категории «более 180 дней» (0,3).
Доля трехкомнатных квартир наибольшая для объявлений категории «более 180 дней» (0,3) и наименьшая для объявлений категории «до 30 дней» (0,22).
Медианные значения количества комнат (2), количества балконов (1), этажа (5) одинаковы для всех сроков активности объявлений, что свидетельствует о том, что для всех категорий активности объявлений количество одно-, двухкомнатных квартир с одним балконом такое же как количество квартир со всеми остальными вариантами количества комнат и балконов. Медианные значения этажа (5) также одинаковы для всех сроков активности объявлений, что свидетельствует о том, количество квартир, расположенных на первых пяти этажах равно количеству квартир на этажах выше пятого. Возможно, в основном квартиры расположены в невысоких домах.
 Доля объявлений в категориях «до 30 дней» и «до 180 дней» примерно одинакова (0,19 и 0,2) и меньше, чем доля объявлений в других категориях.
В Ленинградской области:
Средняя стоимость квадратного метра у квартир из категории «до 30 дней» наибольшая (72717,88 руб/м2), как и медианная стоимость (71810,37 руб/м2).
Наименьшая стоимость квадратного метра у квартир из категории «до 90 дней» (67083,64 руб/м2) и далее она растет по мере увеличения сроков активности объявлений.
В отношении средней площади, средней высоты потолков, средней жилой площади, средней площади кухни в Ленинградской области такая же зависимость показателей, как в Санкт-Петербурге. Самые низкие значения у квартир из категории «до 30 дней», самые высокие у квартир из категории «больше 180 дней). Также преобладают одно-, двухкомнатные квартиры с одним балконом во всех категориях. Медианный этаж меньше, чем в Санкт-Петербурге (4 для категории «до 30 дней, и 3 для остальных категорий). Доля однокомнатных квартир больше в категории «до 30 дней», чем в остальных категориях. Для трехкомнатных квартир: хотя их доля (0,19) в категории «до 30 дней» меньше, чем в категории «более 180 дней» (0,27), но для категории «до 180 дней» доля трехкомнатных квартир такая же, как и их доля в категории «до 30 дней» (0,19).
Также как в Санкт-Петербурге доля объявлений в категориях «до 30 дней» и «до 180 дней» меньше, чем в категориях «до 90 дней» и «более 180 дней».

1.3. Различия между недвижимостью Санкт-Петербурга и Ленинградской области.
Средняя стоимость квадратного метра в Ленинградской области примерно на 34-40% меньше, чем в Санкт-Петербурге. Средняя общая площадь меньше в Ленинградской области на 9,5-15%. Медианные количества комнат и балконов одинаковы для Санкт-Петербурга и городов Ленинградской области. Квартиры в городах Ленинградской области расположены в среднем на более низких этажах, чем в Санкт-Петербурге.
Регион	Категория активности	Кол-во объявлений	Доля объявлений	Средняя стоимость,  руб/м2	Средняя общая площадь,  м2	Средняя высота потолка, м	Средняя жилая площадь, м2
Санкт-Петербург	До 30 дней	2057	0,19	109 760,57	55,2	2,76	30,96
Санкт-Петербург	До 90 дней	3106	0,29	110 969,59	57,16	2,77	31,92
Санкт-Петербург	До 180 дней	2156	0,2	111 006,06	60,6	2,89	34,09
Санкт-Петербург	Более 180 дней	3440	0,32	113 646,65	66,02	2,83	37,4
Лен. область	До 30 дней	372	0,14	72 717,88	49,49	2,69	27,78
Лен. область	До 90 дней	868	0,33	67 083,64	51,78	2,71	29,86
Лен. область	До 180 дней	515	0,2	69 588,65	52,43	2,70	30,19
Лен. область	Более 180 дней	852	0,33	68 328,49	56,12	2,72	32,26

Регион	Категория активности	Медианное кол-во комнат	Медианное кол-во балконов	Медианный этаж	Доля однокомнатных квартир	Доля трехкомнатных квартир
Санкт-Петербург	До 30 дней	2	1	5	0,39	0,22
Санкт-Петербург	До 90 дней	2	1	5	0,37	0,23
Санкт-Петербург	До 180 дней	2	1	5	0,33	0,27
Санкт-Петербург	Более 180 дней	2	1	5	0,3	0,3
Лен. область	До 30 дней	2	1	4	0,44	0,19
Лен. область	До 90 дней	2	1	3	0,36	0,22
Лен. область	До 180 дней	2	1	3	0,34	0,19
Лен. область	Более 180 дней	2	1	3	0,33	0,27

2. Сезонность объявлений
2.1. Динамика активности покупателей.
Месяцы наибольшей активности по публикации объявлений:
Ноябрь, октябрь (21% объявлений)
Месяцы наибольшей активности по снятию объявлений:
Октябрь, ноябрь (22% объявлений)
2.2. Совпадения периодов активной публикации объявлений и периодов, когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений).
Периоды активности по публикации и снятию объявлений совпадают.

2.3. Влияние сезонных колебания на среднюю стоимость квадратного метра и среднюю площадь квартир.
В опубликованных объявлениях:
максимальная средняя стоимость квадратного метра в сентябре, минимальная в апреле;
максимальная средняя площадь квартир в сентябре, минимальная в июне.
Различия между минимальной и максимальной средней общей площадью невелики.
В снятых с публикации объявлениях:
максимальная средняя стоимость квадратного метра в декабре, октябре; минимальная в мае, августе;
максимальная средняя общая площадь в июне, минимальная средняя общая площадь в апреле.
Различия между минимальной и максимальной средней общей площадью невелики.
3. Анализ рынка недвижимости Ленобласти
3.1. Населённые пунктах Ленинградской области, в которых наиболее активно публикуют объявления о продаже недвижимости?
Населенный пункт	Количество объявлений
Мурино	506
Кудрово	417
Шушары	382
Всеволожск	342
Парголово	293
Пушкин	257
Колпино	219
Гатчина	208
Выборг	176
Петергоф	149
Сестрорецк	141
Красное Село	129
Новое Девяткино	117
Сертолово	112
Бугры	93
Волхов	85
Кингисепп	81
Сланцы	78
Ломоносов	74
Кронштадт	68
Никольское	64
Коммунар	63
Янино-1	60
Старая	56
Тосно	55
Сосновый Бор	53
В половине населенных пунктов Ленинградской области количество объявлений меньше 3. В 75% - меньше 11. Поэтому для ответов на вопросы использовались данные населенных пунктов, количество объявлений в которых превышает 50. Их 26 из 288 населенных пунктов всего.
3.2. Самая высокая доля снятых с публикации объявлений (самая высокая доля продажи недвижимости) в следующих населенных пунктах:
Тосно, Мурино, Кудрово, Парголово, Шушары

3.3. Средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир.
Минимальная средняя стоимость одного квадратного метра в Сланцах (18151,67  руб/м2), максимальная в Пушкине (104828,75 руб/м2). Разница почти в 6 раз.
Минимальная средняя площадь в Никольском (45,88), максимальная в Сестрорецке (62,86 м2). Разница в 1,4 раза.

3.4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? То есть, где недвижимость продаётся быстрее, а где — медленнее.
Быстрее всего недвижимость продается в Сосновом Бору (средняя продолжительность публикации объявления (86,41), Янино-1 (118,18) и Кингисеппе (118,62). Дольше всего в Никольском (262.33), Ломоносове (243,69) и Коммунаре (240,65).

Общие выводы и рекомендации
В целом быстрее продается недвижимость с наиболее низкой стоимостью квадратного метра, меньшей общей площадью, меньшей высотой потолков, наименьшим количеством комнат. Половина продаваемых квартир одно- или двухкомнатные.
Средняя площадь квартир и средняя стоимость квадратного метра в Санкт-Петербурге выше, чем в городах Ленинградской области.
Периоды активности по публикации и снятию объявлений приходятся на октябрь, ноябрь.
Максимальная средняя стоимость квадратного метра приходится на осень,  начало зимы.

В 75% населенных пунктов Ленинградской области количество объявлений меньше 50. Разница максимальной и минимальной средней стоимости квадратного метра очень велика (почти 6 раз). Разница в скорости продажи недвижимости достигает 3 раз (между минимальной средней длительностью публикации объявлений и максимальной).

Рекомендации: выходить на рынок осенью с предложениями одно- или двухкомнатных квартир, находящихся в сегменте наиболее низкой стоимости, меньшей общей площади. В Ленинградской области имеет смысл ориентироваться на населенные пункты с наибольшим количеством объявлений и наибольшей долей проданных квартир.
/*
