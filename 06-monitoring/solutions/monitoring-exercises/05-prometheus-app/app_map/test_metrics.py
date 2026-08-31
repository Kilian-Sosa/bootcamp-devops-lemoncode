import unittest

from fastapi.testclient import TestClient

from app_map.main import app


class MetricsEndpointTests(unittest.TestCase):
    def test_metrics_without_trailing_slash_redirects_to_canonical_endpoint(self):
        response = TestClient(app).get("/metrics", follow_redirects=False)

        self.assertEqual(response.status_code, 307)
        self.assertEqual(response.headers["location"], "/metrics/")

    def test_metrics_asgi_mount_serves_metrics(self):
        response = TestClient(app).get("/metrics/")

        self.assertEqual(response.status_code, 200)
        self.assertIn("process_resident_memory_bytes", response.text)
