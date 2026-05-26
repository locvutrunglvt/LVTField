import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';

/// Professional Help & Guide screen for LVTField app
/// Author: Lộc Vũ Trung
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hướng dẫn sử dụng'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearch(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.md),
        children: [
          // Header banner
          _buildBanner(),
          const SizedBox(height: 20),

          // Layout overview
          _HelpSection(
            icon: Icons.phone_android,
            iconColor: AppColors.primaryDark,
            title: 'Bố cục giao diện',
            items: const [
              _HelpItem(
                title: 'Tổng quan màn hình bản đồ',
                content: '📍 THANH TRÊN (Top Bar):\n'
                    '• ← Nút quay lại danh sách dự án\n'
                    '• Tên dự án đang mở\n'
                    '• 🛰️ Nút chuyển bản đồ nền (Vệ tinh ⇌ Đường phố)\n\n'
                    '📍 THANH TRÁI (Left Toolbar):\n'
                    '• Bấm nút ☰ để mở/đóng\n'
                    '• Thêm đối tượng, Chỉnh sửa, GPS Tracking\n'
                    '• Kiểu hiển thị, Zoom tới lớp\n\n'
                    '📍 BÊN PHẢI (Right Controls):\n'
                    '• Nút + / − : Phóng to / Thu nhỏ\n'
                    '• Nút GPS ⊕ : Quay về vị trí hiện tại\n'
                    '• Badge GPS accuracy (góc trên phải)\n\n'
                    '📍 THANH DƯỚI (Bottom Bar):\n'
                    '• Khi chưa chọn lớp: "Thêm lớp" + "Lớp"\n'
                    '• Khi đã chọn lớp: Nút vẽ nhanh + "Lớp"\n\n'
                    '📍 GÓC DƯỚI TRÁI:\n'
                    '• Tọa độ GPS thời gian thực',
              ),
            ],
          ),

          // Quick start
          _HelpSection(
            icon: Icons.rocket_launch,
            iconColor: const Color(0xFFFF6B35),
            title: 'Bắt đầu nhanh',
            items: const [
              _HelpItem(
                title: 'Tạo dự án mới',
                content: '1. Mở app → Bấm nút "+" ở góc dưới phải\n'
                    '2. Nhập tên dự án → Bấm "Tạo"\n'
                    '3. Dự án mới sẽ hiện trong danh sách',
              ),
              _HelpItem(
                title: 'Mở dự án',
                content: 'Chạm vào tên dự án trong danh sách để mở bản đồ.\n'
                    'Nhấn giữ để xem thêm tùy chọn (đổi tên, xóa, xuất).',
              ),
            ],
          ),

          // Layer Management
          _HelpSection(
            icon: Icons.layers,
            iconColor: AppColors.info,
            title: 'Quản lý lớp dữ liệu',
            items: const [
              _HelpItem(
                title: 'Tạo lớp mới',
                content: 'Cách 1 — Từ thanh dưới:\n'
                    '• Bấm "Thêm lớp" → Đặt tên + Chọn loại → Tạo\n\n'
                    'Cách 2 — Từ panel Lớp:\n'
                    '• Bấm "Lớp" ở thanh dưới → Bấm "+ Thêm lớp"\n'
                    '• Đặt tên + Chọn loại (Điểm/Đường/Vùng)\n'
                    '• Tùy chỉnh trường thuộc tính → "Tạo lớp"',
              ),
              _HelpItem(
                title: 'Panel Lớp (Layer Panel)',
                content: 'Bấm "Lớp" ở thanh dưới để mở panel:\n\n'
                    '• Bật/Tắt hiển thị: Bấm biểu tượng 👁 trên lớp\n'
                    '• Menu lớp (⋮): Nhấn vào dấu 3 chấm bên phải\n'
                    '  → Zoom tới lớp\n'
                    '  → Thêm đối tượng\n'
                    '  → Sửa đối tượng\n'
                    '  → GPS Tracking\n'
                    '  → Kiểu hiển thị\n'
                    '  → Đổi tên lớp\n'
                    '  → Xóa lớp\n\n'
                    '• Nhập lớp: Bấm "Nhập" ở cuối panel\n'
                    '• Xuất lớp: Bấm "Xuất" ở cuối panel',
              ),
              _HelpItem(
                title: 'Active Layer (Lớp hoạt động)',
                content: 'Khi chọn một lớp để vẽ, nó trở thành "Active Layer".\n\n'
                    '• Thanh dưới hiện tên lớp + nút vẽ nhanh\n'
                    '• Mỗi lần vẽ xong, lớp vẫn giữ active\n'
                    '• Bấm ✕ cạnh tên lớp để bỏ chọn\n'
                    '• KML, KMZ, MBTiles, GeoTIFF: chỉ xem (🔒)',
              ),
            ],
          ),

          // Feature Creation
          _HelpSection(
            icon: Icons.draw,
            iconColor: AppColors.polygonStroke,
            title: 'Tạo đối tượng',
            items: const [
              _HelpItem(
                title: '📍 Tạo Điểm',
                content: 'Cách 1 — Từ thanh dưới (khi đã có active layer Điểm):\n'
                    '• Bấm nút tạo điểm → Chạm 1 chấm trên bản đồ\n'
                    '• Bảng thuộc tính hiện ngay → Nhập thông tin → Lưu\n\n'
                    'Cách 2 — Từ toolbar trái:\n'
                    '• Mở toolbar ☰ → Bấm "Thêm"\n\n'
                    '💡 Nút GPS: Tạo điểm tại vị trí GPS hiện tại (1 chạm)',
              ),
              _HelpItem(
                title: '📏 Tạo Đường',
                content: '1. Chọn lớp Đường → Bấm nút tạo đường\n'
                    '2. Chạm bản đồ để thêm các đỉnh (≥ 2 điểm)\n'
                    '3. Dùng nút GPS để thêm đỉnh tại vị trí GPS\n'
                    '4. Bấm "Hoàn tác" để xóa đỉnh cuối\n'
                    '5. Bấm ✅ "Hoàn thành" → Bảng thuộc tính → Lưu',
              ),
              _HelpItem(
                title: '🔷 Tạo Vùng (Polygon)',
                content: '1. Chọn lớp Vùng → Bấm nút tạo vùng\n'
                    '2. Chạm bản đồ để thêm các đỉnh (≥ 3 điểm)\n'
                    '3. Vùng tự động đóng khi lưu\n'
                    '4. Bấm ✅ "Hoàn thành" → Bảng thuộc tính → Lưu\n\n'
                    '💡 Diện tích tự động tính khi có trường "Diện tích"',
              ),
              _HelpItem(
                title: 'Chỉnh sửa đỉnh',
                content: 'Mở toolbar trái ☰ → "Chỉnh sửa" → chọn đối tượng:\n\n'
                    '• Kéo đỉnh xanh 🟢 để di chuyển\n'
                    '• Nhấn giữ đỉnh → Xóa đỉnh\n'
                    '• Bấm nút ○ giữa 2 đỉnh → Thêm đỉnh mới\n'
                    '• ↩️ Hoàn tác nhiều bước\n'
                    '• ✅ Lưu hoặc ❌ Hủy',
              ),
            ],
          ),

          // Import
          _HelpSection(
            icon: Icons.file_download,
            iconColor: AppColors.primary,
            title: 'Nhập dữ liệu',
            items: const [
              _HelpItem(
                title: 'Các định dạng hỗ trợ',
                content: '📦 GeoPackage (.gpkg) — Vector + style từ QGIS\n'
                    '📐 Shapefile (.zip) — Nén .shp + .shx + .dbf + .prj\n'
                    '🌍 KML (.kml) — Google Earth (chỉ xem)\n'
                    '📦 KMZ (.kmz) — KML nén (chỉ xem)\n'
                    '📋 GeoJSON (.geojson) — Web GIS chuẩn\n'
                    '🗺️ MBTiles (.mbtiles) — Bản đồ nền offline\n'
                    '🖼️ GeoTIFF (.tif/.tiff) — Ảnh có tọa độ\n'
                    '💾 LVTField (.lvtfield) — Gói dự án',
              ),
              _HelpItem(
                title: 'Cách nhập',
                content: '1. Bấm "Lớp" ở thanh dưới → Mở panel lớp\n'
                    '2. Bấm "Nhập" ở cuối panel\n'
                    '3. Chọn định dạng muốn nhập\n'
                    '4. Chọn file từ thiết bị\n'
                    '5. Chờ xử lý → Dữ liệu hiện trên bản đồ\n\n'
                    '⚠️ Shapefile phải nén ZIP (bao gồm .shp, .shx, .dbf)\n'
                    '⚠️ GeoTIFF max 100MB (lớn hơn nên dùng MBTiles)',
              ),
              _HelpItem(
                title: 'GeoTIFF (Ảnh tọa độ)',
                content: 'App đọc tọa độ từ:\n'
                    '• Tag GeoTIFF trong file TIFF\n'
                    '• File world (.tfw/.wld) đi kèm\n\n'
                    'Hỗ trợ hệ tọa độ: WGS84, UTM Zone 48N, VN-2000\n'
                    'Tự động chuyển đổi về WGS84 để hiển thị.\n'
                    'Điều chỉnh độ trong suốt qua "Kiểu hiển thị" (menu lớp).',
              ),
              _HelpItem(
                title: 'GPKG từ QGIS',
                content: 'File GPKG đóng gói từ QGIS sẽ bảo toàn:\n'
                    '• Màu fill, stroke, opacity\n'
                    '• Độ rộng viền\n'
                    '• Nhãn (label field, font size, color)\n\n'
                    'Yêu cầu: File GPKG phải có bảng layer_styles\n'
                    '(QGIS tự tạo khi "Save Style in Database").',
              ),
            ],
          ),

          // Toolbar left
          _HelpSection(
            icon: Icons.menu,
            iconColor: Colors.green.shade700,
            title: 'Toolbar trái (☰)',
            items: const [
              _HelpItem(
                title: 'Mở / Đóng toolbar',
                content: 'Bấm nút ☰ ở góc trên bên trái bản đồ.\n'
                    'Toolbar hiện ra với 5 công cụ:',
              ),
              _HelpItem(
                title: '📌 Thêm đối tượng',
                content: 'Thêm feature mới vào lớp đang active.\n'
                    'Nếu chưa có lớp → hiện thông báo.',
              ),
              _HelpItem(
                title: '✏️ Chỉnh sửa',
                content: 'Chọn đối tượng trên lớp để chỉnh sửa đỉnh.\n'
                    'Hỗ trợ kéo, xóa, thêm đỉnh.',
              ),
              _HelpItem(
                title: '📡 GPS Tracking',
                content: 'Bật tracking GPS để tự động vẽ đường đi hoặc vùng.\n\n'
                    '📝 Khi lưu vết GPS, có 3 chế độ:\n'
                    '• Thêm vào layer đang kích hoạt (nếu có)\n'
                    '• Chọn từ layer có sẵn cùng loại hình\n'
                    '• Tạo layer mới (tên tự động: Line_/Poly_ngàythángnăm_giờ)\n\n'
                    '🔗 Khi add vào layer có sẵn:\n'
                    '• Tự động hiển thị form nhập liệu của layer đó\n'
                    '• Tự động tính diện tích, chiều dài, tọa độ\n'
                    '• Số thứ tự tự tăng (auto increment)',
              ),
              _HelpItem(
                title: '🎨 Kiểu hiển thị',
                content: 'Thay đổi màu sắc, độ rộng viền, nhãn cho lớp.\n'
                    '• Chọn màu fill/stroke\n'
                    '• Điều chỉnh độ mờ\n'
                    '• Chọn trường label\n'
                    '• Bấm "Áp dụng" ở cuối để lưu (cuộn xuống)',
              ),
              _HelpItem(
                title: '🔍 Zoom tới lớp',
                content: 'Zoom bản đồ vừa vặn để thấy toàn bộ đối tượng\n'
                    'của lớp đang chọn.',
              ),
            ],
          ),

          // Export
          _HelpSection(
            icon: Icons.file_upload,
            iconColor: AppColors.success,
            title: 'Xuất dữ liệu',
            items: const [
              _HelpItem(
                title: 'Cách xuất',
                content: '1. Bấm "Lớp" ở thanh dưới → Mở panel lớp\n'
                    '2. Bấm "Xuất" ở cuối panel\n'
                    '3. Chọn định dạng:\n\n'
                    '📦 GeoPackage (.gpkg) — Mở được trong QGIS\n'
                    '🌍 KML (.kml) — Mở trong Google Earth\n'
                    '📋 GeoJSON (.geojson) — Web GIS chuẩn\n'
                    '💾 LVTField (.lvtfield) — Gói toàn bộ dự án',
              ),
              _HelpItem(
                title: 'Chia sẻ',
                content: 'Sau khi xuất, file sẽ được chia sẻ qua:\n'
                    '• Zalo, Messenger, Gmail...\n'
                    '• Google Drive, OneDrive...\n'
                    '• Bluetooth, NFC...',
              ),
            ],
          ),

          // GPS
          _HelpSection(
            icon: Icons.gps_fixed,
            iconColor: AppColors.gpsCircleStroke,
            title: 'GPS & Định vị',
            items: const [
              _HelpItem(
                title: 'Badge GPS (góc trên phải)',
                content: 'Hiện trạng thái GPS thời gian thực:\n'
                    '• 🟢 Xanh: Độ chính xác tốt (< 5m)\n'
                    '• 🟡 Vàng: Trung bình (5-15m)\n'
                    '• 🔴 Đỏ: Kém (> 15m)\n\n'
                    'Bấm vào badge để xem chi tiết.',
              ),
              _HelpItem(
                title: 'Nút GPS (bên phải)',
                content: 'Nút ⊕ ở cạnh phải bản đồ (dưới nút zoom):\n'
                    '• Bấm 1 lần: Quay về vị trí GPS hiện tại\n'
                    '• Bấm lần 2: Bật chế độ tự động theo dõi\n'
                    '• Kéo bản đồ: Tắt tự động theo dõi',
              ),
              _HelpItem(
                title: 'GPS luôn bật',
                content: 'GPS của app luôn hoạt động khi mở bản đồ.\n'
                    'Đảm bảo đã cấp quyền vị trí cho app.\n'
                    'Ra ngoài trời để có tín hiệu GPS tốt nhất.',
              ),
            ],
          ),

          // Basemap
          _HelpSection(
            icon: Icons.map,
            iconColor: AppColors.secondary,
            title: 'Bản đồ nền',
            items: const [
              _HelpItem(
                title: 'Chuyển đổi bản đồ nền',
                content: 'Bấm nút 🛰️/🗺️ ở góc trên bên phải (thanh trên):\n\n'
                    '🛰️ Google Satellite — Ảnh vệ tinh\n'
                    '🗺️ OpenStreetMap — Bản đồ đường phố\n\n'
                    '💡 MBTiles: Nhập file .mbtiles qua panel Lớp\n'
                    'để dùng bản đồ nền offline.',
              ),
            ],
          ),

          // Coordinate System
          _HelpSection(
            icon: Icons.public,
            iconColor: const Color(0xFF7B1FA2),
            title: 'Hệ tọa độ (CRS)',
            items: const [
              _HelpItem(
                title: 'Nút CRS trên bản đồ',
                content: 'Nút CRS (tím) nằm ở góc phải bên dưới bản đồ,\n'
                    'phía trên nút GPS. Bấm để mở bảng chuyển đổi:\n\n'
                    '📊 Phần 1 — Xem nhanh 5 hệ chính:\n'
                    '• EPSG:4326 — WGS 84 (Lat°, Lon°)\n'
                    '• EPSG:32648 — WGS 84 / UTM 48N\n'
                    '• EPSG:32649 — WGS 84 / UTM 49N\n'
                    '• EPSG:3405 — VN-2000 / UTM 48N\n'
                    '• EPSG:3406 — VN-2000 / UTM 49N\n\n'
                    '📋 Phần 2 — Chọn CRS hiển thị:\n'
                    '• Danh sách đầy đủ 23 hệ VN-2000\n'
                    '• Bấm chọn → Thanh trạng thái cập nhật\n'
                    '• Tọa độ tính toán thời gian thực',
              ),
              _HelpItem(
                title: 'Danh sách VN-2000 TM-3',
                content: 'App hỗ trợ tất cả hệ VN-2000 TM-3 (k₀=0.9999):\n\n'
                    '• TM-3 103-00 → TM-3 108-30 (15 vùng)\n'
                    '• TM-3 zone 481, 482, 491 (3 vùng)\n'
                    '• TM-3 Da Nang zone\n'
                    '• VN-2000 / UTM 48N, 49N (k₀=0.9996)\n\n'
                    'Tham số chuyển đổi: TOWGS84 Helmert 7-param\n'
                    '(EPSG:6960 — Cục Đo đạc Bản đồ Việt Nam)\n'
                    'Sai số: ~1.0m',
              ),
              _HelpItem(
                title: 'Thanh tọa độ (góc dưới trái)',
                content: 'Chạm vào ô tọa độ để chuyển đổi chế độ:\n\n'
                    '1. WGS 84 → 2. VN-2000 → 3. UTM →\n'
                    '4. CRS đã chọn → quay lại 1.\n\n'
                    'CRS đã chọn sẽ hiển thị theo lựa chọn\n'
                    'từ bảng CRS (nút tím).',
              ),
            ],
          ),

          // GPS Track
          _HelpSection(
            icon: Icons.route,
            iconColor: const Color(0xFFFF5722),
            title: 'Lưu vệt GPS',
            items: const [
              _HelpItem(
                title: 'Ghi lại vệt di chuyển',
                content: 'Nút 🔴 (cam) ở góc phải bên dưới bản đồ:\n\n'
                    '1. Bấm nút → Nhập tên vệt → Bắt đầu\n'
                    '2. ▶ Record: Đang ghi (vệt hiện trên bản đồ)\n'
                    '3. ⏸ Pause: Tạm dừng ghi\n'
                    '4. ⏹ Stop: Dừng và lưu\n\n'
                    'Vệt GPS tự động lưu vào lớp đường.',
              ),
            ],
          ),

          // Right-side controls
          _HelpSection(
            icon: Icons.gamepad,
            iconColor: AppColors.primary,
            title: 'Nút điều khiển (góc phải)',
            items: const [
              _HelpItem(
                title: 'Thứ tự từ trên xuống',
                content: '1. CRS (tím) — Chuyển đổi hệ tọa độ\n'
                    '2. GPS ⊕ — Quay về vị trí hiện tại\n'
                    '3. + Zoom In — Phóng to\n'
                    '4. Z Level — Mức zoom hiện tại\n'
                    '5. − Zoom Out — Thu nhỏ\n'
                    '6. 🔴 Track — Lưu vệt GPS\n'
                    '7. 🔵 Layers — Quản lý lớp',
              ),
            ],
          ),

          // Tips & Tricks
          _HelpSection(
            icon: Icons.tips_and_updates,
            iconColor: AppColors.warning,
            title: 'Mẹo sử dụng',
            items: const [
              _HelpItem(
                title: 'Vẽ nhanh nhiều đối tượng',
                content: '• Chọn lớp active 1 lần → vẽ liên tục không cần chọn lại\n'
                    '• Point: Chạm = tạo ngay (form hiện tự động)\n'
                    '• GPS: Nút GPS tạo điểm tại vị trí hiện tại (1 chạm)',
              ),
              _HelpItem(
                title: 'Bảo toàn style QGIS',
                content: 'File GPKG từ QGIS sẽ giữ nguyên:\n'
                    '• Màu fill, stroke, opacity\n'
                    '• Độ rộng viền\n'
                    '• Nhãn (label) với font size và màu',
              ),
              _HelpItem(
                title: 'Sao lưu dự án',
                content: 'Xuất dự án dạng .lvtfield để sao lưu.\n'
                    'File bao gồm toàn bộ: layers + features + attributes.\n'
                    'Nhập lại file .lvtfield để khôi phục.',
              ),
            ],
          ),

          const SizedBox(height: 24),
          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(Icons.forest, color: AppColors.primary, size: 32),
                const SizedBox(height: 8),
                Text(
                  'LVTField — Mobile GIS for Field Survey',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '© 2024 Lộc Vũ Trung',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.menu_book, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hướng dẫn sử dụng',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Tìm hiểu tất cả tính năng của LVTField',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSearch(BuildContext context) {
    showSearch(context: context, delegate: _HelpSearchDelegate());
  }
}

// =============================================================================
// Help Section (expandable category)
// =============================================================================
class _HelpSection extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<_HelpItem> items;

  const _HelpSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          subtitle: Text(
            '${items.length} mục',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          children: items.map((item) => _buildItem(context, item)).toList(),
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, _HelpItem item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white12 : AppColors.divider,
          width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.content,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: isDark ? Colors.white70 : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Help Item (single help entry)
// =============================================================================
class _HelpItem {
  final String title;
  final String content;

  const _HelpItem({required this.title, required this.content});
}

// =============================================================================
// Help Search Delegate
// =============================================================================
class _HelpSearchDelegate extends SearchDelegate<String> {
  final List<Map<String, String>> _allItems = [
    {'title': 'Bố cục giao diện', 'section': 'Giao diện', 'keyword': 'layout trái phải trên dưới toolbar'},
    {'title': 'Tạo dự án mới', 'section': 'Bắt đầu nhanh', 'keyword': 'tạo dự án project'},
    {'title': 'Mở dự án', 'section': 'Bắt đầu nhanh', 'keyword': 'mở dự án open'},
    {'title': 'Tạo lớp mới', 'section': 'Quản lý lớp', 'keyword': 'tạo lớp layer'},
    {'title': 'Panel Lớp', 'section': 'Quản lý lớp', 'keyword': 'panel lớp layer nhập xuất'},
    {'title': 'Active Layer', 'section': 'Quản lý lớp', 'keyword': 'active lớp hoạt động'},
    {'title': 'Tạo Điểm', 'section': 'Tạo đối tượng', 'keyword': 'tạo điểm point chấm'},
    {'title': 'Tạo Đường', 'section': 'Tạo đối tượng', 'keyword': 'tạo đường line'},
    {'title': 'Tạo Vùng', 'section': 'Tạo đối tượng', 'keyword': 'tạo vùng polygon'},
    {'title': 'Chỉnh sửa đỉnh', 'section': 'Tạo đối tượng', 'keyword': 'sửa đỉnh vertex kéo'},
    {'title': 'Định dạng nhập', 'section': 'Nhập dữ liệu', 'keyword': 'gpkg shp kml geojson mbtiles tiff'},
    {'title': 'GPKG từ QGIS', 'section': 'Nhập dữ liệu', 'keyword': 'gpkg style label qgis'},
    {'title': 'GeoTIFF', 'section': 'Nhập dữ liệu', 'keyword': 'tiff ảnh tọa độ overlay'},
    {'title': 'Toolbar trái', 'section': 'Toolbar trái', 'keyword': 'toolbar trái thêm sửa kiểu hiển thị'},
    {'title': 'Xuất dữ liệu', 'section': 'Xuất dữ liệu', 'keyword': 'xuất export'},
    {'title': 'GPS Badge', 'section': 'GPS', 'keyword': 'gps accuracy badge'},
    {'title': 'Nút GPS', 'section': 'GPS', 'keyword': 'gps center nút phải'},
    {'title': 'Bản đồ nền', 'section': 'Bản đồ nền', 'keyword': 'basemap satellite google osm'},
    {'title': 'Hệ tọa độ', 'section': 'Hệ tọa độ (CRS)', 'keyword': 'crs wgs84 vn2000 utm tm-3 epsg chuyển đổi'},
    {'title': 'VN-2000 TM-3', 'section': 'Hệ tọa độ (CRS)', 'keyword': 'vn2000 tm3 helmert datum 3405 3406 9205'},
    {'title': 'Lưu vệt GPS', 'section': 'Lưu vệt GPS', 'keyword': 'track vệt gps record route'},
    {'title': 'Nút điều khiển', 'section': 'Nút điều khiển', 'keyword': 'nút phải zoom gps crs layers'},
    {'title': 'Mẹo vẽ nhanh', 'section': 'Mẹo sử dụng', 'keyword': 'mẹo nhanh tip'},
    {'title': 'Sao lưu dự án', 'section': 'Mẹo sử dụng', 'keyword': 'sao lưu backup lvtfield'},
  ];

  @override
  String get searchFieldLabel => 'Tìm kiếm hướng dẫn...';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, ''),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSuggestionList();

  @override
  Widget buildSuggestions(BuildContext context) => _buildSuggestionList();

  Widget _buildSuggestionList() {
    final q = query.toLowerCase();
    final filtered = q.isEmpty
        ? _allItems
        : _allItems.where((item) {
            return item['title']!.toLowerCase().contains(q) ||
                item['keyword']!.toLowerCase().contains(q) ||
                item['section']!.toLowerCase().contains(q);
          }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              'Không tìm thấy "$query"',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = filtered[index];
        return ListTile(
          leading: const Icon(Icons.help_outline, color: AppColors.primary),
          title: Text(
            item['title']!,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(item['section']!, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => close(context, item['title']!),
        );
      },
    );
  }
}
