from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .auth import admin_user, vendor_user
from .cart import cart_store
from .database import Base, SessionLocal, engine, get_db
from .models import Order, OrderLine, Product, Tenant, User
from .seed import seed_database


ROOT = Path(__file__).resolve().parents[3]


@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)
    with SessionLocal() as db:
        seed_database(db)
    yield


app = FastAPI(title="NordicShop API", version="0.1.0", lifespan=lifespan)


class CartItemIn(BaseModel):
    cart_id: str = Field(min_length=3, max_length=80)
    product_id: int
    quantity: int = Field(default=1, ge=1, le=10)


class CheckoutIn(BaseModel):
    cart_id: str
    customer_name: str = Field(min_length=2, max_length=100)
    customer_email: EmailStr


class StockIn(BaseModel):
    stock: int = Field(ge=0, le=10000)


def product_json(product: Product):
    return {
        "id": product.id,
        "tenant_id": product.tenant_id,
        "vendor": product.tenant.name,
        "name": product.name,
        "description": product.description,
        "category": product.category,
        "price": float(product.price),
        "stock": product.stock,
        "accent": product.accent,
        "active": product.active,
    }


@app.get("/api/health")
def health():
    return {"status": "ok", "service": "nordic-api"}


@app.get("/api/ready")
def ready(db: Session = Depends(get_db)):
    db.scalar(select(func.count(Tenant.id)))
    return {"status": "ready"}


@app.get("/api/products")
def products(category: str | None = Query(default=None), db: Session = Depends(get_db)):
    query = select(Product).join(Product.tenant).where(Product.active.is_(True), Tenant.active.is_(True))
    if category:
        query = query.where(Product.category == category)
    return [product_json(p) for p in db.scalars(query.order_by(Product.id)).all()]


@app.get("/api/products/{product_id}")
def product(product_id: int, db: Session = Depends(get_db)):
    item = db.get(Product, product_id)
    if not item or not item.active or not item.tenant.active:
        raise HTTPException(status_code=404, detail="Product not found")
    return product_json(item)


@app.get("/api/cart/{cart_id}")
def get_cart(cart_id: str, db: Session = Depends(get_db)):
    result = []
    for product_id, quantity in cart_store.get(cart_id).items():
        item = db.get(Product, product_id)
        if item and item.active:
            result.append({**product_json(item), "quantity": quantity, "line_total": float(item.price) * quantity})
    return {"items": result, "total": sum(x["line_total"] for x in result)}


@app.post("/api/cart/items", status_code=201)
def add_cart_item(payload: CartItemIn, db: Session = Depends(get_db)):
    item = db.get(Product, payload.product_id)
    if not item or not item.active or item.stock < payload.quantity:
        raise HTTPException(status_code=400, detail="Product is unavailable")
    cart_store.add(payload.cart_id, payload.product_id, payload.quantity)
    return {"status": "added"}


@app.delete("/api/cart/{cart_id}/items/{product_id}", status_code=204)
def remove_cart_item(cart_id: str, product_id: int):
    cart_store.remove(cart_id, product_id)


@app.post("/api/orders", status_code=201)
def checkout(payload: CheckoutIn, db: Session = Depends(get_db)):
    cart = cart_store.get(payload.cart_id)
    if not cart:
        raise HTTPException(status_code=400, detail="Cart is empty")
    order = Order(customer_name=payload.customer_name, customer_email=payload.customer_email)
    db.add(order)
    for product_id, quantity in cart.items():
        item = db.get(Product, product_id)
        if not item or not item.active or item.stock < quantity:
            raise HTTPException(status_code=409, detail=f"{product_id} is no longer available")
        item.stock -= quantity
        order.lines.append(OrderLine(tenant_id=item.tenant_id, product_id=item.id,
                                     product_name=item.name, quantity=quantity, unit_price=item.price))
    db.commit()
    db.refresh(order)
    cart_store.clear(payload.cart_id)
    return {"order_id": order.id, "status": order.status, "items": len(order.lines)}


@app.get("/api/vendor/me")
def vendor_me(user: User = Depends(vendor_user)):
    return {"id": user.id, "name": user.name, "tenant_id": user.tenant_id, "tenant": user.tenant.name}


@app.get("/api/vendor/products")
def vendor_products(user: User = Depends(vendor_user), db: Session = Depends(get_db)):
    rows = db.scalars(select(Product).where(Product.tenant_id == user.tenant_id).order_by(Product.id)).all()
    return [product_json(p) for p in rows]


@app.patch("/api/vendor/products/{product_id}/stock")
def update_stock(product_id: int, payload: StockIn, user: User = Depends(vendor_user),
                 db: Session = Depends(get_db)):
    item = db.scalar(select(Product).where(Product.id == product_id, Product.tenant_id == user.tenant_id))
    if not item:
        raise HTTPException(status_code=404, detail="Product not found")
    item.stock = payload.stock
    db.commit()
    return product_json(item)


@app.get("/api/vendor/orders")
def vendor_orders(user: User = Depends(vendor_user), db: Session = Depends(get_db)):
    lines = db.scalars(select(OrderLine).where(OrderLine.tenant_id == user.tenant_id).order_by(OrderLine.id.desc())).all()
    return [{"order_id": x.order_id, "product": x.product_name, "quantity": x.quantity,
             "unit_price": float(x.unit_price), "status": x.order.status} for x in lines]


@app.get("/api/admin/summary")
def admin_summary(_: User = Depends(admin_user), db: Session = Depends(get_db)):
    return {
        "vendors": db.scalar(select(func.count(Tenant.id))),
        "active_vendors": db.scalar(select(func.count(Tenant.id)).where(Tenant.active.is_(True))),
        "products": db.scalar(select(func.count(Product.id))),
        "orders": db.scalar(select(func.count(Order.id))),
    }


@app.get("/api/admin/vendors")
def admin_vendors(_: User = Depends(admin_user), db: Session = Depends(get_db)):
    tenants = db.scalars(select(Tenant).order_by(Tenant.id)).all()
    return [{"id": x.id, "name": x.name, "slug": x.slug, "active": x.active} for x in tenants]


@app.patch("/api/admin/vendors/{tenant_id}/toggle")
def toggle_vendor(tenant_id: int, _: User = Depends(admin_user), db: Session = Depends(get_db)):
    tenant = db.get(Tenant, tenant_id)
    if not tenant:
        raise HTTPException(status_code=404, detail="Vendor not found")
    tenant.active = not tenant.active
    db.commit()
    return {"id": tenant.id, "active": tenant.active}


@app.get("/api/admin/orders")
def admin_orders(_: User = Depends(admin_user), db: Session = Depends(get_db)):
    orders = db.scalars(select(Order).order_by(Order.id.desc())).all()
    return [{"id": o.id, "customer": o.customer_name, "status": o.status,
             "created_at": o.created_at.isoformat(), "items": len(o.lines)} for o in orders]


app.mount("/assets", StaticFiles(directory=ROOT / "shared"), name="assets")
app.mount("/vendor", StaticFiles(directory=ROOT / "apps" / "vendor-portal", html=True), name="vendor")
app.mount("/admin", StaticFiles(directory=ROOT / "apps" / "admin-portal", html=True), name="admin")
app.mount("/shop", StaticFiles(directory=ROOT / "apps" / "customer-web", html=True), name="shop")


@app.get("/", include_in_schema=False)
def root():
    return RedirectResponse("/shop/")
