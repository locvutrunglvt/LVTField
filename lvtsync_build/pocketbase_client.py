# -*- coding: utf-8 -*-
"""
PocketBase REST API client using only Python stdlib.
No external dependencies required - works in any QGIS environment.
Author: Lộc Vũ Trung
"""

import json
import time
import urllib.request
import urllib.error
import urllib.parse
import ssl


class PocketBaseClient:
    """PocketBase REST API client using only stdlib (no external deps)."""

    DEFAULT_URL = 'https://lvtfield.lvtcenter.it.com'
    MAX_RETRIES = 3
    RETRY_DELAYS = [0.5, 1.0, 2.0]  # seconds between retries

    def __init__(self, base_url=None):
        self.base_url = (base_url or self.DEFAULT_URL).rstrip('/')
        self.token = None
        self.user_email = None
        self.user_id = None
        self.user_name = None
        # SSL context that works on all platforms
        self._ssl_ctx = ssl.create_default_context()
        # Throttle: minimum seconds between requests
        self._last_request_time = 0
        self._min_interval = 0.15  # 150ms between requests

    @property
    def is_authenticated(self):
        """Check if we have a valid auth token."""
        return self.token is not None

    # ------------------------------------------------------------------
    # Low-level HTTP with retry + throttle
    # ------------------------------------------------------------------

    def _request(self, method, path, data=None, params=None):
        """Make an HTTP request to the PocketBase API with retry logic.

        Includes:
        - Throttling (150ms min between requests)
        - Retry with exponential backoff (3 attempts)
        - Handles connection drops gracefully

        Args:
            method: HTTP method (GET, POST, PATCH, DELETE).
            path: API path starting with '/'.
            data: Optional dict to send as JSON body.
            params: Optional dict of query-string parameters.

        Returns:
            Parsed JSON response as dict.

        Raises:
            Exception: On HTTP errors with server message.
        """
        url = f'{self.base_url}{path}'

        # Append query parameters
        if params:
            query = urllib.parse.urlencode(params)
            url = f'{url}?{query}'

        headers = {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Connection': 'close',  # Prevent connection reuse issues
        }
        if self.token:
            headers['Authorization'] = f'Bearer {self.token}'

        body = json.dumps(data).encode('utf-8') if data else None

        # Throttle requests to avoid overwhelming server
        elapsed = time.time() - self._last_request_time
        if elapsed < self._min_interval:
            time.sleep(self._min_interval - elapsed)

        last_error = None
        for attempt in range(self.MAX_RETRIES):
            try:
                req = urllib.request.Request(url, data=body, headers=headers, method=method)
                self._last_request_time = time.time()
                with urllib.request.urlopen(req, timeout=30, context=self._ssl_ctx) as resp:
                    raw = resp.read().decode('utf-8')
                    return json.loads(raw) if raw else {}
            except urllib.error.HTTPError as exc:
                error_body = exc.read().decode('utf-8', errors='replace')
                try:
                    error_json = json.loads(error_body)
                    msg = error_json.get('message', error_body)
                except (json.JSONDecodeError, ValueError):
                    msg = error_body
                raise Exception(f'HTTP {exc.code}: {msg}')
            except (urllib.error.URLError, ConnectionError, OSError) as exc:
                last_error = exc
                if attempt < self.MAX_RETRIES - 1:
                    delay = self.RETRY_DELAYS[attempt]
                    time.sleep(delay)
                    continue
                raise Exception(f'Không thể kết nối server sau {self.MAX_RETRIES} lần thử: {exc}')

    # ------------------------------------------------------------------
    # Authentication
    # ------------------------------------------------------------------

    def login(self, email, password):
        """Authenticate with email and password.

        Returns:
            True on success.

        Raises:
            Exception: On authentication failure.
        """
        result = self._request('POST', '/api/collections/users/auth-with-password', {
            'identity': email,
            'password': password,
        })
        self.token = result.get('token')
        record = result.get('record', {})
        self.user_email = record.get('email', email)
        self.user_id = record.get('id', '')
        self.user_name = record.get('name', '')
        return True

    def logout(self):
        """Clear authentication state."""
        self.token = None
        self.user_email = None
        self.user_id = None
        self.user_name = None

    # ------------------------------------------------------------------
    # Projects
    # ------------------------------------------------------------------

    def list_projects(self):
        """List all projects owned by current user.

        Returns:
            List of project dicts.
        """
        params = {'filter': f'owner="{self.user_id}"', 'perPage': 200}
        result = self._request('GET', '/api/collections/projects/records', params=params)
        return result.get('items', [])

    def get_project(self, project_id):
        """Get a single project by ID."""
        return self._request('GET', f'/api/collections/projects/records/{project_id}')

    def create_project(self, name, description='', crs_epsg=4326):
        """Create a new project on server.

        Args:
            name: Project name.
            description: Optional description.
            crs_epsg: Coordinate reference system EPSG code.

        Returns:
            Created project dict.
        """
        return self._request('POST', '/api/collections/projects/records', {
            'name': name,
            'description': description,
            'crs_epsg': crs_epsg,
            'owner': self.user_id,
            'device_id': 'qgis-desktop',
        })

    # ------------------------------------------------------------------
    # Layers
    # ------------------------------------------------------------------

    def list_layers(self, project_id):
        """List layers for a project.

        Args:
            project_id: Remote project ID.

        Returns:
            List of layer dicts.
        """
        params = {'filter': f'project_id="{project_id}"', 'perPage': 200}
        result = self._request('GET', '/api/collections/layers/records', params=params)
        return result.get('items', [])

    def create_layer(self, project_id, name, geometry_type, field_schema=None,
                     style_config=None):
        """Create a new layer on server.

        Args:
            project_id: Parent project ID.
            name: Layer name.
            geometry_type: One of 'point', 'linestring', 'polygon'.
            field_schema: JSON string of attribute schema.
            style_config: JSON string of style configuration.

        Returns:
            Created layer dict.
        """
        return self._request('POST', '/api/collections/layers/records', {
            'project_id': project_id,
            'name': name,
            'geometry_type': geometry_type,
            'style_config': style_config or '{}',
            'source_format': 'qgis',
            'field_schema': field_schema or '{}',
            'sort_order': 0,
        })

    # ------------------------------------------------------------------
    # Features
    # ------------------------------------------------------------------

    def list_features(self, layer_id, page=1, per_page=500):
        """List features for a layer.

        Args:
            layer_id: Remote layer ID.
            page: Page number for pagination.
            per_page: Items per page (max 500).

        Returns:
            List of feature dicts.
        """
        params = {
            'filter': f'layer_id="{layer_id}"',
            'perPage': per_page,
            'page': page,
        }
        result = self._request('GET', '/api/collections/features/records', params=params)
        return result.get('items', [])

    def list_all_features(self, layer_id):
        """Fetch ALL features for a layer (handles pagination).

        Args:
            layer_id: Remote layer ID.

        Returns:
            Complete list of feature dicts.
        """
        all_features = []
        page = 1
        while True:
            batch = self.list_features(layer_id, page=page)
            if not batch:
                break
            all_features.extend(batch)
            if len(batch) < 500:
                break
            page += 1
        return all_features

    def create_feature(self, layer_id, coordinates_json, attributes=None, owner=None):
        """Create a new feature on server. NEVER deletes existing data.

        Args:
            layer_id: Parent layer ID.
            coordinates_json: JSON string of coordinates [[lat, lng], ...].
            attributes: JSON string of feature attributes.
            owner: Owner user ID (defaults to current user).

        Returns:
            Created feature dict.
        """
        return self._request('POST', '/api/collections/features/records', {
            'layer_id': layer_id,
            'coordinates_json': coordinates_json,
            'attributes': attributes or '{}',
            'device_id': 'qgis-desktop',
            'version': 1,
            'owner': owner or self.user_id,
        })

    def update_feature(self, feature_id, coordinates_json=None, attributes=None,
                       version=1):
        """Update an existing feature (increments version).

        Args:
            feature_id: Feature record ID.
            coordinates_json: Updated coordinates JSON string.
            attributes: Updated attributes JSON string.
            version: Current version number (will be incremented).

        Returns:
            Updated feature dict.
        """
        payload = {'version': version + 1}
        if coordinates_json is not None:
            payload['coordinates_json'] = coordinates_json
        if attributes is not None:
            payload['attributes'] = attributes
        return self._request('PATCH', f'/api/collections/features/records/{feature_id}',
                             payload)

    # ------------------------------------------------------------------
    # Utilities
    # ------------------------------------------------------------------

    def health_check(self):
        """Check server health.

        Returns:
            True if server is reachable and healthy.
        """
        try:
            result = self._request('GET', '/api/health')
            return result.get('code') == 200
        except Exception:
            return False
