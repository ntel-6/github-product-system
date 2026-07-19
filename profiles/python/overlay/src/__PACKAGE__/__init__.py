"""Product package."""


def health() -> dict[str, bool]:
    """Return a dependency-free readiness signal."""
    return {"ok": True}
