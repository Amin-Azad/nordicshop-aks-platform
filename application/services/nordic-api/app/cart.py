import os

from redis import Redis


REDIS_URL = os.getenv("NORDICSHOP_REDIS_URL", "redis://localhost:6379/0")


class CartStore:
    def __init__(self):
        self.redis = Redis.from_url(REDIS_URL, decode_responses=True)

    def _key(self, cart_id: str) -> str:
        return f"cart:{cart_id}"

    def get(self, cart_id: str) -> dict[int, int]:
        values = self.redis.hgetall(self._key(cart_id))
        return {int(product_id): int(quantity) for product_id, quantity in values.items()}

    def add(self, cart_id: str, product_id: int, quantity: int):
        self.redis.hincrby(self._key(cart_id), product_id, quantity)

    def remove(self, cart_id: str, product_id: int):
        self.redis.hdel(self._key(cart_id), product_id)

    def clear(self, cart_id: str):
        self.redis.delete(self._key(cart_id))


cart_store = CartStore()
