WITH sesiones_pagadas AS (
    -- 1. Identificamos el tráfico pagado y aplicamos el modelo Last Paid Click
    SELECT 
        visitor_id,
        visit_date,
        source AS utm_source,
        medium AS utm_medium,
        campaign AS utm_campaign,
        ROW_NUMBER() OVER (
            PARTITION BY visitor_id 
            ORDER BY visit_date DESC
        ) AS rn
    FROM public.sessions
    WHERE medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
),
ultimas_sesiones AS (
    -- 2. Nos quedamos únicamente con el último clic pagado de cada visitante
    SELECT 
        visitor_id,
        visit_date,
        utm_source,
        utm_medium,
        utm_campaign
    FROM sesiones_pagadas
    WHERE rn = 1
),
atribucion_leads AS (
    -- 3. Cruzamos con la tabla de leads aplicando las dos condiciones de éxito del proyecto
    SELECT 
        v.visitor_id,
        DATE(v.visit_date) AS visit_date,
        v.utm_source,
        v.utm_medium,
        v.utm_campaign,
        l.lead_id,
        CASE 
            WHEN l.status_id = 142 OR l.closing_reason = 'Completado con éxito' THEN 1 
            ELSE 0 
        END AS is_purchase,
        CASE 
            WHEN l.status_id = 142 OR l.closing_reason = 'Completado con éxito' THEN COALESCE(l.amount, 0) 
            ELSE 0 
        END AS revenue
    FROM ultimas_sesiones v
    LEFT JOIN public.leads l 
        ON v.visitor_id = l.visitor_id 
        AND l.created_at >= v.visit_date
),
resumen_atribucion AS (
    -- 4. Agrupamos las visitas, leads y ganancias por día y campaña
    SELECT 
        visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        COUNT(DISTINCT visitor_id) AS visitors_count,
        COUNT(DISTINCT lead_id) AS leads_count,
        SUM(is_purchase) AS purchases_count,
        SUM(revenue) AS revenue
    FROM atribucion_leads
    GROUP BY visit_date, utm_source, utm_medium, utm_campaign
),
costos_publicitarios AS (
    -- 5. Unificamos y sumamos los gastos de vk y yandex
    SELECT 
        DATE(campaign_date) AS campaign_date,
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM (
        SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent FROM public.vk_ads
        UNION ALL
        SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent FROM public.ya_ads
    ) sub_costos
    GROUP BY DATE(campaign_date), utm_source, utm_medium, utm_campaign
)
-- 6. Consulta final con el ordenamiento ESTRICTO que pide tu guía
SELECT 
    r.visit_date,
    r.visitors_count,
    r.utm_source,
    r.utm_medium,
    r.utm_campaign,
    COALESCE(c.total_cost, 0) AS total_cost,
    r.leads_count,
    r.purchases_count,
    r.revenue
FROM resumen_atribucion r
LEFT JOIN costos_publicitarios c 
    ON r.visit_date = c.campaign_date 
    AND r.utm_source = c.utm_source 
    AND r.utm_medium = c.utm_medium 
    AND r.utm_campaign = c.utm_campaign
ORDER BY 
    r.visit_date ASC,
    r.visitors_count DESC,
    r.utm_source ASC,
    r.utm_medium ASC,
    r.utm_campaign ASC,
    r.revenue DESC NULLS LAST;