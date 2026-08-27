from sqlalchemy import select
from sqlalchemy.orm import Session

from .models import Product, Tenant, User


PRODUCTS = [
    (1, "Harbour Wool Throw", "Soft recycled-wool throw for cool Nordic evenings.", "Home", 649, 18, "fjord"),
    (1, "Oak Desk Tray", "A quiet place for notes, keys and everyday tools.", "Workspace", 329, 24, "oak"),
    (1, "Coastal Ceramic Set", "Two hand-finished cups in a calm sea-grey glaze.", "Kitchen", 289, 32, "sea"),
    (1, "Linen Market Bag", "Strong washed linen with wide, comfortable handles.", "Living", 219, 40, "linen"),
    (2, "Birch Table Lamp", "Warm, focused light with a simple birch base.", "Lighting", 799, 12, "birch"),
    (2, "Forest Notebook", "Recycled paper, cloth spine and dotted pages.", "Workspace", 149, 65, "forest"),
    (2, "Stone Serving Board", "A compact slate board for bread and small plates.", "Kitchen", 379, 21, "stone"),
    (2, "Everyday Knit Beanie", "A soft merino blend for windy commutes.", "Clothing", 269, 37, "berry"),
]


def seed_database(db: Session):
    if db.scalar(select(Tenant.id).limit(1)):
        return
    north = Tenant(id=1, name="North Harbour Goods", slug="north-harbour")
    fjell = Tenant(id=2, name="Fjell & Form", slug="fjell-form")
    db.add_all([north, fjell])
    db.add_all([
        User(id=1, email="vendor.a@nordicshop.local", name="Anna Lind", role="vendor", tenant_id=1),
        User(id=2, email="vendor.b@nordicshop.local", name="Erik Dahl", role="vendor", tenant_id=2),
        User(id=3, email="admin@nordicshop.local", name="Maja Holm", role="admin", tenant_id=None),
    ])
    for idx, (tenant_id, name, desc, category, price, stock, accent) in enumerate(PRODUCTS, start=1):
        db.add(Product(id=idx, tenant_id=tenant_id, name=name, description=desc, category=category,
                       price=price, stock=stock, accent=accent))
    db.commit()
