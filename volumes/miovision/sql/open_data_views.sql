﻿-- View: open_data.miovision_2017

DROP VIEW open_data.miovision_2017;

CREATE OR REPLACE VIEW open_data.miovision_2017 AS 
 SELECT period_type as aggregation_period,
    int_id,
    intersec5 AS intersection_name,
    px,
    volumes_15min.datetime_bin,
    CASE WHEN classification ='Buses' THEN 'Buses and streetcars'
    ELSE classification END AS classification,
    volumes_15min.leg,
    volumes_15min.dir,
    SUM(volumes_15min.volume)::INT
    
   FROM miovision.volumes_15min
   INNER JOIN miovision.intersections USING (intersection_uid)
   INNER JOIN gis.centreline_intersection USING (int_id)
   INNER JOIN gis.traffic_signals on node_id = int_id
   INNER JOIN miovision.classifications USING(classification_uid)
   INNER JOIN miovision.report_dates USING (intersection_uid, class_type) 
  WHERE dt = datetime_bin::DATE AND date_part('year'::text, volumes_15min.datetime_bin) = 2017::double precision
GROUP BY int_id, intersec5, px, datetime_bin, classification, leg, dir, period_type;
ALTER TABLE open_data.miovision_2017
  OWNER TO rdumas;
GRANT ALL ON TABLE open_data.miovision_2017 TO rdumas;
GRANT SELECT ON TABLE open_data.miovision_2017 TO od_extract_svc;

DROP VIEW open_data.miovision_2018;

CREATE OR REPLACE VIEW open_data.miovision_2018 AS 
 SELECT period_type as aggregation_period,
    int_id,
    intersec5 AS intersection_name,
    px,
    volumes_15min.datetime_bin,
    CASE WHEN classification ='Buses' THEN 'Buses and streetcars'
    ELSE classification END AS classification,
    volumes_15min.leg,
    volumes_15min.dir,
    SUM(volumes_15min.volume)::INT
   FROM miovision.volumes_15min
   INNER JOIN miovision.intersections USING (intersection_uid)
   INNER JOIN gis.centreline_intersection USING (int_id)
   INNER JOIN gis.traffic_signals on node_id = int_id
   INNER JOIN miovision.classifications USING(classification_uid)
   INNER JOIN miovision.report_dates USING (intersection_uid, class_type) 
  WHERE dt = datetime_bin::DATE AND date_part('year'::text, volumes_15min.datetime_bin) = 2018::double precision
GROUP BY int_id, intersec5, px, datetime_bin, classification, leg, dir, period_type;
ALTER TABLE open_data.miovision_2018
  OWNER TO rdumas;
GRANT ALL ON TABLE open_data.miovision_2018 TO rdumas;
GRANT SELECT ON TABLE open_data.miovision_2018 TO od_extract_svc;


-- View: open_data.ksp_miovision_summary

DROP VIEW open_data.ksp_miovision_summary;

CREATE OR REPLACE VIEW open_data.ksp_miovision_summary AS 
WITH valid_bins AS (
         SELECT a_1.intersection_uid,
            a_1.class_type,
            a_1.dt + b_1.b::time without time zone AS datetime_bin,
            a_1.period_type
           FROM miovision.report_dates a_1
             CROSS JOIN (SELECT generate_series('2017-01-01 00:00:00'::timestamp without time zone, '2017-01-01 23:45:00'::timestamp without time zone, '00:15:00'::interval)::TIME) b_1(b)
          ORDER BY a_1.intersection_uid, a_1.class_type, (a_1.dt + b_1.b::time without time zone)
        ), int_avg AS (
         SELECT volumes_15min_by_class.intersection_uid,
            volumes_15min_by_class.class_type,
            volumes_15min_by_class.dir,
            volumes_15min_by_class.leg,
            volumes_15min_by_class.period_type,
            volumes_15min_by_class.datetime_bin::time without time zone AS time_bin,
            avg(volumes_15min_by_class.total_volume) AS avg_volume
           FROM miovision.volumes_15min_by_class
          GROUP BY volumes_15min_by_class.intersection_uid, volumes_15min_by_class.class_type, volumes_15min_by_class.period_type, volumes_15min_by_class.dir, volumes_15min_by_class.leg, (volumes_15min_by_class.datetime_bin::time without time zone)
        )
 , volumes_15 AS (
 
 SELECT a.intersection_uid,
    a.period_type,
    a.datetime_bin,
    a.class_type,
    b.dir,
    b.leg,
    COALESCE(c.total_volume, b.avg_volume) AS volume
  FROM valid_bins a
     JOIN int_avg b USING (intersection_uid, class_type, period_type)
     LEFT JOIN miovision.volumes_15min_by_class c USING (datetime_bin, intersection_uid, class_type, dir, leg, period_type)
  WHERE b.time_bin = a.datetime_bin::time without time zone
  ORDER BY a.intersection_uid, a.period_type, a.datetime_bin, a.class_type, b.dir, b.leg
),
 intersection_days AS (
	SELECT intersection_uid, datetime_bin::date AS dt, COUNT(DISTINCT datetime_bin) AS num_daily_observations
	FROM volumes_15
	GROUP BY intersection_uid, dt
 )
, daily AS(
 SELECT a.intersection_uid,
    c.intersection_name,
    c.street_main,
    c.street_cross,
    a.class_type,
    a.dir,
    a.period_type,
    a.datetime_bin::date AS dt,
    b.period_name || 
    CASE WHEN period_id = 7 THEN '' --24 hour
    ELSE --Append period range 
	(((' ('::text || to_char(lower(b.period_range)::interval, 'HH24:MM'::text)) || '-'::text) || to_char(upper(b.period_range)::interval, 'HH24:MM'::text)) || ')'::text 
    END
    AS "period_name",
    sum(a.volume) AS total_volume
   FROM volumes_15 a
     CROSS JOIN miovision.periods b
     JOIN miovision.intersections c USING (intersection_uid)
     JOIN intersection_days d ON d.intersection_uid = a.intersection_uid AND a.datetime_bin::date = dt
  WHERE a.datetime_bin::time without time zone <@ b.period_range AND report_flag AND (a.dir = ANY (ARRAY['EB'::text, 'WB'::text])) 
	AND (period_id != 7 OR num_daily_observations > 23 * 4) --Make sure 24hour counts have data for most of the 24-hour period
	AND (c.street_cross = ANY (ARRAY['Bathurst'::text, 'Spadina'::text, 'Bay'::text, 'Jarvis'::text])) AND (c.street_cross = 'Bathurst'::text AND (a.leg = ANY (ARRAY['E'::text, 'S'::text, 'N'::text])) OR c.street_cross = 'Jarvis'::text AND (a.leg = ANY (ARRAY['W'::text, 'S'::text, 'N'::text])) OR (c.street_cross <> ALL (ARRAY['Bathurst'::text, 'Jarvis'::text])) AND (a.dir = 'EB'::text AND (a.leg = ANY (ARRAY['W'::text, 'N'::text, 'S'::text])) OR a.dir = 'WB'::text AND (a.leg = ANY (ARRAY['E'::text, 'N'::text, 'S'::text])))) AND NOT ((a.class_type = ANY (ARRAY['Vehicles'::text, 'Cyclists'::text])) AND (a.dir = 'EB'::text AND (c.street_main = ANY (ARRAY['Wellington'::text, 'Richmond'::text])) OR a.dir = 'WB'::text AND c.street_main = 'Adelaide'::text))
  GROUP BY a.intersection_uid, c.intersection_name, c.street_main, c.street_cross, a.period_type, a.class_type, a.dir, (a.datetime_bin::date), b.period_name, b.period_range, period_id
   
)
SELECT period_type as aggregation_period, intersections.int_id,
    centreline_intersection.intersec5 AS intersection_name, px,
    CASE
            WHEN class_type = 'Buses'::text THEN 'Buses and streetcars'::text
            ELSE class_type
        END AS classification,
        dir, period_name, round(AVG(total_volume), -1)::int as average_volume
FROM daily
JOIN miovision.intersections USING (intersection_uid)
JOIN gis.centreline_intersection USING (int_id)
INNER JOIN gis.traffic_signals on node_id = int_id
GROUP BY period_type, int_id, class_type, intersec5, px, dir, period_name;
GRANT SELECT ON TABLE open_data.ksp_miovision_summary TO od_extract_svc;
