WITH pv_pagadas AS (
    -- 1. Identificamos y filtramos solo los clics pagados usando los nombres reales de tus columnas
    SELECT 
        visitor_id,
        visit_date,
        source,
        medium,
        campaign,
        -- Numeramos las visitas de cada usuario de la más reciente a la más antigua
        ROW_NUMBER() OVER (
            PARTITION BY visitor_id 
            ORDER BY visit_date DESC
        ) AS rn
    FROM public.sessions
    WHERE medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
),
ultimas_visitas AS (
    -- 2. Filtramos para quedarnos únicamente con el último clic pagado de cada visitante
    SELECT 
        visitor_id,
        visit_date,
        source,
        medium,
        campaign
    FROM pv_pagadas
    WHERE rn = 1
)
-- 3. Unimos el último clic pagado con los leads y renombramos las columnas según los requisitos
SELECT 
    v.visitor_id,
    v.visit_date,
    v.source AS utm_source,       -- Renombrado a lo requerido por el proyecto
    v.medium AS utm_medium,       -- Renombrado a lo requerido por el proyecto
    v.campaign AS utm_campaign,   -- Renombrado a lo requerido por el proyecto
    l.lead_id,
    l.created_at,
    l.amount,
    l.closing_reason,
    l.status_id
FROM ultimas_visitas v
LEFT JOIN public.leads l 
    ON v.visitor_id = l.visitor_id 
    AND l.created_at >= v.visit_date
-- 4. Ordenamiento estricto requerido
ORDER BY 
    l.amount DESC NULLS LAST,
    v.visit_date ASC,
    v.source ASC,
    v.medium ASC,
    v.campaign ASC;