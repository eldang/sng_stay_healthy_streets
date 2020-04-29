DROP SCHEMA IF EXISTS sng CASCADE;
CREATE SCHEMA IF NOT EXISTS sng;

-- import streets data manually as sng.routes
-- suggested method: use QGIS to convert the kml to a sql file, with only the name and description fields, geometries coerced to 2d linestrings, and no CREATE SCHEMA.  Then open that as text and manually find-and-replace "public" to "sng" with both single and double quotes.
-- import as D1_street_segments, D2_street_segments, D3_street_segments, D456_street_segments, D7_street_segments




-- create combo view




-- make chunky street segments from the FIX data
DROP TABLE IF EXISTS sng.street_segments CASCADE;
CREATE TABLE sng.street_segments AS
SELECT
	gid,
	stname_ord AS street_name,
	ST_Transform(st_buffer(geom, GREATEST(surfacewid*2.5, 75), 'endcap=flat join=round'), 4326) AS geom,
	ST_Transform(geom, 4326) AS centreline
FROM sources.street_segments;
CREATE INDEX ON sng.street_segments USING gist (geom);
VACUUM ANALYZE sng.street_segments;


-- select street segments corresponding to each proposed route
DROP TABLE IF EXISTS sng.route_segments CASCADE;
CREATE TABLE sng.route_segments AS
SELECT
	r.ogc_fid AS route_id,
	r.name AS route_name,
	s.street_name, ST_Union(s.centreline) AS geom,
	count(s.gid) AS n_segments
FROM sng.street_segments s
RIGHT JOIN sng.routes r ON ST_Intersects(r.wkb_geometry, s.geom)
GROUP BY r.ogc_fid, r.name, s.street_name;
DELETE FROM sng.route_segments WHERE n_segments < 3;
CREATE INDEX ON sng.route_segments USING gist(geom);
VACUUM ANALYZE sng.route_segments;


-- now buffer the route segments
DROP TABLE IF EXISTS sng.route_buffers CASCADE;
CREATE TABLE sng.route_buffers as
SELECT
	route_id, route_name, street_name,
	ST_Buffer(geom, 0.00002, 'endcap=flat join=round') AS geom
FROM sng.route_segments;
CREATE INDEX ON sng.route_buffers USING gist(geom);
VACUUM ANALYZE sng.route_buffers;

-- and find the other street segments these intersect
DROP TABLE IF EXISTS sng.route_intersections CASCADE;
CREATE TABLE sng.route_intersections AS
SELECT
	r.route_id, r.route_name,
	s.street_name, s.centreline AS geom
FROM sng.street_segments s
RIGHT JOIN sng.route_buffers r ON ST_Intersects(r.geom, s.geom) AND r.street_name != s.street_name;


-- and bring it all together
DROP TABLE IF EXISTS sng.routes_tagged CASCADE;
CREATE TABLE sng.routes_tagged AS
SELECT
	ogc_fid, wkb_geometry, "name", "description",
	ST_Length(ST_Transform(wkb_geometry, 2926)) / 5280 AS route_length,
	COUNT(i.route_id) + 2 AS n_intersections
FROM sng.routes r
LEFT JOIN sng.route_intersections i ON i.route_id = r.ogc_fid
GROUP BY ogc_fid, wkb_geometry, "name", "description";


-- export from qgis
