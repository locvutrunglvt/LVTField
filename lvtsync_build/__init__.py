# -*- coding: utf-8 -*-
"""
LVT Sync - QGIS Plugin
Synchronize field data between QGIS Desktop and LVTField mobile app.
Author: Lộc Vũ Trung
"""


def classFactory(iface):
    """Entry point for QGIS plugin loader."""
    from .lvtsync_plugin import LVTSyncPlugin
    return LVTSyncPlugin(iface)
