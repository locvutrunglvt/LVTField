"""
Extract the exact datum transformation parameters that pyproj uses
for EPSG:9209 -> EPSG:4326
"""
from pyproj import CRS, Transformer
from pyproj.transformer import TransformerGroup
import json

# Get CRS info
crs_9209 = CRS.from_epsg(9209)
print("CRS 9209 info:")
print(f"  Name: {crs_9209.name}")
print(f"  Datum: {crs_9209.datum.name}")
print(f"  Ellipsoid: {crs_9209.ellipsoid.name}")
print(f"  Semi-major: {crs_9209.ellipsoid.semi_major_metre}")
print(f"  Inverse flat: {crs_9209.ellipsoid.inverse_flattening}")

# Get transformation group
tg = TransformerGroup("EPSG:9209", "EPSG:4326")
print(f"\nNumber of transformations: {len(tg.transformers)}")
for i, t in enumerate(tg.transformers):
    print(f"\n  Transformer {i}: {t.description}")
    print(f"  Accuracy: {t.accuracy}")

# Try to get the Towgs84 parameters from CRS
crs_vn = CRS.from_epsg(4756)  # VN-2000 geographic
print(f"\nVN-2000 geographic (4756):")
print(f"  Datum: {crs_vn.datum.name}")
print(f"  to_wgs84: {crs_vn.datum.to_json()}")

# Also check the actual pipeline
transformer = Transformer.from_crs("EPSG:9209", "EPSG:4326", always_xy=True)
print(f"\nPipeline definition:")
print(f"  {transformer.definition}")

# Calculate the approximate datum shift in degrees
# From our test: Delta = +110.9m lat, -195.6m lon consistently
# This corresponds to a geographic shift of:
lat_shift_deg = 110.9 / 111320
lon_shift_deg = -195.6 / (111320 * 0.9487)  # cos(18.3deg)
print(f"\nEstimated datum shift:")
print(f"  dLat = {lat_shift_deg:.8f} deg = {lat_shift_deg * 3600:.4f} arcsec")
print(f"  dLon = {lon_shift_deg:.8f} deg = {lon_shift_deg * 3600:.4f} arcsec")

# Test: what if we apply a simple offset?
import math

def tm_to_wgs84_corrected(e, n, cm, k0=0.9999, fe=500000.0, d_lat=0, d_lon=0):
    a = 6378137.0
    f = 1/298.257223563
    e2 = 2*f - f*f
    ep2 = e2/(1-e2)
    
    x = e - fe
    y = n
    M = y / k0
    mu = M / (a * (1 - e2/4 - 3*e2*e2/64 - 5*e2*e2*e2/256))
    e1 = (1 - math.sqrt(1-e2)) / (1 + math.sqrt(1-e2))
    
    phi1 = (mu 
        + (3*e1/2 - 27*e1**3/32)*math.sin(2*mu) 
        + (21*e1*e1/16 - 55*e1**4/32)*math.sin(4*mu) 
        + (151*e1**3/96)*math.sin(6*mu))
    
    sp = math.sin(phi1); cp = math.cos(phi1); tp = math.tan(phi1)
    N1 = a/math.sqrt(1-e2*sp*sp)
    T1 = tp*tp; C1 = ep2*cp*cp
    R1 = a*(1-e2)/((1-e2*sp*sp)**1.5)
    D = x/(N1*k0)
    
    lat = phi1 - (N1*tp/R1)*(
        D*D/2 
        - (5+3*T1+10*C1-4*C1*C1-9*ep2)*D**4/24 
        + (61+90*T1+298*C1+45*T1*T1-252*ep2-3*C1*C1)*D**6/720)
    lon = (D 
        - (1+2*T1+C1)*D**3/6 
        + (5-2*C1+28*T1-3*C1*C1+8*ep2+24*T1*T1)*D**5/120)/cp
    
    return (math.degrees(lat) + d_lat, cm + math.degrees(lon) + d_lon)

# Calibrate with pyproj
transformer = Transformer.from_crs("EPSG:9209", "EPSG:4326", always_xy=True)

# Get exact shift from center point
e, n = 541741.84, 2016835.81
m_lat, m_lon = tm_to_wgs84_corrected(e, n, 105.5)
p_lon, p_lat = transformer.transform(e, n)
d_lat = p_lat - m_lat
d_lon = p_lon - m_lon
print(f"\nExact correction needed:")
print(f"  d_lat = {d_lat:.10f} degrees")  
print(f"  d_lon = {d_lon:.10f} degrees")

# Verify correction
print("\nVerification with correction applied:")
for label, ee, nn in [("First", 531524.9, 2025218.9), ("SW", 526346.69, 2005414.0), ("NE", 557137.0, 2028257.62)]:
    c_lat, c_lon = tm_to_wgs84_corrected(ee, nn, 105.5, d_lat=d_lat, d_lon=d_lon)
    r_lon, r_lat = transformer.transform(ee, nn)
    err_lat = (c_lat - r_lat) * 111320
    err_lon = (c_lon - r_lon) * 111320 * math.cos(math.radians(r_lat))
    total = math.sqrt(err_lat**2 + err_lon**2)
    print(f"  {label}: corrected=({c_lat:.8f}, {c_lon:.8f}), ref=({r_lat:.8f}, {r_lon:.8f}), err={total:.2f}m")
