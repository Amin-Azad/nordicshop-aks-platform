from fastapi import Depends, Header, HTTPException, status
from sqlalchemy.orm import Session

from .database import get_db
from .models import User


def current_user(
    x_demo_user: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> User:
    if not x_demo_user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Choose a demo identity")
    try:
        user_id = int(x_demo_user)
    except ValueError as exc:
        raise HTTPException(status_code=401, detail="Invalid demo identity") from exc
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=401, detail="Unknown demo identity")
    return user


def vendor_user(user: User = Depends(current_user)) -> User:
    if user.role != "vendor" or not user.tenant_id:
        raise HTTPException(status_code=403, detail="Vendor access required")
    if not user.tenant or not user.tenant.active:
        raise HTTPException(status_code=403, detail="Vendor is inactive")
    return user


def admin_user(user: User = Depends(current_user)) -> User:
    if user.role != "admin":
        raise HTTPException(status_code=403, detail="Administrator access required")
    return user
