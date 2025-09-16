/* Проект «Онлайн-игра»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты, а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Забродская Е.А.
 * Дата: 13.02.2025
*/

-- Часть 1. Исследовательский анализ данных

-- 1. Исследование доли платящих игроков
-- 1.1. Доля платящих пользователей по всем данным:
WITH players_number AS (
	SELECT 
		count(id) AS total_players_number,
		(SELECT
			count(id) 
		FROM fantasy.users
		WHERE payer = 1) AS payer_players_number
	FROM fantasy.users)
SELECT 
	total_players_number,
	payer_players_number,
	ROUND(payer_players_number/total_players_number::numeric,2) AS payer_players_share
FROM players_number;

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:

WITH total_players_race AS (
	SELECT
		race_id,
		COUNT(id) AS total_players_race_nmb
	FROM fantasy.users
	GROUP BY race_id),
payer_players_race AS (
	SELECT
		race_id,
		COUNT(id) AS payer_players_race_nmb
		FROM fantasy.users
		WHERE payer = 1
		GROUP BY race_id)
SELECT
	race,
	total_players_race_nmb,
	payer_players_race_nmb,
	ROUND(payer_players_race_nmb/total_players_race_nmb::NUMERIC,2) AS payer_players_race_share
	FROM total_players_race AS tpr
	LEFT JOIN payer_players_race AS ppr ON ppr.race_id = tpr.race_id
	LEFT JOIN fantasy.race AS r ON r.race_id = tpr.race_id
	ORDER BY payer_players_race_share DESC;
-- 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
SELECT
	'все покупки' AS purchase_all_non_zero,
	COUNT(amount) AS purchase_nmb,
	SUM(amount) AS total_amount,
	MIN(amount) AS min_amount,
	MAX(amount) AS max_amount,
	ROUND(AVG(amount)::numeric,2) AS avg_amount,
	ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY amount)::NUMERIC,2) AS mediana_amount,
	ROUND(STDDEV(amount)::NUMERIC,2) AS st_dev_amount
FROM fantasy.events
UNION
SELECT 
	'покупки с ненулевой суммой' AS purchase_all_non_zero,
	COUNT(amount) AS purchase_nmb,
	SUM(amount) AS total_amount,
	MIN(amount) AS min_amount,
	MAX(amount) AS max_amount,
	ROUND(AVG(amount)::numeric,2) AS avg_amount,
	ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY amount)::NUMERIC,2) AS mediana_amount,
	ROUND(STDDEV(amount)::NUMERIC,2) AS st_dev_amount
	FROM fantasy.events
	WHERE amount > 0;
-- 2.2: Аномальные нулевые покупки:
WITH purchases_count AS
	(SELECT 
		count(*) AS purchase_nmb,
		(SELECT 
			count(*) 
		FROM fantasy.events
		WHERE amount = 0) AS nul_purchase_nmb
	FROM fantasy.events
	)
SELECT
	nul_purchase_nmb,
	nul_purchase_nmb/purchase_nmb::NUMERIC AS nul_purchase_share
	FROM purchases_count;
--Расчет количества игроков-покупателей и платящих игроков-покупателей
-- с ненулевыми суммами покупок
WITH buyers_payers_nmb AS (
SELECT 
	COUNT(e.id) AS total_buyers_nmb,
	COUNT(e.id) filter(WHERE payer = 1) AS total_payers_nmb, 
	COUNT(e.id) FILTER(WHERE amount > 0) AS non_zero_buyers_nmb,
	COUNT(e.id) FILTER(WHERE payer = 1 AND amount > 0) AS non_zero_payers_nmb
FROM fantasy.events AS e
LEFT JOIN fantasy.users AS u using(id))
SELECT 
	total_buyers_nmb,
	total_payers_nmb, 
	non_zero_buyers_nmb,
	non_zero_payers_nmb,
	ROUND(non_zero_buyers_nmb/total_buyers_nmb::NUMERIC,4) AS non_zero_buyers_share,
	ROUND(non_zero_payers_nmb/total_payers_nmb::NUMERIC,4) AS non_zero_buyers_share
FROM buyers_payers_nmb;
-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
WITH player_data AS (
	SELECT
		id,	
		COUNT(transaction_id) AS purchase_nmb_per_user,
		SUM(amount) AS total_amount_per_user
	FROM fantasy.events
	WHERE amount > 0
	GROUP BY id)
SELECT
	CASE
		WHEN payer = 1
			THEN 'Платящие'
		ELSE 'Неплатящие'
	END AS player_category,
	COUNT(pd.id) AS players_nmb,
	ROUND(AVG(purchase_nmb_per_user),2) AS avg_purchase_nmb_per_user,
	ROUND(AVG(total_amount_per_user)::numeric,2) AS avg_total_amount_per_user
FROM player_data AS pd
LEFT JOIN fantasy.users AS u ON u.id = pd.id
GROUP BY payer;
-- 2.4: Популярные эпические предметы:

WITH item_purchases AS (
	SELECT 
		item_code,
		COUNT(transaction_id) AS purchase_nmb_per_item,
		SUM(COUNT(transaction_id)) OVER() AS total_purchase_nmb,
		COUNT(transaction_id)::numeric/SUM(COUNT(transaction_id)) OVER() AS item_purchase_share,
		COUNT(DISTINCT id) AS buyers_nmb_per_item,
		(SELECT
			COUNT(DISTINCT id) 
		FROM fantasy.events
		WHERE amount > 0) AS total_buyers_nmb
	FROM fantasy.items AS i
	LEFT JOIN fantasy.events AS e USING(item_code)
	WHERE amount > 0
	GROUP BY item_code
	)
SELECT 
	game_items,
	purchase_nmb_per_item,
	item_purchase_share,
	buyers_nmb_per_item/total_buyers_nmb::NUMERIC AS item_buyers_share
FROM item_purchases AS ip
LEFT JOIN fantasy.items AS i ON i.item_code = ip.item_code
ORDER BY purchase_nmb_per_item DESC;
--Эпические предметы, которые не покупали ни разу:
WITH item_purchases AS (
	SELECT 
		i.item_code,
		COUNT(transaction_id) AS purchase_nmb_per_item
	FROM fantasy.items AS i
	LEFT JOIN fantasy.events AS e USING(item_code)
	GROUP BY i.item_code
	)
SELECT 
	game_items,
	purchase_nmb_per_item,
	COUNT(ip.item_code) OVER() AS total_item_zero_purchases_nmb
FROM item_purchases AS ip
LEFT JOIN fantasy.items AS i ON i.item_code = ip.item_code
WHERE purchase_nmb_per_item = 0;
-- Часть 2. Решение ad hoc-задач
-- 1. Зависимость активности игроков от расы персонажа:
WITH players_per_race AS (
	SELECT
		race_id,
		COUNT(id) AS players_nmb_per_race
	FROM fantasy.users
	GROUP BY race_id),
buyers_payers_per_race AS (
	SELECT
		race_id,
		COUNT(DISTINCT e.id) AS buyers_per_race_nmb,
		COUNT(DISTINCT e.id) FILTER (WHERE payer = 1) AS payers_per_race_nmb,
		ROUND(AVG(amount)::NUMERIC,2) AS avg_amount_per_buyer,
		ROUND(AVG(amount) FILTER (WHERE payer = 1)::NUMERIC,2) AS avg_amount_per_payer
	FROM fantasy.events AS e
	LEFT JOIN fantasy.users AS u ON u.id = e.id
	WHERE amount > 0
	GROUP BY race_id),
	purchases_per_buyer_payer AS (
		SELECT 
			e.id,
			COUNT(transaction_id) AS purchases_nmb_per_buyer,
			COUNT(transaction_id) FILTER (WHERE payer = 1) AS purchases_nmb_per_payer,
			SUM(amount) AS total_amount_per_buyer,
			SUM(amount) FILTER (WHERE payer = 1) AS total_amount_per_payer
			FROM fantasy.events AS e
			LEFT JOIN fantasy.users AS u ON u.id = e.id
			WHERE amount > 0
			GROUP BY e.id),
	avg_per_buyer AS (
		SELECT 
			race_id,
			ROUND(AVG(purchases_nmb_per_buyer)::numeric,2) AS avg_purchases_per_buyer,
			ROUND(AVG(purchases_nmb_per_payer)::NUMERIC,2) AS avg_purchases_per_payer,
			ROUND(AVG(total_amount_per_buyer)::numeric,2) AS avg_total_amount_per_buyer,
			ROUND(AVG(total_amount_per_payer)::numeric,2) AS avg_total_amount_per_payer
		FROM purchases_per_buyer_payer AS ppb
		LEFT JOIN fantasy.users AS u ON u.id = ppb.id
		GROUP BY race_id)
SELECT 
	race,
	players_nmb_per_race,
	buyers_per_race_nmb,
	payers_per_race_nmb,
	ROUND(buyers_per_race_nmb/players_nmb_per_race::NUMERIC,2) AS buyers_share,
	ROUND(payers_per_race_nmb/buyers_per_race_nmb::NUMERIC,2) AS payers_share,
	avg_purchases_per_buyer,
	avg_purchases_per_payer,
	avg_amount_per_buyer,
	avg_amount_per_payer,
	avg_total_amount_per_buyer,
	avg_total_amount_per_payer
FROM players_per_race AS ppr
LEFT JOIN buyers_payers_per_race AS bpr ON bpr.race_id = ppr.race_id
LEFT JOIN avg_per_buyer AS apb ON apb.race_id = bpr.race_id
LEFT JOIN fantasy.race AS r ON r.race_id = apb.race_id
ORDER BY avg_purchases_per_buyer DESC;
-- 2. Частота покупок
WITH date_to_date AS (
	SELECT 
		id,
		transaction_id,
		date::DATE AS date,
		COUNT(transaction_id) OVER(PARTITION BY id) AS purchase_amount_per_buyer
	FROM fantasy.events
	WHERE amount > 0
	),
days_between AS (
	SELECT
		id,
		transaction_id,
		date - LAG(date) OVER(PARTITION BY id ORDER BY date) AS days_between
	FROM date_to_date
	WHERE purchase_amount_per_buyer > 25
	),
purchases_days_per_user AS (
	SELECT  
		id,
		COUNT(transaction_id) AS purchase_nmb,
		ROUND(AVG(days_between)::NUMERIC,2) AS avg_days_between
	FROM days_between
	GROUP BY id),
rang AS (
	SELECT
		id,
		purchase_nmb,
		avg_days_between,
		payer,
		NTILE(3) OVER(ORDER BY avg_days_between) AS rang
	FROM purchases_days_per_user AS pdpu
	LEFT JOIN fantasy.users AS u USING(id)
	)
SELECT 
	CASE
		WHEN rang = 1
			THEN 'высокая частота'
		WHEN rang = 2
			THEN 'умеренная частота'
		WHEN rang = 3
			THEN 'низкая частота'
	END AS purchase_freq,
	COUNT(id) AS buyers_nmb,
	SUM(payer) AS payers_nmb,
	ROUND(SUM(payer)/COUNT(id)::NUMERIC,2) AS payers_share,
	ROUND(AVG(purchase_nmb)::NUMERIC,2) AS avg_purchase_nmb_per_player,
	ROUND(AVG(avg_days_between)::NUMERIC,2) AS avg_days_between_per_player
FROM rang
GROUP BY rang 
ORDER BY rang;

