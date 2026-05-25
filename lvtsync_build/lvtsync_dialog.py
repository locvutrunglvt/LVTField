# -*- coding: utf-8 -*-
"""
LVT Sync - Main dialog with Login, Projects, and Sync tabs.
All UI text is in Vietnamese.
Author: Lộc Vũ Trung
"""

import json
import traceback
from datetime import datetime

from qgis.PyQt.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QFormLayout, QGridLayout,
    QTabWidget, QWidget, QLabel, QLineEdit, QPushButton,
    QTableWidget, QTableWidgetItem, QTextEdit, QProgressBar,
    QHeaderView, QMessageBox, QAbstractItemView, QGroupBox,
    QSizePolicy,
)
from qgis.PyQt.QtCore import Qt, QVariant
from qgis.PyQt.QtGui import QFont, QColor

from qgis.core import (
    QgsProject, QgsVectorLayer, QgsFeature, QgsGeometry,
    QgsPointXY, QgsField, QgsFields, QgsCoordinateReferenceSystem,
    QgsWkbTypes,
)

from .pocketbase_client import PocketBaseClient


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

def _qgis_geom_type_to_server(wkb_type):
    """Map QGIS WKB geometry type to server string."""
    flat = QgsWkbTypes.flatType(wkb_type)
    mapping = {
        QgsWkbTypes.Point: 'point',
        QgsWkbTypes.MultiPoint: 'point',
        QgsWkbTypes.LineString: 'linestring',
        QgsWkbTypes.MultiLineString: 'linestring',
        QgsWkbTypes.Polygon: 'polygon',
        QgsWkbTypes.MultiPolygon: 'polygon',
    }
    return mapping.get(flat, 'point')


def _server_geom_type_to_qgis_uri(geom_type):
    """Map server geometry type string to QGIS memory layer URI type."""
    mapping = {
        'point': 'Point',
        'linestring': 'LineString',
        'polygon': 'Polygon',
    }
    return mapping.get(geom_type, 'Point')


def _coords_json_to_qgs_geometry(coords_json_str, geom_type):
    """Convert server coordinates_json to QgsGeometry.

    Server format: [[lat, lng], [lat, lng], ...]
    QGIS uses QgsPointXY(lng, lat).
    """
    try:
        coords = json.loads(coords_json_str) if isinstance(coords_json_str, str) else coords_json_str
    except (json.JSONDecodeError, TypeError):
        return None

    if not coords:
        return None

    if geom_type == 'point':
        # Single point: [lat, lng] or [[lat, lng]]
        if isinstance(coords[0], (int, float)):
            lat, lng = coords[0], coords[1]
        else:
            lat, lng = coords[0][0], coords[0][1]
        return QgsGeometry.fromPointXY(QgsPointXY(lng, lat))

    elif geom_type == 'linestring':
        points = [QgsPointXY(c[1], c[0]) for c in coords]
        return QgsGeometry.fromPolylineXY(points)

    elif geom_type == 'polygon':
        points = [QgsPointXY(c[1], c[0]) for c in coords]
        # Close ring if needed
        if points and points[0] != points[-1]:
            points.append(points[0])
        return QgsGeometry.fromPolygonXY([points])

    return None


def _qgs_geometry_to_coords_json(geometry, geom_type):
    """Convert QgsGeometry to server coordinates_json string.

    Returns JSON string of [[lat, lng], ...].
    """
    if geometry is None or geometry.isEmpty():
        return '[]'

    if geom_type == 'point':
        pt = geometry.asPoint()
        return json.dumps([[pt.y(), pt.x()]])

    elif geom_type == 'linestring':
        # Handle both single and multi linestring
        if geometry.isMultipart():
            lines = geometry.asMultiPolyline()
            points = lines[0] if lines else []
        else:
            points = geometry.asPolyline()
        return json.dumps([[p.y(), p.x()] for p in points])

    elif geom_type == 'polygon':
        # Handle both single and multi polygon
        if geometry.isMultipart():
            polygons = geometry.asMultiPolygon()
            ring = polygons[0][0] if polygons and polygons[0] else []
        else:
            rings = geometry.asPolygon()
            ring = rings[0] if rings else []
        return json.dumps([[p.y(), p.x()] for p in ring])

    return '[]'


# ---------------------------------------------------------------------------
# Main Dialog
# ---------------------------------------------------------------------------

class LVTSyncDialog(QDialog):
    """Main dialog for LVT Sync plugin with three tabs."""

    def __init__(self, iface, parent=None):
        super().__init__(parent)
        self.iface = iface
        self.client = PocketBaseClient()
        self._projects_cache = []

        self._setup_ui()
        self._connect_signals()
        self._update_auth_ui()

    # ------------------------------------------------------------------
    # UI Setup
    # ------------------------------------------------------------------

    def _setup_ui(self):
        """Build the complete dialog UI."""
        self.setWindowTitle('LVT Sync — Đồng bộ LVTField')
        self.resize(600, 500)
        self.setMinimumSize(500, 400)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(8, 8, 8, 8)

        # Tab widget
        self.tabs = QTabWidget()
        layout.addWidget(self.tabs)

        # Create tabs
        self.tabs.addTab(self._create_login_tab(), '🔑 Đăng nhập')
        self.tabs.addTab(self._create_projects_tab(), '📁 Dự án')
        self.tabs.addTab(self._create_sync_tab(), '🔄 Đồng bộ')

        # Bottom status bar
        self.lbl_status_bar = QLabel('')
        self.lbl_status_bar.setStyleSheet('color: #666; font-size: 11px; padding: 2px;')
        layout.addWidget(self.lbl_status_bar)

    # -- Tab 1: Login -------------------------------------------------------

    def _create_login_tab(self):
        """Create the login/authentication tab."""
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(12)

        # Server group
        grp_server = QGroupBox('Máy chủ')
        grp_layout = QFormLayout(grp_server)
        self.txt_server_url = QLineEdit(PocketBaseClient.DEFAULT_URL)
        self.txt_server_url.setPlaceholderText('https://lvtfield.lvtcenter.it.com')
        self.btn_health = QPushButton('Kiểm tra kết nối')
        self.btn_health.setFixedWidth(140)
        row = QHBoxLayout()
        row.addWidget(self.txt_server_url)
        row.addWidget(self.btn_health)
        grp_layout.addRow('URL:', row)
        layout.addWidget(grp_server)

        # Login group
        grp_login = QGroupBox('Tài khoản')
        login_layout = QFormLayout(grp_login)

        self.txt_email = QLineEdit('locvutrung@gmail.com')
        self.txt_email.setPlaceholderText('email@example.com')
        login_layout.addRow('Email:', self.txt_email)

        self.txt_password = QLineEdit()
        self.txt_password.setEchoMode(QLineEdit.Password)
        self.txt_password.setPlaceholderText('Mật khẩu')
        login_layout.addRow('Mật khẩu:', self.txt_password)

        btn_row = QHBoxLayout()
        self.btn_login = QPushButton('Đăng nhập')
        self.btn_login.setStyleSheet(
            'QPushButton { background-color: #2196F3; color: white; padding: 6px 20px; '
            'border-radius: 4px; font-weight: bold; } '
            'QPushButton:hover { background-color: #1976D2; }'
        )
        self.btn_logout = QPushButton('Đăng xuất')
        self.btn_logout.setEnabled(False)
        btn_row.addWidget(self.btn_login)
        btn_row.addWidget(self.btn_logout)
        btn_row.addStretch()
        login_layout.addRow('', btn_row)

        layout.addWidget(grp_login)

        # Status group
        grp_status = QGroupBox('Trạng thái')
        status_layout = QFormLayout(grp_status)
        self.lbl_auth_status = QLabel('⚪ Chưa đăng nhập')
        self.lbl_auth_status.setFont(QFont('Segoe UI', 10))
        status_layout.addRow(self.lbl_auth_status)
        self.lbl_user_info = QLabel('')
        status_layout.addRow(self.lbl_user_info)
        layout.addWidget(grp_status)

        layout.addStretch()
        return widget

    # -- Tab 2: Projects -----------------------------------------------------

    def _create_projects_tab(self):
        """Create the projects listing tab."""
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(8)

        # Toolbar
        toolbar = QHBoxLayout()
        self.btn_refresh_projects = QPushButton('🔄 Làm mới')
        self.btn_download_project = QPushButton('⬇️ Tải về QGIS')
        self.btn_download_project.setStyleSheet(
            'QPushButton { background-color: #4CAF50; color: white; padding: 6px 16px; '
            'border-radius: 4px; font-weight: bold; } '
            'QPushButton:hover { background-color: #388E3C; }'
        )
        toolbar.addWidget(self.btn_refresh_projects)
        toolbar.addStretch()
        toolbar.addWidget(self.btn_download_project)
        layout.addLayout(toolbar)

        # Projects table
        self.tbl_projects = QTableWidget(0, 4)
        self.tbl_projects.setHorizontalHeaderLabels([
            'Tên dự án', 'Mô tả', 'Số layer', 'ID'
        ])
        header = self.tbl_projects.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.Stretch)
        header.setSectionResizeMode(1, QHeaderView.Stretch)
        header.setSectionResizeMode(2, QHeaderView.ResizeToContents)
        header.setSectionResizeMode(3, QHeaderView.ResizeToContents)
        self.tbl_projects.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.tbl_projects.setSelectionMode(QAbstractItemView.SingleSelection)
        self.tbl_projects.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.tbl_projects.setAlternatingRowColors(True)
        layout.addWidget(self.tbl_projects)

        # Info label
        self.lbl_projects_info = QLabel('Nhấn "Làm mới" để tải danh sách dự án.')
        self.lbl_projects_info.setStyleSheet('color: #888;')
        layout.addWidget(self.lbl_projects_info)

        return widget

    # -- Tab 3: Sync ---------------------------------------------------------

    def _create_sync_tab(self):
        """Create the synchronization tab."""
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(8)

        # Action buttons
        btn_layout = QHBoxLayout()
        self.btn_push = QPushButton('⬆️ Đẩy lên server')
        self.btn_push.setStyleSheet(
            'QPushButton { background-color: #FF9800; color: white; padding: 8px 20px; '
            'border-radius: 4px; font-weight: bold; font-size: 12px; } '
            'QPushButton:hover { background-color: #F57C00; }'
        )
        self.btn_pull = QPushButton('⬇️ Tải về từ server')
        self.btn_pull.setStyleSheet(
            'QPushButton { background-color: #2196F3; color: white; padding: 8px 20px; '
            'border-radius: 4px; font-weight: bold; font-size: 12px; } '
            'QPushButton:hover { background-color: #1976D2; }'
        )
        btn_layout.addWidget(self.btn_push)
        btn_layout.addWidget(self.btn_pull)
        layout.addLayout(btn_layout)

        # Progress
        self.progress = QProgressBar()
        self.progress.setRange(0, 100)
        self.progress.setValue(0)
        self.progress.setTextVisible(True)
        layout.addWidget(self.progress)

        # Last sync info
        info_layout = QHBoxLayout()
        self.lbl_last_sync = QLabel('Lần đồng bộ cuối: —')
        self.lbl_sync_stats = QLabel('')
        info_layout.addWidget(self.lbl_last_sync)
        info_layout.addStretch()
        info_layout.addWidget(self.lbl_sync_stats)
        layout.addLayout(info_layout)

        # Log area
        lbl_log = QLabel('Nhật ký:')
        lbl_log.setFont(QFont('Segoe UI', 9, QFont.Bold))
        layout.addWidget(lbl_log)

        self.txt_log = QTextEdit()
        self.txt_log.setReadOnly(True)
        self.txt_log.setFont(QFont('Consolas', 9))
        self.txt_log.setStyleSheet('background-color: #1e1e1e; color: #d4d4d4; padding: 4px;')
        layout.addWidget(self.txt_log)

        return widget

    # ------------------------------------------------------------------
    # Signal connections
    # ------------------------------------------------------------------

    def _connect_signals(self):
        """Connect all button signals to handlers."""
        self.btn_health.clicked.connect(self._on_health_check)
        self.btn_login.clicked.connect(self._on_login)
        self.btn_logout.clicked.connect(self._on_logout)
        self.btn_refresh_projects.clicked.connect(self._on_refresh_projects)
        self.btn_download_project.clicked.connect(self._on_download_project)
        self.btn_push.clicked.connect(self._on_push)
        self.btn_pull.clicked.connect(self._on_pull)
        self.txt_password.returnPressed.connect(self._on_login)

    # ------------------------------------------------------------------
    # Logging
    # ------------------------------------------------------------------

    def _log(self, message, level='info'):
        """Append a timestamped message to the sync log.

        Args:
            message: Log message text.
            level: One of 'info', 'ok', 'warn', 'error'.
        """
        timestamp = datetime.now().strftime('%H:%M:%S')
        colors = {
            'info': '#d4d4d4',
            'ok': '#4EC9B0',
            'warn': '#DCDCAA',
            'error': '#F44747',
        }
        color = colors.get(level, colors['info'])
        self.txt_log.append(
            f'<span style="color:#888">[{timestamp}]</span> '
            f'<span style="color:{color}">{message}</span>'
        )

    # ------------------------------------------------------------------
    # Auth UI
    # ------------------------------------------------------------------

    def _update_auth_ui(self):
        """Update login UI elements based on authentication state."""
        if self.client.is_authenticated:
            self.lbl_auth_status.setText('🟢 Đã đăng nhập')
            self.lbl_auth_status.setStyleSheet('color: #2e7d32; font-weight: bold;')
            self.lbl_user_info.setText(
                f'👤 {self.client.user_name or self.client.user_email}\n'
                f'📧 {self.client.user_email}\n'
                f'🆔 {self.client.user_id}'
            )
            self.btn_login.setEnabled(False)
            self.btn_logout.setEnabled(True)
            self.txt_email.setEnabled(False)
            self.txt_password.setEnabled(False)
            self.lbl_status_bar.setText(f'Đã đăng nhập: {self.client.user_email}')
        else:
            self.lbl_auth_status.setText('⚪ Chưa đăng nhập')
            self.lbl_auth_status.setStyleSheet('color: #666;')
            self.lbl_user_info.setText('')
            self.btn_login.setEnabled(True)
            self.btn_logout.setEnabled(False)
            self.txt_email.setEnabled(True)
            self.txt_password.setEnabled(True)
            self.lbl_status_bar.setText('')

    # ------------------------------------------------------------------
    # Handlers
    # ------------------------------------------------------------------

    def _on_health_check(self):
        """Check server connectivity."""
        url = self.txt_server_url.text().strip()
        self.client.base_url = url.rstrip('/')
        self.btn_health.setEnabled(False)
        self.btn_health.setText('Đang kiểm tra...')
        try:
            # Force UI repaint
            from qgis.PyQt.QtWidgets import QApplication
            QApplication.processEvents()

            ok = self.client.health_check()
            if ok:
                QMessageBox.information(self, 'Kết nối', '✅ Kết nối server thành công!')
            else:
                QMessageBox.warning(self, 'Kết nối', '❌ Server không phản hồi.')
        except Exception as exc:
            QMessageBox.critical(self, 'Lỗi', f'Không thể kết nối:\n{exc}')
        finally:
            self.btn_health.setEnabled(True)
            self.btn_health.setText('Kiểm tra kết nối')

    def _on_login(self):
        """Handle login button click."""
        email = self.txt_email.text().strip()
        password = self.txt_password.text()

        if not email or not password:
            QMessageBox.warning(self, 'Thiếu thông tin', 'Vui lòng nhập email và mật khẩu.')
            return

        url = self.txt_server_url.text().strip()
        self.client.base_url = url.rstrip('/')

        self.btn_login.setEnabled(False)
        self.btn_login.setText('Đang đăng nhập...')
        from qgis.PyQt.QtWidgets import QApplication
        QApplication.processEvents()

        try:
            self.client.login(email, password)
            self._update_auth_ui()
            self._log(f'Đăng nhập thành công: {self.client.user_email}', 'ok')
            QMessageBox.information(self, 'Thành công',
                                    f'Đã đăng nhập!\nXin chào {self.client.user_name or email}')
        except Exception as exc:
            QMessageBox.critical(self, 'Đăng nhập thất bại', f'Lỗi:\n{exc}')
            self._log(f'Đăng nhập thất bại: {exc}', 'error')
        finally:
            self.btn_login.setEnabled(True)
            self.btn_login.setText('Đăng nhập')

    def _on_logout(self):
        """Handle logout button click."""
        self.client.logout()
        self._update_auth_ui()
        self._log('Đã đăng xuất.', 'info')

    # -- Projects -----------------------------------------------------------

    def _on_refresh_projects(self):
        """Fetch and display projects from server."""
        if not self.client.is_authenticated:
            QMessageBox.warning(self, 'Chưa đăng nhập', 'Vui lòng đăng nhập trước.')
            self.tabs.setCurrentIndex(0)
            return

        self.btn_refresh_projects.setEnabled(False)
        self.lbl_projects_info.setText('Đang tải...')
        from qgis.PyQt.QtWidgets import QApplication
        QApplication.processEvents()

        try:
            projects = self.client.list_projects()
            self._projects_cache = projects
            self._populate_projects_table(projects)
            self.lbl_projects_info.setText(f'Tìm thấy {len(projects)} dự án.')
            self._log(f'Đã tải {len(projects)} dự án từ server.', 'ok')
        except Exception as exc:
            self.lbl_projects_info.setText(f'Lỗi: {exc}')
            self._log(f'Lỗi tải dự án: {exc}', 'error')
        finally:
            self.btn_refresh_projects.setEnabled(True)

    def _populate_projects_table(self, projects):
        """Fill the projects table with data.

        Args:
            projects: List of project dicts from server.
        """
        self.tbl_projects.setRowCount(0)
        for proj in projects:
            row = self.tbl_projects.rowCount()
            self.tbl_projects.insertRow(row)
            self.tbl_projects.setItem(row, 0, QTableWidgetItem(proj.get('name', '')))
            self.tbl_projects.setItem(row, 1, QTableWidgetItem(proj.get('description', '')))
            self.tbl_projects.setItem(row, 2, QTableWidgetItem('—'))  # layers count filled later
            self.tbl_projects.setItem(row, 3, QTableWidgetItem(proj.get('id', '')))

    def _on_download_project(self):
        """Download selected project's layers and features into QGIS."""
        if not self.client.is_authenticated:
            QMessageBox.warning(self, 'Chưa đăng nhập', 'Vui lòng đăng nhập trước.')
            return

        selected = self.tbl_projects.selectedItems()
        if not selected:
            QMessageBox.warning(self, 'Chưa chọn', 'Vui lòng chọn một dự án để tải.')
            return

        row = selected[0].row()
        project_name = self.tbl_projects.item(row, 0).text()
        project_id = self.tbl_projects.item(row, 3).text()

        reply = QMessageBox.question(
            self, 'Xác nhận tải về',
            f'Tải dự án "{project_name}" về QGIS?\n\n'
            'Các layer sẽ được thêm mới (không ghi đè layer hiện tại).',
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No
        )
        if reply != QMessageBox.Yes:
            return

        self._download_project(project_id, project_name)

    def _download_project(self, project_id, project_name):
        """Execute the project download process.

        Args:
            project_id: Remote project ID.
            project_name: Project name for display.
        """
        from qgis.PyQt.QtWidgets import QApplication

        self._log(f'Bắt đầu tải dự án: {project_name}', 'info')
        self.progress.setValue(0)

        try:
            # Fetch layers
            layers = self.client.list_layers(project_id)
            self._log(f'Tìm thấy {len(layers)} layer.', 'info')

            if not layers:
                self._log('Dự án không có layer nào.', 'warn')
                return

            total_steps = len(layers)
            features_total = 0

            for idx, layer_data in enumerate(layers):
                layer_name = layer_data.get('name', f'Layer_{idx}')
                layer_id = layer_data.get('id', '')
                geom_type = layer_data.get('geometry_type', 'point')

                self._log(f'  → Tải layer: {layer_name} ({geom_type})', 'info')
                QApplication.processEvents()

                # Fetch features
                features = self.client.list_all_features(layer_id)
                self._log(f'    {len(features)} features.', 'info')

                # Create QGIS memory layer
                qgis_layer = self._create_qgis_layer(
                    layer_name, geom_type, features, project_name
                )

                if qgis_layer and qgis_layer.isValid():
                    QgsProject.instance().addMapLayer(qgis_layer)
                    features_total += len(features)
                    self._log(f'    ✅ Đã thêm layer "{layer_name}" vào QGIS.', 'ok')
                else:
                    self._log(f'    ❌ Lỗi tạo layer "{layer_name}".', 'error')

                # Update progress
                progress_pct = int(((idx + 1) / total_steps) * 100)
                self.progress.setValue(progress_pct)
                QApplication.processEvents()

            self._log(f'Hoàn tất! Đã tải {len(layers)} layer, '
                      f'{features_total} features.', 'ok')
            self.lbl_last_sync.setText(
                f'Lần đồng bộ cuối: {datetime.now().strftime("%H:%M:%S %d/%m/%Y")}'
            )
            self.lbl_sync_stats.setText(f'⬇ {features_total} features')

        except Exception as exc:
            self._log(f'Lỗi tải dự án: {exc}', 'error')
            self._log(traceback.format_exc(), 'error')

    def _create_qgis_layer(self, name, geom_type, features, group_name=''):
        """Create a QgsVectorLayer from server feature data.

        Args:
            name: Layer name.
            geom_type: Server geometry type string.
            features: List of feature dicts from server.
            group_name: Optional group/project name prefix.

        Returns:
            QgsVectorLayer or None on failure.
        """
        qgis_geom = _server_geom_type_to_qgis_uri(geom_type)
        display_name = f'{group_name} — {name}' if group_name else name
        uri = f'{qgis_geom}?crs=EPSG:4326&index=yes'

        layer = QgsVectorLayer(uri, display_name, 'memory')
        if not layer.isValid():
            return None

        provider = layer.dataProvider()

        # Collect all attribute keys from features
        all_attr_keys = set()
        for feat_data in features:
            attrs_str = feat_data.get('attributes', '{}')
            try:
                attrs = json.loads(attrs_str) if isinstance(attrs_str, str) else (attrs_str or {})
            except (json.JSONDecodeError, TypeError):
                attrs = {}
            all_attr_keys.update(attrs.keys())

        # Always add remote_id field for tracking
        fields = [QgsField('remote_id', QVariant.String)]
        fields.append(QgsField('remote_layer_id', QVariant.String))
        fields.append(QgsField('remote_version', QVariant.Int))

        for key in sorted(all_attr_keys):
            fields.append(QgsField(key, QVariant.String))

        provider.addAttributes(fields)
        layer.updateFields()

        # Add features
        qgs_features = []
        for feat_data in features:
            coords_json = feat_data.get('coordinates_json', '[]')
            geom = _coords_json_to_qgs_geometry(coords_json, geom_type)

            attrs_str = feat_data.get('attributes', '{}')
            try:
                attrs = json.loads(attrs_str) if isinstance(attrs_str, str) else (attrs_str or {})
            except (json.JSONDecodeError, TypeError):
                attrs = {}

            qfeat = QgsFeature(layer.fields())
            if geom:
                qfeat.setGeometry(geom)

            # Set tracking attributes
            qfeat.setAttribute('remote_id', feat_data.get('id', ''))
            qfeat.setAttribute('remote_layer_id', feat_data.get('layer_id', ''))
            qfeat.setAttribute('remote_version', feat_data.get('version', 1))

            # Set user attributes
            for key in sorted(all_attr_keys):
                val = attrs.get(key, '')
                qfeat.setAttribute(key, str(val) if val is not None else '')

            qgs_features.append(qfeat)

        if qgs_features:
            provider.addFeatures(qgs_features)
            layer.updateExtents()

        return layer

    # -- Sync: Push ----------------------------------------------------------

    def _on_push(self):
        """Push current QGIS project layers to server."""
        if not self.client.is_authenticated:
            QMessageBox.warning(self, 'Chưa đăng nhập', 'Vui lòng đăng nhập trước.')
            self.tabs.setCurrentIndex(0)
            return

        # Collect vector layers
        qgis_project = QgsProject.instance()
        vector_layers = [
            lyr for lyr in qgis_project.mapLayers().values()
            if isinstance(lyr, QgsVectorLayer) and lyr.featureCount() > 0
        ]

        if not vector_layers:
            QMessageBox.information(self, 'Không có dữ liệu',
                                    'Không có vector layer nào trong project.')
            return

        # Summary
        layer_info = '\n'.join(
            f'  • {lyr.name()} ({lyr.featureCount()} features)'
            for lyr in vector_layers
        )
        reply = QMessageBox.question(
            self, 'Xác nhận đẩy lên server',
            f'Đẩy {len(vector_layers)} layer lên server?\n\n{layer_info}\n\n'
            '⚠️ Dữ liệu sẽ được THÊM MỚI, không xóa dữ liệu cũ.',
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No
        )
        if reply != QMessageBox.Yes:
            return

        self._push_layers(vector_layers)

    def _push_layers(self, vector_layers):
        """Push vector layers to PocketBase server.

        SAFETY: NEVER deletes anything on server. Only creates new records.

        Args:
            vector_layers: List of QgsVectorLayer objects.
        """
        from qgis.PyQt.QtWidgets import QApplication

        qgis_project = QgsProject.instance()
        project_name = qgis_project.baseName() or 'QGIS Project'

        self._log(f'Bắt đầu đẩy lên: {project_name}', 'info')
        self.progress.setValue(0)

        try:
            # Create project on server
            self._log(f'Tạo dự án: {project_name}', 'info')
            remote_project = self.client.create_project(
                name=project_name,
                description=f'Đẩy từ QGIS — {datetime.now().strftime("%d/%m/%Y %H:%M")}',
                crs_epsg=4326,
            )
            remote_project_id = remote_project.get('id', '')
            self._log(f'  → ID dự án: {remote_project_id}', 'ok')

            total_features = 0
            total_layers = len(vector_layers)

            for idx, qgis_layer in enumerate(vector_layers):
                layer_name = qgis_layer.name()
                geom_type = _qgis_geom_type_to_server(qgis_layer.wkbType())

                self._log(f'Tạo layer: {layer_name} ({geom_type})', 'info')
                QApplication.processEvents()

                # Build field schema from layer fields
                field_schema = {}
                for field in qgis_layer.fields():
                    fname = field.name()
                    if fname in ('remote_id', 'remote_layer_id', 'remote_version'):
                        continue
                    field_schema[fname] = field.typeName()

                # Create layer on server
                remote_layer = self.client.create_layer(
                    project_id=remote_project_id,
                    name=layer_name,
                    geometry_type=geom_type,
                    field_schema=json.dumps(field_schema),
                )
                remote_layer_id = remote_layer.get('id', '')

                # Push features
                feat_count = 0
                for feature in qgis_layer.getFeatures():
                    geom = feature.geometry()
                    coords_json = _qgs_geometry_to_coords_json(geom, geom_type)

                    # Build attributes dict (exclude tracking fields)
                    attrs = {}
                    for field in qgis_layer.fields():
                        fname = field.name()
                        if fname in ('remote_id', 'remote_layer_id', 'remote_version'):
                            continue
                        val = feature.attribute(fname)
                        if val is not None and val != QVariant():
                            attrs[fname] = str(val)

                    self.client.create_feature(
                        layer_id=remote_layer_id,
                        coordinates_json=coords_json,
                        attributes=json.dumps(attrs),
                    )
                    feat_count += 1
                    total_features += 1

                self._log(f'  ✅ {feat_count} features đã đẩy lên.', 'ok')

                # Update progress
                progress_pct = int(((idx + 1) / total_layers) * 100)
                self.progress.setValue(progress_pct)
                QApplication.processEvents()

            self._log(f'Hoàn tất! Đã đẩy {total_layers} layer, '
                      f'{total_features} features.', 'ok')
            self.lbl_last_sync.setText(
                f'Lần đồng bộ cuối: {datetime.now().strftime("%H:%M:%S %d/%m/%Y")}'
            )
            self.lbl_sync_stats.setText(f'⬆ {total_features} features')

            QMessageBox.information(
                self, 'Hoàn tất',
                f'Đã đẩy thành công!\n'
                f'• {total_layers} layer\n'
                f'• {total_features} features'
            )

        except Exception as exc:
            self._log(f'Lỗi đẩy dữ liệu: {exc}', 'error')
            self._log(traceback.format_exc(), 'error')
            QMessageBox.critical(self, 'Lỗi', f'Đẩy lên thất bại:\n{exc}')

    # -- Sync: Pull ----------------------------------------------------------

    def _on_pull(self):
        """Pull data from server - same as downloading a project."""
        if not self.client.is_authenticated:
            QMessageBox.warning(self, 'Chưa đăng nhập', 'Vui lòng đăng nhập trước.')
            self.tabs.setCurrentIndex(0)
            return

        # Refresh project list first
        try:
            projects = self.client.list_projects()
        except Exception as exc:
            QMessageBox.critical(self, 'Lỗi', f'Không thể lấy danh sách dự án:\n{exc}')
            return

        if not projects:
            QMessageBox.information(self, 'Trống', 'Không có dự án nào trên server.')
            return

        # Let user pick project via list dialog
        from qgis.PyQt.QtWidgets import QInputDialog
        project_names = [p.get('name', 'N/A') for p in projects]
        chosen, ok = QInputDialog.getItem(
            self, 'Chọn dự án',
            'Chọn dự án để tải về:',
            project_names, 0, False
        )
        if not ok or not chosen:
            return

        idx = project_names.index(chosen)
        project = projects[idx]

        reply = QMessageBox.question(
            self, 'Xác nhận tải về',
            f'Tải dự án "{chosen}" về QGIS?\n\n'
            'Các layer sẽ được thêm mới (không ghi đè layer hiện tại).',
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No
        )
        if reply != QMessageBox.Yes:
            return

        self._download_project(project.get('id', ''), chosen)
