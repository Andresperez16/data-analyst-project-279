WITH pv_pagadas AS (
    -- 1. Identificamos el tráfico pagado y aplicamos Last Paid Click
    SELECT 
        visitor_id,
        visit_date,
        source,
        medium,
        campaign,
        ROW_NUMBER() OVER (
            PARTITION BY visitor_id 
            ORDER BY visit_date DESC
        ) AS rn
    FROM public.sessions
    WHERE medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
),
atribucion_leads AS (
    -- 2. Cruzamos las últimas visitas con la tabla de leads
    SELECT 
        v.visitor_id,
        DATE(v.visit_date) AS visit_date,
        v.source AS utm_source,
        v.medium AS utm_medium,
        v.campaign AS utm_campaign,
        l.lead_id,
        l.amount,
        CASE WHEN l.status_id = 142 THEN 1 ELSE 0 END AS is_purchase
    FROM pv_pagadas v
    LEFT JOIN public.leads l 
        ON v.visitor_id = l.visitor_id 
        AND l.created_at >= v.visit_date
    WHERE v.rn = 1
),
costos_publicitarios AS (
    -- 3. Unificamos usando la columna real 'daily_spent' agrupando por día y campaña
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
        SUM(CASE WHEN is_purchase = 1 THEN amount ELSE 0 END) AS revenue
    FROM atribucion_leads
    GROUP BY visit_date, utm_source, utm_medium, utm_campaign
)
-- 5. Consulta final: Unimos las métricas de conversión con los costos publicitarios
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
-- 6. Criterios estrictos de ordenamiento requeridos para las 15 primeras filas
ORDER BY 
    r.visit_date ASC,
    r.visitors_count DESC,
    r.utm_source ASC,
    r.utm_medium ASC,
    r.utm_campaign ASC,
    r.revenue DESC NULLS last;
