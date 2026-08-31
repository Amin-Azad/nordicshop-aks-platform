import os
import sys
from pathlib import Path

API_ROOT = Path(__file__).resolve().parents[1] / "services" / "nordic-api"
sys.path.insert(0, str(API_ROOT))

TEST_DB = Path(__file__).parent / "nordicshop_test.db"
TEST_DB.unlink(missing_ok=True)
os.environ["NORDICSHOP_DATABASE_URL"] = f"sqlite:///{TEST_DB}"

from fastapi.testclient import TestClient
from app.main import app


VENDOR_A = {"X-Demo-User": "1"}
VENDOR_B = {"X-Demo-User": "2"}
ADMIN = {"X-Demo-User": "3"}


def test_health_and_seeded_catalog():
    with TestClient(app) as client:
        assert client.get("/api/health").json()["status"] == "ok"
        products = client.get("/api/products").json()
        assert len(products) == 8
        assert {p["vendor"] for p in products} == {"North Harbour Goods", "Fjell & Form"}


def test_customer_cart_and_checkout_journey():
    with TestClient(app) as client:
        assert client.post("/api/cart/items", json={"cart_id": "customer-test", "product_id": 1, "quantity": 2}).status_code == 201
        cart = client.get("/api/cart/customer-test").json()
        assert cart["items"][0]["quantity"] == 2
        order = client.post("/api/orders", json={"cart_id": "customer-test", "customer_name": "Sofie Jensen", "customer_email": "sofie@example.dk"})
        assert order.status_code == 201
        assert order.json()["items"] == 1


def test_vendor_lists_are_tenant_scoped():
    with TestClient(app) as client:
        a = client.get("/api/vendor/products", headers=VENDOR_A).json()
        b = client.get("/api/vendor/products", headers=VENDOR_B).json()
        assert {p["tenant_id"] for p in a} == {1}
        assert {p["tenant_id"] for p in b} == {2}
        assert {p["id"] for p in a}.isdisjoint({p["id"] for p in b})


def test_vendor_a_cannot_change_vendor_b_product():
    with TestClient(app) as client:
        response = client.patch("/api/vendor/products/5/stock", headers=VENDOR_A, json={"stock": 999})
        assert response.status_code == 404
        vendor_b_product = next(p for p in client.get("/api/vendor/products", headers=VENDOR_B).json() if p["id"] == 5)
        assert vendor_b_product["stock"] != 999


def test_vendor_cannot_use_admin_routes_and_admin_can():
    with TestClient(app) as client:
        assert client.get("/api/admin/summary", headers=VENDOR_A).status_code == 403
        summary = client.get("/api/admin/summary", headers=ADMIN)
        assert summary.status_code == 200
        assert summary.json()["vendors"] == 2


def test_missing_identity_is_rejected():
    with TestClient(app) as client:
        assert client.get("/api/vendor/products").status_code == 401


def test_api_root():
    with TestClient(app) as client:
        response = client.get("/")
        assert response.status_code == 200
        assert response.json() == {"service": "nordic-api"}
