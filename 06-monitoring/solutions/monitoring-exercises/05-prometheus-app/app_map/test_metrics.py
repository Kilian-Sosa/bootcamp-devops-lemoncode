import unittest

from fastapi.testclient import TestClient

from app_map.main import app


class MetricsEndpointTests(unittest.TestCase):
    def test_metrics_is_served_without_a_trailing_slash(self):
        response = TestClient(app).get("/metrics")

        self.assertEqual(response.status_code, 200)
        self.assertIn("process_resident_memory_bytes", response.text)
