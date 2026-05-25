# -*- coding: utf-8 -*-
"""
LVT Sync - Main plugin class following QGIS plugin standards.
Author: Lộc Vũ Trung
"""

import os

from qgis.PyQt.QtWidgets import QAction
from qgis.PyQt.QtGui import QIcon


class LVTSyncPlugin:
    """QGIS Plugin — LVT Sync: synchronize with LVTField server."""

    PLUGIN_NAME = 'LVT Sync'

    def __init__(self, iface):
        """Initialize the plugin.

        Args:
            iface: QgisInterface instance for interacting with QGIS.
        """
        self.iface = iface
        self.plugin_dir = os.path.dirname(__file__)
        self.actions = []
        self.menu = self.PLUGIN_NAME
        self.toolbar = self.iface.addToolBar(self.PLUGIN_NAME)
        self.toolbar.setObjectName('LVTSyncToolbar')
        self._dialog = None

    def initGui(self):
        """Create menu items and toolbar icons inside the QGIS GUI."""
        icon_path = os.path.join(self.plugin_dir, 'icon.png')
        if not os.path.exists(icon_path):
            # Fallback: use a built-in QGIS icon
            icon = QIcon(':/images/themes/default/mActionRefresh.svg')
        else:
            icon = QIcon(icon_path)

        # Main action
        action = QAction(icon, 'LVT Sync — Đồng bộ LVTField', self.iface.mainWindow())
        action.setStatusTip('Mở cửa sổ đồng bộ dữ liệu LVTField')
        action.setWhatsThis('Đồng bộ dữ liệu giữa QGIS Desktop và ứng dụng LVTField')
        action.triggered.connect(self.show_sync_dialog)

        # Add to toolbar
        self.toolbar.addAction(action)

        # Add to Plugins menu
        self.iface.addPluginToMenu(self.menu, action)

        self.actions.append(action)

    def unload(self):
        """Remove the plugin menu items and toolbar icons from QGIS GUI."""
        for action in self.actions:
            self.iface.removePluginMenu(self.menu, action)
            self.iface.removeToolBarIcon(action)

        # Remove toolbar
        if self.toolbar:
            del self.toolbar

        # Close dialog if open
        if self._dialog:
            self._dialog.close()
            self._dialog = None

    def show_sync_dialog(self):
        """Open the main sync dialog."""
        from .lvtsync_dialog import LVTSyncDialog

        if self._dialog is None:
            self._dialog = LVTSyncDialog(self.iface, parent=self.iface.mainWindow())

        self._dialog.show()
        self._dialog.raise_()
        self._dialog.activateWindow()
