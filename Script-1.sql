/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Даниель Гусак
 * Дата: 24.05.2026
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным
 
SELECT 
	-- Общее количество зарегестрированных игроков
	COUNT(*) AS total_players,
    -- Количество платящих игроков.
    -- Поле payer хранится как бинарный признак (1 = платит, 0 = не платит),
    -- поэтому сумма значений эквивалентна числу пользователей с покупками
	SUM(u.payer) AS paying_playsers,	   
    -- Доля платящих игроков среди всех пользователей.
    -- Среднее значение бинарного признака (AVG) фактически отражает конверсию в платежи
    -- Округление до 3 знаков после запятой используется для более точного анализа распределения
	ROUND(AVG(u.payer), 3) AS paying_share	   
FROM fantasy.users u;

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
-- Использование CTE для подсчета общего количества и количества платящих игроков в разрезе расы
-- CTE: агрегация метрик пользователей по расам
WITH users AS (
    SELECT 
        -- Идентификатор и название расы
        r.race_id,
        r.race, 
        
        -- Количество платящих игроков (payer: 1/0 → сумма = число платящих)
        SUM(u.payer) AS race_paying_players,
        
        -- Общее число игроков в расе
        COUNT(*) AS race_total_players
        
    FROM fantasy.users u
    INNER JOIN fantasy.race r 
        ON u.race_id = r.race_id 

    GROUP BY r.race_id, r.race  
)
-- Доля платящих игроков по расам
SELECT 
    *,
    -- Доля платежей по расе
    ROUND((race_paying_players::numeric / race_total_players), 3) AS race_paying_share  
FROM users
ORDER BY race_paying_share DESC;

-- Задача 2. Исследование внутриигровых покупок

-- 2.1. Статистические показатели по полю amount:
SELECT 
    -- Общее количество транзакций (покупок)
    COUNT(*) AS total_purchases,     
    -- Общая выручка (сумма всех покупок)
    SUM(e.amount) AS total_sum,   
    -- Минимальная сумма покупки
    MIN(e.amount) AS min,    
    -- Максимальная сумма покупки
    MAX(e.amount) AS max, 
    -- Средний чек (с округлением до 2 знаков)
    ROUND(AVG(e.amount)::numeric, 2) AS avg,    
    -- Медианный чек (50-й перцентиль)
    ROUND(
        PERCENTILE_CONT(0.5) 
        WITHIN GROUP (ORDER BY e.amount)::numeric, 
        2
    ) AS median,
    -- Стандартное отклонение чеков (показывает разброс значений)
    ROUND(STDDEV(e.amount)::numeric, 2) AS stddev
FROM fantasy.events e;

-- 2.2: Аномальные нулевые покупки:
SELECT 
    -- Общее количество транзакций (все события покупок)
    COUNT(*) AS total_purchases,
    -- Количество покупок с нулевой суммой (free / zero transactions)
    COUNT(*) FILTER (WHERE amount = 0) AS zero_purchases,
    -- Доля нулевых покупок от общего числа транзакций
    -- ROUND до 3 знаков для удобства интерпретации
    ROUND(
        COUNT(*) FILTER (WHERE amount = 0)::numeric / COUNT(*), 
        3
    ) AS zero_purchases_share
FROM fantasy.events e;

-- 2.3: Популярные эпические предметы:
-- CTE: агрегируем продажи по каждому товару
WITH sales AS (
    SELECT
        -- Код предмета
        e.item_code,  
        -- Наименование предмета
        i.game_items, 
        -- Общее количество продаж товара
        COUNT(*) AS total_sales,     
        -- Количество уникальных пользователей, купивших товар
        COUNT(DISTINCT e.id) AS users_per_item
    FROM fantasy.events e  
    INNER JOIN fantasy.items i ON e.item_code = i.item_code 
    -- Учитываем только платные покупки
    WHERE amount > 0  
    -- Группировка по товарам
    GROUP BY e.item_code, i.game_items 
)
-- Финальный расчет долей и метрик по товарам
SELECT
    -- Код предмета
    item_code, 
    -- Наименование предмета
    game_items, 
    -- Общее количество продаж
    total_sales,  
    -- Доля продаж товара от всех продаж (window sum)
    total_sales::numeric / SUM(total_sales) OVER () AS sales_share,   
    -- Количество уникальных покупателей
    users_per_item,  
    -- Доля пользователей, купивших товар, от общего числа покупателей по всем товарам
    users_per_item::numeric / SUM(users_per_item) OVER() AS users_share
FROM sales
-- Сортировка по популярности товара (доле продаж)
ORDER BY sales_share DESC;


-- Часть 2. Решение ad hoc-задачи
-- Задача: Зависимость активности игроков от расы персонажа:
WITH total_players AS (
    -- Общее количество зарегистрированных игроков по расам
    SELECT
        r.race_id,
        r.race,
        COUNT(u.id) AS total_players
    FROM fantasy.users u
    JOIN fantasy.race r
        ON u.race_id = r.race_id
    GROUP BY r.race_id, r.race
),
paying_players AS (
    -- Количество платящих игроков по расам
    SELECT
        u.race_id,
        COUNT(DISTINCT u.id) AS paying_players
    FROM fantasy.users u
    JOIN fantasy.events e
        ON u.id = e.id
    WHERE e.amount > 0
    GROUP BY u.race_id
),
player_activity AS (
    -- Активность платящих игроков
    SELECT
        u.race_id,
        u.id AS player_id,
        -- Количество покупок игрока
        COUNT(e.transaction_id) AS purchases_per_player,
        -- Средняя стоимость покупки игрока
        AVG(e.amount) AS avg_purchase_amount,
        -- Суммарная стоимость покупок игрока
        SUM(e.amount) AS total_purchase_amount
    FROM fantasy.users u
    JOIN fantasy.events e
        ON u.id = e.id
    -- Исключаем нулевые покупки
    WHERE e.amount > 0

    GROUP BY u.race_id, u.id
)
SELECT
    tp.race,
    -- Общее количество игроков
    tp.total_players,
    -- Количество платящих игроков
    COALESCE(pp.paying_players, 0) AS paying_players,
    -- Доля платящих игроков от всех зарегистрированных
    ROUND(
        COALESCE(pp.paying_players, 0)::numeric
        / tp.total_players,
        3
    ) AS paying_share,
    -- Доля платящих игроков среди всех платящих игроков
    ROUND(
        COALESCE(pp.paying_players, 0)::numeric
        / SUM(COALESCE(pp.paying_players, 0)) OVER (),
        3
    ) AS paying_players_share,
    -- Среднее количество покупок на одного платящего игрока
    ROUND(
        AVG(pa.purchases_per_player)::numeric,
        2
    ) AS avg_purchases_per_player,
    -- Средняя стоимость одной покупки
    ROUND(
        AVG(pa.avg_purchase_amount)::numeric,
        2
    ) AS avg_purchase_amount,
    -- Средняя суммарная стоимость покупок на игрока
    ROUND(
        AVG(pa.total_purchase_amount)::numeric,
        2
    ) AS avg_total_purchase_amount
FROM total_players tp
LEFT JOIN paying_players pp
    ON tp.race_id = pp.race_id
LEFT JOIN player_activity pa
    ON tp.race_id = pa.race_id
GROUP BY
    tp.race,
    tp.total_players,
    pp.paying_players
ORDER BY paying_share DESC;
