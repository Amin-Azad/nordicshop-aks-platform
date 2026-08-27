from collections import defaultdict


class CartStore:
    """Development cart store. Redis will replace this adapter in the Docker phase."""

    def __init__(self):
        self._carts: dict[str, dict[int, int]] = defaultdict(dict)

    def get(self, cart_id: str) -> dict[int, int]:
        return dict(self._carts[cart_id])

    def add(self, cart_id: str, product_id: int, quantity: int):
        self._carts[cart_id][product_id] = self._carts[cart_id].get(product_id, 0) + quantity

    def remove(self, cart_id: str, product_id: int):
        self._carts[cart_id].pop(product_id, None)

    def clear(self, cart_id: str):
        self._carts.pop(cart_id, None)


cart_store = CartStore()
