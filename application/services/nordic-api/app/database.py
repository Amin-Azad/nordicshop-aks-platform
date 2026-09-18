import os

from sqlalchemy import create_engine, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker


DATABASE_URL = os.getenv("NORDICSHOP_DATABASE_URL", "sqlite:///./nordicshop.db")
connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}
engine = create_engine(
    DATABASE_URL,
    connect_args=connect_args,
    future=True,
    pool_pre_ping=True,
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


def get_db():
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()



def _set_rls_context(session, access_mode: str, tenant_id: int | None = None, order_id: int | None = None) -> None:
    """Set transaction-local PostgreSQL RLS context; no-op for SQLite tests."""
    if session.get_bind().dialect.name != "postgresql":
        return

    session.execute(
        text("SELECT set_config('app.access_mode', :access_mode, true)"),
        {"access_mode": access_mode},
    )
    session.execute(
        text("SELECT set_config('app.tenant_id', :tenant_id, true)"),
        {"tenant_id": "" if tenant_id is None else str(tenant_id)},
    )
    session.execute(
        text("SELECT set_config('app.order_id', :order_id, true)"),
        {"order_id": "" if order_id is None else str(order_id)},
    )


def set_customer_context(session, order_id: int | None = None) -> None:
    _set_rls_context(session, "customer", order_id=order_id)


def set_vendor_context(session, tenant_id: int) -> None:
    _set_rls_context(session, "vendor", tenant_id=tenant_id)


def set_admin_context(session) -> None:
    _set_rls_context(session, "admin")
