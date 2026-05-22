import sqlite3, math

db = sqlite3.connect(r'G:\My Drive\GIS\FSC\Ha Tinh\2026\FSC_Viet Trang_14May2026_V5.gpkg')

# Read first geometry binary to check
row = db.execute('SELECT geom FROM [Viet Trang 2026] LIMIT 1').fetchone()
geom = row[0]
print(f"Geom bytes: {len(geom)}, header: {geom[:20].hex()}")

# Check GP header
if geom[0] == 0x47 and geom[1] == 0x50:
    flags = geom[3]
    envelope_type = (flags >> 1) & 0x07
    env_sizes = {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}
    env_size = env_sizes.get(envelope_type, 0)
    wkb_offset = 8 + env_size
    print(f"GPB: flags={flags:#04x}, env_type={envelope_type}, env_size={env_size}, wkb_offset={wkb_offset}")
    
    # Read WKB type
    byte_order = geom[wkb_offset]  # 0=BE, 1=LE
    is_le = byte_order == 1
    import struct
    endian = '<' if is_le else '>'
    wkb_type = struct.unpack_from(f'{endian}I', geom, wkb_offset + 1)[0]
    print(f"WKB: byte_order={'LE' if is_le else 'BE'}, type={wkb_type}")
    
    # Type 6 = MultiPolygon, 1006 = MultiPolygon Z
    base_type = wkb_type % 1000
    print(f"Base geometry type: {base_type} ({'MultiPolygon' if base_type == 6 else 'Polygon' if base_type == 3 else 'other'})")

    if base_type == 6:  # MultiPolygon
        num_polys = struct.unpack_from(f'{endian}I', geom, wkb_offset + 5)[0]
        print(f"Number of polygons: {num_polys}")
        
        # Read first polygon's first ring's first point
        off = wkb_offset + 9
        # Each polygon starts with its own WKB header
        bo2 = geom[off]
        off += 1
        ptype = struct.unpack_from(f'{endian}I', geom, off)[0]
        off += 4
        num_rings = struct.unpack_from(f'{endian}I', geom, off)[0]
        off += 4
        num_pts = struct.unpack_from(f'{endian}I', geom, off)[0]
        off += 4
        x = struct.unpack_from(f'{endian}d', geom, off)[0]
        y = struct.unpack_from(f'{endian}d', geom, off + 8)[0]
        print(f"First point: X={x}, Y={y}")

def tm_to_wgs84(e, n, cm, k0=0.9999, fe=500000):
    a = 6378137.0
    f_val = 1/298.257223563
    e2 = 2*f_val - f_val*f_val
    x = e - fe
    y = n
    M = y / k0
    mu = M / (a * (1 - e2/4 - 3*e2*e2/64 - 5*e2*e2*e2/256))
    e1 = (1 - math.sqrt(1-e2)) / (1 + math.sqrt(1-e2))
    phi1 = mu + (3*e1/2 - 27*e1**3/32)*math.sin(2*mu) + (21*e1*e1/16 - 55*e1**4/32)*math.sin(4*mu) + (151*e1**3/96)*math.sin(6*mu)
    sp = math.sin(phi1)
    cp = math.cos(phi1)
    tp = math.tan(phi1)
    ep2 = e2/(1-e2)
    N1 = a/math.sqrt(1-e2*sp*sp)
    T1 = tp*tp
    C1 = ep2*cp*cp
    R1 = a*(1-e2)/((1-e2*sp*sp)**1.5)
    D = x/(N1*k0)
    lat = phi1 - (N1*tp/R1)*(D*D/2 - (5+3*T1+10*C1-4*C1*C1-9*ep2)*D**4/24 + (61+90*T1+298*C1+45*T1*T1-252*ep2-3*C1*C1)*D**6/720)
    lon = (D - (1+2*T1+C1)*D**3/6 + (5-2*C1+28*T1-3*C1*C1+8*ep2+24*T1*T1)*D**5/120)/cp
    return (math.degrees(lat), cm + math.degrees(lon))

# Test with actual first point
print("\n=== Conversion Test ===")
lat, lon = tm_to_wgs84(x, y, 105.5)
print(f"Input:  E={x:.2f}, N={y:.2f} (VN-2000 TM-3 105.5)")
print(f"Output: lat={lat:.6f}, lon={lon:.6f}")
print(f"Expected: Ha Tinh ~18.0-18.5N, 105.5-106.0E")

# Test bounds
for label, ee, nn in [("SW", 526346.6875, 2005414.0), ("NE", 557137.0, 2028257.625)]:
    la, lo = tm_to_wgs84(ee, nn, 105.5)
    print(f"{label}: E={ee:.1f} N={nn:.1f} -> lat={la:.6f} lon={lo:.6f}")

db.close()
