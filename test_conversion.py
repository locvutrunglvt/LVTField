"""
Compare our TM conversion with pyproj authoritative result
to find the exact offset causing the misalignment.
"""
import math
import sys

# Try pyproj first
try:
    from pyproj import Transformer
    HAS_PYPROJ = True
except ImportError:
    HAS_PYPROJ = False
    print("pyproj not available, trying osgeo...")

try:
    from osgeo import osr
    HAS_GDAL = True
except ImportError:
    HAS_GDAL = False

# Our manual TM conversion (same as Dart code)
def tm_to_wgs84_manual(e, n, cm, k0=0.9999, fe=500000.0):
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
    
    return (math.degrees(lat), cm + math.degrees(lon))

# Test points from the GPKG
test_points = [
    ("First point", 531524.9012074317, 2025218.89931652),
    ("SW corner", 526346.6875, 2005414.0),
    ("NE corner", 557137.0, 2028257.625),
    ("Center", (526346.6875+557137)/2, (2005414+2028257.625)/2),
]

cm = 105.5
k0 = 0.9999
fe = 500000.0

print("=" * 80)
print("MANUAL TM CONVERSION vs PYPROJ REFERENCE")
print(f"CRS: VN-2000 / TM-3 105-30 (EPSG:9209)")
print(f"Params: CM={cm}, k0={k0}, FE={fe}")
print("=" * 80)

if HAS_PYPROJ:
    # EPSG:9209 -> EPSG:4326
    transformer = Transformer.from_crs("EPSG:9209", "EPSG:4326", always_xy=True)
    
    for label, e, n in test_points:
        # Our manual result
        m_lat, m_lon = tm_to_wgs84_manual(e, n, cm, k0, fe)
        
        # pyproj reference result
        p_lon, p_lat = transformer.transform(e, n)
        
        # Delta
        d_lat = (m_lat - p_lat) * 111320  # meters
        d_lon = (m_lon - p_lon) * 111320 * math.cos(math.radians(p_lat))  # meters
        
        print(f"\n{label}: E={e:.2f}, N={n:.2f}")
        print(f"  Manual:  lat={m_lat:.8f}, lon={m_lon:.8f}")
        print(f"  Pyproj:  lat={p_lat:.8f}, lon={p_lon:.8f}")
        print(f"  Delta:   {d_lat:.2f}m lat, {d_lon:.2f}m lon")
        print(f"  Total:   {math.sqrt(d_lat**2 + d_lon**2):.2f}m")

elif HAS_GDAL:
    src = osr.SpatialReference()
    src.ImportFromEPSG(9209)
    dst = osr.SpatialReference()
    dst.ImportFromEPSG(4326)
    transform = osr.CoordinateTransformation(src, dst)
    
    for label, e, n in test_points:
        m_lat, m_lon = tm_to_wgs84_manual(e, n, cm, k0, fe)
        p_lat, p_lon, _ = transform.TransformPoint(e, n)
        d_lat = (m_lat - p_lat) * 111320
        d_lon = (m_lon - p_lon) * 111320 * math.cos(math.radians(p_lat))
        
        print(f"\n{label}: E={e:.2f}, N={n:.2f}")
        print(f"  Manual:  lat={m_lat:.8f}, lon={m_lon:.8f}")
        print(f"  GDAL:    lat={p_lat:.8f}, lon={p_lon:.8f}")
        print(f"  Delta:   {d_lat:.2f}m lat, {d_lon:.2f}m lon")
        print(f"  Total:   {math.sqrt(d_lat**2 + d_lon**2):.2f}m")
else:
    print("\nNeither pyproj nor GDAL available.")
    print("Manual results only:")
    for label, e, n in test_points:
        m_lat, m_lon = tm_to_wgs84_manual(e, n, cm, k0, fe)
        print(f"  {label}: lat={m_lat:.8f}, lon={m_lon:.8f}")
    
    print("\nInstalling pyproj...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyproj"])
    print("Installed. Re-run this script.")
