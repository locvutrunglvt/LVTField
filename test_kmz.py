"""
Analyze Hung Duc KMZ file to extract Description HTML structure
"""
import zipfile
import xml.etree.ElementTree as ET
import os

kmz_path = r"G:\My Drive\GIS\FSC\Tuyen Quang\Hung Duc\Hung Duc KML_22May2026.kmz"

# KMZ is a ZIP containing KML
with zipfile.ZipFile(kmz_path, 'r') as z:
    print("Files in KMZ:")
    for f in z.namelist():
        print(f"  {f} ({z.getinfo(f).file_size} bytes)")
    
    # Find the KML file
    kml_files = [f for f in z.namelist() if f.endswith('.kml')]
    if not kml_files:
        print("No KML file found!")
        exit()
    
    kml_content = z.read(kml_files[0]).decode('utf-8')

# Parse KML
# KML uses namespaces
ns = {'kml': 'http://www.opengis.net/kml/2.2'}

root = ET.fromstring(kml_content)

# Find all Placemarks
placemarks = root.findall('.//kml:Placemark', ns)
print(f"\nTotal Placemarks: {len(placemarks)}")

# Examine first few placemarks
for i, pm in enumerate(placemarks[:3]):
    name_el = pm.find('kml:name', ns)
    desc_el = pm.find('kml:description', ns)
    
    name = name_el.text if name_el is not None else "N/A"
    desc = desc_el.text if desc_el is not None else "N/A"
    
    print(f"\n{'='*80}")
    print(f"Placemark {i}: name={name}")
    print(f"Description ({len(desc)} chars):")
    print(desc[:2000] if desc else "None")
    
    # Check for ExtendedData
    ext_data = pm.find('kml:ExtendedData', ns)
    if ext_data is not None:
        print("\nExtendedData found:")
        for data in ext_data.findall('kml:Data', ns) + ext_data.findall('kml:SchemaData', ns):
            print(f"  {ET.tostring(data, encoding='unicode')[:200]}")
    
    # Check geometry type
    for geom_type in ['Point', 'LineString', 'Polygon', 'MultiGeometry']:
        geom = pm.find(f'.//kml:{geom_type}', ns)
        if geom is not None:
            print(f"\nGeometry: {geom_type}")
            break

# Also check Schema definitions
schemas = root.findall('.//kml:Schema', ns)
for schema in schemas:
    print(f"\n{'='*80}")
    print(f"Schema: {schema.get('name', 'N/A')}")
    for field in schema.findall('kml:SimpleField', ns):
        print(f"  Field: {field.get('name')} (type={field.get('type')})")

# Check if there's SchemaData with SimpleData
for i, pm in enumerate(placemarks[:2]):
    schema_data = pm.find('.//kml:SchemaData', ns)
    if schema_data is not None:
        print(f"\nPlacemark {i} SchemaData:")
        for sd in schema_data.findall('kml:SimpleData', ns):
            print(f"  {sd.get('name')} = {sd.text}")
